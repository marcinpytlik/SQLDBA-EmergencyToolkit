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
