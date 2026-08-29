# Procmon: jak podejrzeć zapis SQL Server do plików danych i logu

Ten runbook pokazuje, jak za pomocą Sysinternals Process Monitor (Procmon) prześledzić operacje I/O wykonywane przez `sqlservr.exe`, w szczególności zapisy do plików MDF/NDF/LDF oraz stos wywołań Windows prowadzący do operacji typu `WriteFile`.

> Procmon jest narzędziem diagnostycznym. Na obciążonej produkcji zawsze używaj wąskich filtrów i krótkich okien capture.

Pełny workflow przygotowania symboli offline znajduje się także w:

```text
Docs/Offline-Symbols-Workflow.md
```

## 1. Przygotowanie Procmon

Uruchom Procmon jako Administrator na hoście, na którym działa SQL Server.

Następnie:

1. zatrzymaj capture: `Ctrl+E`,
2. wyczyść bieżący bufor: `Ctrl+X`,
3. otwórz `Filter -> Filter...`.

Minimalny filtr:

```text
Process Name    is    sqlservr.exe    Include
```

Dla konkretnej bazy dodaj np.:

```text
Path    contains    MyDatabase.mdf    Include
```

albo dla całego katalogu danych:

```text
Path    begins with    D:\SQLData\    Include
```

## 2. Jakie operacje obserwować

Na początku nie ograniczaj capture wyłącznie do `WriteFile`. Warto zobaczyć m.in.:

- `CreateFile`
- `WriteFile`
- `ReadFile`
- `QueryInformationFile`
- `QueryInformationVolume`

Po pierwszym przeglądzie możesz zawęzić filtr do:

```text
Operation    is    WriteFile    Include
```

## 3. Kontrolowany test SQL

Najlepiej wykonywać go w bazie laboratoryjnej.

```sql
CREATE TABLE dbo.TestIO
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    SomeValue varchar(8000) NOT NULL
);
```

### INSERT

```sql
INSERT INTO dbo.TestIO(SomeValue)
VALUES (REPLICATE('X', 1000));
```

### COMMIT

```sql
BEGIN TRAN;
INSERT INTO dbo.TestIO(SomeValue)
VALUES (REPLICATE('L', 1000));
COMMIT;
```

### CHECKPOINT

```sql
CHECKPOINT;
```

Po teście zatrzymaj capture `Ctrl+E`.

## 4. MDF/NDF kontra LDF

Warto robić osobne capture.

Dla pliku danych:

```text
Path contains MyDatabase.mdf
```

Dla logu:

```text
Path contains MyDatabase_log.ldf
```

Typowa obserwacja:

```text
COMMIT -> zapis logu -> LDF
```

Dirty pages z buffer pool mogą zostać zapisane do MDF/NDF później, np. przez CHECKPOINT.

## 5. Stack dla konkretnego zdarzenia

Kliknij dwukrotnie interesujące zdarzenie `WriteFile` i przejdź do:

```text
Event Properties -> Stack
```

Bez symboli możesz zobaczyć głównie moduły i offsety:

```text
sqlservr.exe+0x...
KERNELBASE.dll+0x...
ntdll.dll+0x...
ntoskrnl.exe+0x...
ntfs.sys+0x...
```

Po poprawnym załadowaniu symboli część stacku Windows zostanie rozwiązana do nazw funkcji, np.:

```text
sqlservr.exe
  -> KERNELBASE.dll
  -> ntdll.dll!NtWriteFile
  -> ntoskrnl.exe
  -> fltmgr.sys
  -> ntfs.sys
  -> storport.sys / stornvme.sys / vendor driver
```

Dokładny stack zależy od wersji Windows, SQL Server i warstwy storage.

## 6. Standardowa struktura symboli na stacji DBA

Przyjmujemy:

```text
C:\SQLSymbols\
├── Targets\
│   ├── SQLPROD01\
│   ├── SQLPROD02\
│   └── ...
├── Symbols\
├── Logs\
└── Tools\
```

`Targets` przechowuje dokładne binaria z serwerów, a `Symbols` jest wspólnym cache PDB.

## 7. Krok 1 - kopiowanie binariów z produkcji

Na serwerze SQL uruchom:

```powershell
.\PowerShell\Copy-SqlSymbolTargetsToWorkstation.ps1 `
    -DestinationPath "\\DBAWORKSTATION\SQLSymbols$\Targets" `
    -IncludeOptionalDrivers
```

Skrypt automatycznie utworzy podkatalog nazwy serwera, np.:

```text
C:\SQLSymbols\Targets\SQLPROD01\
├── Windows\
├── Drivers\
├── SQLServer\
├── Logs\
├── SymbolTargets.csv
└── CopySummary.csv
```

Skrypt wykrywa również wszystkie działające procesy `sqlservr.exe` i ich katalogi BINN.

## 8. Krok 2 - pobieranie symboli na stacji z Internetem

Na stacji DBA zainstaluj Debugging Tools for Windows. Typowa lokalizacja:

```text
C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe
```

Następnie uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory "C:\SQLSymbols"
```

Skrypt rekurencyjnie przejrzy wszystkie `EXE`, `DLL` i `SYS` w:

```text
C:\SQLSymbols\Targets
```

i zapisze pobrane PDB w:

```text
C:\SQLSymbols\Symbols
```

Logi `symchk.exe` trafią do:

```text
C:\SQLSymbols\Logs
```

## 9. Krok 3 - symbole wracają na serwer offline

Z powrotem na produkcję kopiujesz przede wszystkim:

```text
C:\SQLSymbols\Symbols
```

np. jako:

```text
D:\DBATools\Symbols
```

Nie musisz kopiować z powrotem katalogu `Targets`.

W Procmon ustaw:

```text
Options -> Configure Symbols...
```

Symbol path:

```text
D:\DBATools\Symbols
```

Dla serwera offline bez adresu Microsoft Symbol Server.

## 10. Co jest zbierane

### Windows user mode

- `ntdll.dll`
- `kernel32.dll`
- `KernelBase.dll`
- `advapi32.dll`
- `rpcrt4.dll`
- `ntoskrnl.exe`

### File system / storage

- `ntfs.sys`
- `fltmgr.sys`
- `disk.sys`
- `volmgr.sys`
- `volsnap.sys`
- `storport.sys`
- `classpnp.sys`

Przy `-IncludeOptionalDrivers` również m.in. `stornvme.sys`, `spaceport.sys`, `partmgr.sys`, `volume.sys`, `mountmgr.sys`.

### SQL Server

Domyślnie m.in.:

- `sqlservr.exe`
- `sqllang.dll`
- `sqlmin.dll`
- `sqlos.dll`
- `sqltses.dll`
- `sqlmanager.dll`

Publiczny Microsoft Symbol Server może nie zawierać pełnych prywatnych symboli SQL Server. Dlatego część ramek SQL może nadal pozostać jako `sqlservr.exe+offset`.

## 11. Przydatne kolumny w Procmon

Warto mieć widoczne:

- Time of Day
- Process Name
- PID
- Operation
- Path
- Result
- Detail
- Duration
- TID

## 12. Bezpieczeństwo na produkcji

Nie pozostawiaj szerokiego capture na długo na obciążonej instancji.

Lepszy filtr:

```text
Process Name is sqlservr.exe
AND
Path begins with D:\SQLData\
```

Najlepszy do krótkiego testu:

```text
Process Name is sqlservr.exe
AND
Path is D:\SQLData\ProblemDatabase.mdf
```

Zbieraj przez krótki czas, wykonaj kontrolowaną operację i zatrzymaj capture.

## 13. Interpretacja

### WriteFile do LDF po COMMIT

Normalne zachowanie wynikające z trwałości transakcji.

### WriteFile do MDF po CHECKPOINT

Normalny zapis dirty pages z buffer pool do plików danych.

### Długi Duration przy WriteFile

Może wskazywać na opóźnienie storage, ale nie przesądza o przyczynie. Koreluj z:

- `sys.dm_io_virtual_file_stats`
- `WRITELOG`
- `PAGEIOLATCH_*`
- Windows PerfMon
- Storage & IO Emergency Pack z tego repo

### Stack zawiera driver producenta HBA/SAN/VM

Warto zidentyfikować dokładny sterownik. Microsoft Symbol Server może nie zawierać jego symboli; wtedy trzeba korzystać z symboli producenta, jeśli są dostępne.

## 14. Polecany mini-LAB

1. INSERT bez CHECKPOINT
2. INSERT + COMMIT
3. CHECKPOINT
4. większy INSERT
5. opcjonalnie BACKUP DATABASE

Dla każdego testu porównaj:

- MDF/NDF
- LDF
- stack wywołań
- Duration

To pozwala bardzo dobrze zobaczyć, jak SQL Server przechodzi z własnej warstwy I/O do Windows i storage.

## 15. Offset i Length w zdarzeniu WriteFile

Dla operacji `WriteFile` Procmon pokazuje w polu `Detail` m.in.:

```text
Offset: 3 997 696, Length: 24 576, I/O Flags: Non-cached, Write Through
```

Znaczenie pól:

```text
Offset = od którego bajtu w pliku rozpoczyna się operacja I/O
Length = ile bajtów obejmuje ta operacja I/O
```

Dla plików danych SQL Server (`MDF`/`NDF`) strona ma rozmiar:

```text
8 KB = 8192 bajtów
```

Dlatego `Length` będący wielokrotnością 8192 można przeliczyć na liczbę stron objętych pojedynczym zapisem:

```text
liczba stron = Length / 8192
```

Przykłady:

```text
8192   = 1 strona
16384  = 2 strony
24576  = 3 strony
65536  = 8 stron
131072 = 16 stron
```

Dla LDF nie należy interpretować `Length` jako liczby stron danych 8 KB. Log transakcyjny ma inną strukturę i `Length` oznacza rozmiar konkretnego zapisu logu.

## 16. Wyznaczanie początkowego PageID z Offset dla MDF/NDF

Jeżeli operacja dotyczy pliku danych i offset jest wyrównany do 8192 bajtów, początkowy numer strony można wyznaczyć jako:

```text
PageID = Offset / 8192
```

Przykład z testu:

```text
Offset: 3 997 696
Length: 24 576
```

Obliczenie:

```text
3 997 696 / 8192 = 488
24 576 / 8192 = 3
```

Czyli operacja rozpoczyna się od strony:

```text
PageID 488
```

i obejmuje trzy kolejne strony:

```text
488
489
490
```

Ważne: `PageID` ma znaczenie zawsze w kontekście konkretnego pliku, dlatego pełny identyfikator strony zapisujemy jako:

```text
FileID:PageID
```

np.:

```text
1:488
```

Przed analizą należy potwierdzić `file_id` dla pliku widocznego w Procmonie:

```sql
USE DemoDeploymentDatabase;
GO

SELECT
    file_id,
    name,
    type_desc,
    physical_name
FROM sys.database_files;
```

Nie należy zakładać, że interesujący plik zawsze ma `file_id = 1`, szczególnie przy bazach posiadających wiele plików MDF/NDF.

## 17. Sprawdzenie strony przez sys.dm_db_page_info

Dla SQL Server 2019+ wygodnym sposobem jest `sys.dm_db_page_info`.

Przykład dla strony `1:488`:

```sql
USE DemoDeploymentDatabase;
GO

SELECT
    database_id,
    file_id,
    page_id,
    page_type,
    page_type_desc,
    object_id,
    index_id,
    partition_id,
    alloc_unit_id
FROM sys.dm_db_page_info
(
    DB_ID(),
    1,
    488,
    'DETAILED'
);
```

Do rozpoznania obiektu:

```sql
DECLARE @ObjectId int;

SELECT @ObjectId = object_id
FROM sys.dm_db_page_info
(
    DB_ID(),
    1,
    488,
    'DETAILED'
);

SELECT
    @ObjectId AS ObjectId,
    OBJECT_SCHEMA_NAME(@ObjectId) AS SchemaName,
    OBJECT_NAME(@ObjectId) AS ObjectName;
```

## 18. Sprawdzenie wszystkich stron objętych jednym WriteFile

Dla przykładu:

```text
Offset: 3 997 696
Length: 24 576
```

wyznaczyliśmy strony `488`, `489`, `490`.

Można sprawdzić je jednym zapytaniem:

```sql
USE DemoDeploymentDatabase;
GO

SELECT
    p.page_id,
    p.page_type,
    p.page_type_desc,
    p.object_id,
    OBJECT_SCHEMA_NAME(p.object_id) AS SchemaName,
    OBJECT_NAME(p.object_id) AS ObjectName,
    p.index_id,
    i.name AS IndexName,
    p.partition_id,
    p.alloc_unit_id
FROM
(
    SELECT *
    FROM sys.dm_db_page_info(DB_ID(), 1, 488, 'DETAILED')

    UNION ALL

    SELECT *
    FROM sys.dm_db_page_info(DB_ID(), 1, 489, 'DETAILED')

    UNION ALL

    SELECT *
    FROM sys.dm_db_page_info(DB_ID(), 1, 490, 'DETAILED')
) AS p
LEFT JOIN sys.indexes AS i
    ON i.object_id = p.object_id
   AND i.index_id  = p.index_id
ORDER BY p.page_id;
```

W wykonanym teście wynik był następujący:

```text
PageID  PageType    Schema  ObjectName    Index
488     DATA_PAGE   sys     sysobjvalues  clst
489     DATA_PAGE   sys     sysobjvalues  clst
490     DATA_PAGE   sys     sysobjvalues  clst
```

Wszystkie trzy strony miały ten sam `partition_id` i `alloc_unit_id`, co potwierdziło, że należą do tej samej jednostki alokacji indeksu.

To pozwoliło przejść od pojedynczego zdarzenia Windows:

```text
Procmon WriteFile
Offset 3 997 696
Length 24 576
```

przez:

```text
Offset / 8192 -> PageID 488
Length / 8192 -> 3 strony
```

a następnie do:

```text
1:488, 1:489, 1:490
    -> sys.dm_db_page_info
    -> sys.sysobjvalues
    -> clustered index clst
```

## 19. Alternatywna weryfikacja przez DBCC PAGE

Do głębszej analizy strony można użyć `DBCC PAGE`.

```sql
DBCC TRACEON(3604);
GO

DBCC PAGE
(
    'DemoDeploymentDatabase',
    1,
    488,
    3
);
GO
```

Do szybkiego obejrzenia nagłówka/alokacji można użyć innego poziomu szczegółowości, np. `0`.

`DBCC PAGE` może pokazać m.in. nagłówek strony, sloty i zawartość rekordów. Jest to narzędzie diagnostyczne i wynik należy interpretować ostrożnie.

## 20. Jak czytać informacje alokacyjne DBCC PAGE

Przykładowe informacje:

```text
GAM  = ALLOCATED
SGAM = NOT ALLOCATED
PFS  = ALLOCATED
DIFF = CHANGED
ML   = NOT MIN_LOGGED
```

W uproszczeniu:

- `GAM = ALLOCATED` - extent jest zaalokowany,
- `SGAM = NOT ALLOCATED` - extent nie jest obecnie wskazany jako mixed extent posiadający wolne strony,
- `PFS` - zawiera informacje o stanie zaalokowania i wykorzystania strony,
- `DIFF = CHANGED` - extent został zmieniony od ostatniego pełnego backupu i będzie brany pod uwagę przy backupie differential,
- `ML = NOT MIN_LOGGED` - extent nie jest oznaczony na mapie ML jako zmieniony przez odpowiednią operację minimalnie logowaną.

## 21. Kompletny workflow: Procmon -> strona -> obiekt SQL Server

Praktyczna procedura:

1. W Procmon filtruj:

```text
Process Name is sqlservr.exe
Operation is WriteFile
Path is <pełna ścieżka MDF/NDF>
```

2. Wybierz interesujący `WriteFile`.
3. Zapisz `Offset` i `Length`.
4. Potwierdź `file_id` przez `sys.database_files`.
5. Policz:

```text
FirstPageID = Offset / 8192
PageCount   = Length / 8192
```

6. Wyznacz zakres stron:

```text
FirstPageID ... FirstPageID + PageCount - 1
```

7. Sprawdź strony przez `sys.dm_db_page_info`.
8. Rozwiąż `object_id` i `index_id` do tabeli/indeksu.
9. Opcjonalnie wykonaj `DBCC PAGE` dla szczegółowej analizy.
10. Otwórz `Event Properties -> Stack`, aby połączyć konkretną stronę SQL Server z fizyczną ścieżką wywołania I/O w Windows.

Docelowy łańcuch analizy wygląda więc tak:

```text
Procmon WriteFile
      |
      +-- Path   -> konkretny MDF/NDF -> FileID
      +-- Offset -> FirstPageID
      +-- Length -> liczba stron
      |
      v
FileID:PageID
      |
      v
sys.dm_db_page_info / DBCC PAGE
      |
      v
object_id + index_id
      |
      v
konkretna tabela / indeks
      |
      v
Procmon Stack -> SQL Server -> Windows I/O -> kernel/storage
```

## 22. Case study: CHECKPOINT -> dirty page -> dbo.NewTable2 -> WriteFile

Poniższy przykład pochodzi z praktycznego testu wykonanego dla bazy `DemoDeploymentDatabase`.

### 22.1. Identyfikacja tabeli i indeksu

Najpierw sprawdzono `object_id` oraz indeks tabeli:

```sql
USE DemoDeploymentDatabase;
GO

SELECT
    o.object_id,
    o.name AS ObjectName,
    i.index_id,
    i.name AS IndexName,
    i.type_desc
FROM sys.objects AS o
JOIN sys.indexes AS i
    ON i.object_id = o.object_id
WHERE o.name = N'NewTable2';
```

Wynik testu:

```text
object_id   = 1205579333
ObjectName  = NewTable2
index_id    = 1
IndexName   = PK_NewTable1
type_desc   = CLUSTERED
```

### 22.2. Identyfikacja stron należących do tabeli

Do sprawdzenia stron użyto:

```sql
SELECT
    allocated_page_file_id AS file_id,
    allocated_page_page_id AS page_id,
    page_type_desc,
    allocation_unit_type_desc,
    is_allocated
FROM sys.dm_db_database_page_allocations
(
    DB_ID(),
    OBJECT_ID(N'dbo.NewTable2'),
    1,
    NULL,
    'DETAILED'
)
WHERE is_allocated = 1
ORDER BY allocated_page_file_id, allocated_page_page_id;
```

Wynik:

```text
file_id  page_id  page_type_desc  allocation_unit_type_desc
1        460      IAM_PAGE        IN_ROW_DATA
1        512      DATA_PAGE       IN_ROW_DATA
```

Interesująca nas strona danych to więc:

```text
FileID:PageID = 1:512
```

### 22.3. Wyliczenie offsetu strony 512

Dla strony 8 KB:

```text
Offset = PageID * 8192
```

czyli:

```text
512 * 8192 = 4 194 304
```

W Procmonie należało więc szukać operacji obejmującej offset `4 194 304` w pliku MDF.

### 22.4. Złapany WriteFile

W capture znaleziono dokładnie:

```text
Process   : sqlservr.exe
Operation : WriteFile
Path      : ...\DemoDeploymentDatabase.mdf
Result    : SUCCESS
Offset    : 4 194 304
Length    : 8 192
I/O Flags : Non-cached, Write Through
```

Interpretacja:

```text
StartPage = 4 194 304 / 8192 = 512
PageCount = 8 192 / 8192     = 1
```

Czyli ten pojedynczy `WriteFile` zapisał dokładnie jedną stronę:

```text
1:512
```

która wcześniej została przypisana do:

```text
dbo.NewTable2
PK_NewTable1
DATA_PAGE
```

### 22.5. Wymuszenie flush przez CHECKPOINT

Przed capture wykonano modyfikację danych, a następnie ręczny:

```sql
CHECKPOINT;
GO
```

W stacku zdarzenia `WriteFile` dla strony `1:512` pojawiła się funkcja:

```text
UserCheckpoint
```

co bezpośrednio wiąże fizyczny zapis z ręcznie wywołanym checkpointem.

### 22.6. Stack strony 1:512

Najważniejszy fragment stosu wyglądał następująco:

```text
sqlmin.dll!UserCheckpoint
        ↓
sqlmin.dll!BPool::WriteOnlyDirty
        ↓
sqlmin.dll!FCB::GatherWriteInternal
        ↓
sqlmin.dll!FCB::AsyncWrite
        ↓
sqlmin.dll!FCB::AsyncWriteInternal
        ↓
sqlmin.dll!DiskWriteAsync
        ↓
KERNELBASE.dll!WriteFile
        ↓
ntdll.dll!ZwWriteFile
        ↓
ntoskrnl.exe!NtWriteFile
        ↓
ntoskrnl.exe!IofCallDriver
        ↓
FLTMGR.SYS
```

Nazwy funkcji mogą różnić się pomiędzy buildami SQL Server i Windows, ale idea pozostaje ta sama.

### 22.7. Co pokazuje ten test

Ten przykład pozwolił prześledzić pełny łańcuch:

```text
T-SQL CHECKPOINT
       ↓
UserCheckpoint
       ↓
Buffer Pool
       ↓
BPool::WriteOnlyDirty
       ↓
FCB::GatherWriteInternal
       ↓
DiskWriteAsync
       ↓
Windows WriteFile
       ↓
Kernel / Filter Manager
```

Jednocześnie dzięki korelacji `Offset -> PageID` wiadomo, że fizycznie zapisywana była konkretna strona:

```text
1:512
```

należąca do:

```text
dbo.NewTable2
clustered index PK_NewTable1
```

Pełna korelacja wygląda więc tak:

```text
dbo.NewTable2
object_id 1205579333
index_id 1 / PK_NewTable1
       ↓
DATA_PAGE 1:512
       ↓
Offset 4 194 304
Length 8 192
       ↓
Procmon WriteFile
       ↓
UserCheckpoint
       ↓
BPool::WriteOnlyDirty
       ↓
FCB::GatherWriteInternal
       ↓
DiskWriteAsync
       ↓
WriteFile / ZwWriteFile / NtWriteFile
       ↓
Windows kernel / FLTMGR.SYS
```

To jest praktyczny sposób przejścia od konkretnej tabeli SQL Server aż do rzeczywistej operacji I/O widocznej na poziomie Windows.