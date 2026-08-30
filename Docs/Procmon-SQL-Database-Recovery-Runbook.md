# Procmon SQL Server – Scenario 03: User Database Startup & Crash Recovery

## Cel scenariusza

Celem laboratorium jest obserwacja uruchamiania bazy użytkownika oraz mechanizmu crash recovery w SQL Server przy użyciu Process Monitor (Procmon), SQL Server ERRORLOG, `sys.dm_db_page_info`, `sys.dm_db_database_page_allocations`, `sys.fn_PhysLocFormatter(%%physloc%%)`, stosów wywołań Procmon oraz korelacji offsetu pliku MDF z numerem strony SQL Server.

Scenariusz składa się z dwóch części:

1. **Normalny restart usługi SQL Server** – obserwacja otwierania MDF/LDF, odczytu stron systemowych i standardowego recovery podczas uruchamiania.
2. **Kontrolowany crash recovery** – zatwierdzona zmiana rekordu bez checkpointu, `SHUTDOWN WITH NOWAIT`, restart instancji i obserwacja fizycznego odczytu oraz późniejszego zapisu konkretnej strony danych.

---

## 1. Ważne założenia bezpieczeństwa

> **UWAGA – LAB ONLY**

Część 03B używa:

```sql
SHUTDOWN WITH NOWAIT;
```

Polecenie zatrzymuje **całą instancję SQL Server bez checkpointu**. Nie wolno wykonywać tego kroku na środowisku produkcyjnym ani na współdzielonej instancji testowej, na której pracują inni użytkownicy. Scenariusz zakłada izolowaną instancję laboratoryjną.

---

## 2. Środowisko testowe

Przykładowe środowisko użyte podczas laboratorium:

```text
SQL Server:     SQL Server 2022 Express
Instance:       MSSQLSERVER
Build:          16.0.4265.3
Database:       ProcmonRecoveryLab
database_id:    71
Recovery model: SIMPLE
```

Pliki:

```text
MDF:
C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\ProcmonRecoveryLab.mdf

LDF:
C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\ProcmonRecoveryLab_log.ldf
```

Podczas obserwowanego eksperymentu oba pliki miały rozmiar:

```text
75 497 472 bytes
```

---

## 3. Zasada mapowania offsetu MDF na PageID

Strona danych SQL Server ma standardowo 8192 bajty. Dla pliku MDF:

```text
PageID = Offset / 8192
```

Przykład:

```text
Offset: 3 080 192
3 080 192 / 8192 = 376
```

Czyli:

```text
Offset 3 080 192 = FileID 1 / PageID 376
```

> **UWAGA**
>
> Nie należy stosować tego przeliczenia do pliku LDF. Offsety logu transakcyjnego nie są numerami stron danych SQL Server.

---

## 4. Przygotowanie bazy laboratoryjnej

```sql
CREATE DATABASE ProcmonRecoveryLab;
GO

USE ProcmonRecoveryLab;
GO

CREATE TABLE dbo.RecoveryTest
(
    Id        int IDENTITY(1,1) NOT NULL,
    SomeValue char(4000) NOT NULL,
    CreatedAt datetime2 NOT NULL
        CONSTRAINT DF_RecoveryTest_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_RecoveryTest
        PRIMARY KEY CLUSTERED (Id)
);
GO

INSERT dbo.RecoveryTest (SomeValue)
SELECT TOP (1000)
    REPLICATE('X', 4000)
FROM sys.all_objects AS a
CROSS JOIN sys.all_objects AS b;
GO

CHECKPOINT;
GO
```

---

## 5. Weryfikacja metadanych bazy

```sql
SELECT
    database_id,
    name,
    state_desc,
    recovery_model_desc
FROM sys.databases
WHERE name = N'ProcmonRecoveryLab';
GO

SELECT
    file_id,
    name,
    type_desc,
    physical_name,
    size * 8.0 / 1024 AS size_mb
FROM sys.master_files
WHERE database_id = DB_ID(N'ProcmonRecoveryLab');
GO
```

---

## 6. Konfiguracja Procmon

Podstawowy filtr:

```text
Process Name  is        sqlservr.exe          Include
Path          contains  ProcmonRecoveryLab    Include
```

Interesujące operacje:

```text
CreateFile
ReadFile
WriteFile
FlushBuffersFile
CloseFile
QueryStandardInformationFile
```

Dla analizy call stack:

```text
Event Properties → Stack
```

---

# Część 03A – normalny restart SQL Server

## 7. Cel

Zaobserwować:

```text
SQL Server startup
→ otwarcie MDF
→ odczyt stron kontrolnych
→ otwarcie LDF
→ analiza logu
→ recovery
→ baza ONLINE
```

Normalny restart nie jest dobrym eksperymentem do udowodnienia crash recovery konkretnej strony użytkownika, ponieważ SQL Server ma możliwość przeprowadzenia kontrolowanego zamknięcia.

---

## 8. Obserwacja normalnego restartu

W badanym przebiegu poprzedni proces SQL Server miał PID `23220`, a nowy proces uruchomił się jako PID `6108`.

Pierwszy kontakt nowego procesu z MDF:

```text
12:35:33.5942868
CreateFile
ProcmonRecoveryLab.mdf
```

Następnie SQL Server otworzył plik w trybie:

```text
Generic Read/Write
Write Through
No Buffering
Random Access
```

---

## 9. Pierwsze odczyty MDF

Pierwszy odczyt:

```text
12:35:33.8395261
ReadFile
Offset: 0
Length: 8192
```

Czyli `PageID = 0`.

Kolejny:

```text
12:35:33.8446760
ReadFile
Offset: 73 728
Length: 8192
```

Obliczenie:

```text
73 728 / 8192 = 9
```

Weryfikacja:

```sql
SELECT *
FROM sys.dm_db_page_info
(
    DB_ID(N'ProcmonRecoveryLab'),
    1,
    9,
    N'DETAILED'
);
GO
```

W badaniu strona `1:9` została zidentyfikowana jako `BOOT_PAGE`.

---

## 10. Otwarcie LDF i odczyty logu

Pierwszy kontakt z LDF:

```text
12:35:33.8452607
CreateFile
ProcmonRecoveryLab_log.ldf
```

Następnie m.in.:

```text
12:35:34.0351939  Offset 0         Length 8192
12:35:34.0368294  Offset 8192      Length 4096
12:35:34.0373166  Offset 2039808   Length 4096
12:35:34.0376705  Offset 4071424   Length 4096
12:35:34.0378125  Offset 6103040   Length 4096
12:35:34.0379955  Offset 8388608   Length 4096
```

oraz większe odczyty:

```text
12:35:34.0408628  Offset 757760  Length 491520
12:35:34.0420654  Offset 794624  Length 491520
```

---

## 11. ERRORLOG – normalny restart

```text
12:35:33.590 Starting up database 'ProcmonRecoveryLab'.
12:35:34.040 Parallel redo is started ... worker pool size [2].
12:35:34.040 1 transactions rolled forward ...
12:35:34.120 0 transactions rolled back ...
12:35:34.130 Parallel redo is shutdown ...
```

To potwierdza wykonanie recovery, ale nie przypisuje pojedynczej operacji Procmon do konkretnego rekordu logu.

---

## 12. Odczyty MDF podczas Parallel Redo

W tym oknie obserwowano m.in.:

```text
Offset 49 152      → page 6
Offset 1 548 288   → page 189
Offset 1 253 376   → page 153
Offset 1 318 912   → page 161
Offset 163 840     → page 20
Offset 139 264     → page 17
```

Każdy z tych odczytów miał `Length = 8192` i `Non-cached`.

---

## 13. Call stack odczytu MDF

Najbardziej wiarygodny fragment:

```text
FCB::ScatterReadInternal
→ FCB::AsyncRead
→ FCB::AsyncReadInternal
→ DiskReadAsync
→ KernelBase!ReadFile
→ ntdll!NtReadFile
→ Windows kernel
→ FLTMGR
```

To potwierdza fizyczny odczyt inicjowany przez warstwę storage engine SQL Server.

---

## 14. Późniejsze zapisy dirty pages

Przykład:

```text
12:35:34.9280718
WriteFile
Offset: 1 253 376
Length: 8192
```

Czyli `PageID = 153`.

Call stack:

```text
BPool::WriteOnlyIfDirty
→ FCB::GatherWriteInternal
→ FCB::AsyncWrite
→ FCB::AsyncWriteInternal
→ DiskWriteAsync
→ KernelBase!WriteFile
→ ntdll!ZwWriteFile
→ Windows kernel
→ FLTMGR
```

Najważniejszy element to `BPool::WriteOnlyIfDirty`, wskazujący zapis dirty page z buffer pool.

---

## 15. Identyfikacja stron systemowych

Badane strony:

```text
1:65
1:20
1:153
1:9
```

Dla stron danych:

```sql
SELECT
    object_id,
    OBJECT_SCHEMA_NAME(object_id, DB_ID()) AS schema_name,
    OBJECT_NAME(object_id, DB_ID()) AS object_name
FROM
(
    VALUES (3), (7), (24)
) AS v(object_id);
GO
```

Wynik:

```text
3  → sys.sysrscols
7  → sys.sysallocunits
24 → sys.sysprufiles
```

Strona `1:9` to `BOOT_PAGE`.

Wniosek: strony z pierwszego przebiegu nie były stronami `dbo.RecoveryTest`.

---

## 16. Identyfikacja stron tabeli użytkownika

```sql
SELECT OBJECT_ID(N'dbo.RecoveryTest') AS RecoveryTestObjectId;
GO
```

W badaniu:

```text
RecoveryTestObjectId = 901578250
```

Alokacje:

```sql
SELECT
    allocated_page_file_id,
    allocated_page_page_id,
    page_type,
    page_type_desc,
    is_allocated,
    allocation_unit_type_desc
FROM sys.dm_db_database_page_allocations
(
    DB_ID(),
    OBJECT_ID(N'dbo.RecoveryTest'),
    NULL,
    NULL,
    'DETAILED'
)
WHERE is_allocated = 1
ORDER BY allocated_page_file_id, allocated_page_page_id;
GO
```

Przykładowe strony:

```text
1:338 IAM_PAGE
1:376 DATA_PAGE
1:384 INDEX_PAGE
1:392 DATA_PAGE
1:393 DATA_PAGE
1:394 DATA_PAGE
...
```

---

# Część 03B – kontrolowany crash recovery

## 17. Cel

Udowodnić zachowanie:

```text
COMMIT
→ brak checkpointu
→ awaryjne zatrzymanie
→ recovery
→ REDO
→ odczyt konkretnej strony danych
→ późniejszy zapis dirty page
```

---

## 18. Lokalizacja konkretnego rekordu

```sql
USE ProcmonRecoveryLab;
GO

SELECT TOP (10)
    Id,
    sys.fn_PhysLocFormatter(%%physloc%%) AS PhysicalLocation,
    CreatedAt
FROM dbo.RecoveryTest
ORDER BY Id;
GO
```

Wynik:

```text
Id  PhysicalLocation
1   (1:376:0)
2   (1:376:1)
3   (1:392:0)
4   (1:392:1)
...
```

Dla `Id = 1`:

```text
FileID = 1
PageID = 376
SlotID = 0
```

Offset:

```text
376 × 8192 = 3 080 192
```

---

## 19. Wartość kontrolna przed UPDATE

```sql
SELECT
    Id,
    LEFT(SomeValue, 20) AS SomeValuePrefix,
    sys.fn_PhysLocFormatter(%%physloc%%) AS PhysicalLocation
FROM dbo.RecoveryTest
WHERE Id = 1;
GO
```

Wynik:

```text
Id = 1
SomeValuePrefix = XXXXXXXXXXXXXXXXXXXX
PhysicalLocation = (1:376:0)
```

---

## 20. CHECKPOINT bazowy

```sql
CHECKPOINT;
GO
```

Po tym checkpointcie nie wykonujemy już kolejnego checkpointu przed awaryjnym zatrzymaniem.

---

## 21. UPDATE kontrolowanego rekordu

```sql
UPDATE dbo.RecoveryTest
SET SomeValue = REPLICATE('R', 4000)
WHERE Id = 1;
GO
```

Kontrola:

```sql
SELECT
    Id,
    LEFT(SomeValue, 20) AS SomeValuePrefix,
    sys.fn_PhysLocFormatter(%%physloc%%) AS PhysicalLocation
FROM dbo.RecoveryTest
WHERE Id = 1;
GO
```

Wynik:

```text
Id = 1
SomeValuePrefix = RRRRRRRRRRRRRRRRRRRR
PhysicalLocation = (1:376:0)
```

Rekord pozostał na tej samej stronie.

---

## 22. Uruchomienie Procmon

```text
Ctrl+E   stop
Ctrl+X   clear
```

Filtry:

```text
Process Name  is        sqlservr.exe          Include
Path          contains  ProcmonRecoveryLab    Include
```

Start capture:

```text
Ctrl+E
```

---

## 23. Awaryjne zatrzymanie instancji

> **UWAGA – STATE CHANGING / INSTANCE-WIDE / LAB ONLY**

```sql
USE master;
GO
SHUTDOWN WITH NOWAIT;
GO
```

Polecenie zatrzymuje całą instancję bez standardowego checkpointu.

---

## 24. Restart SQL Server

```powershell
Start-Service MSSQLSERVER
```

Po starcie instancji zatrzymaj capture Procmon.

---

## 25. Weryfikacja rekordu po crash recovery

```sql
USE ProcmonRecoveryLab;
GO

SELECT
    Id,
    LEFT(SomeValue, 20) AS SomeValuePrefix,
    sys.fn_PhysLocFormatter(%%physloc%%) AS PhysicalLocation
FROM dbo.RecoveryTest
WHERE Id = 1;
GO
```

Wynik:

```text
Id = 1
SomeValuePrefix = RRRRRRRRRRRRRRRRRRRR
PhysicalLocation = (1:376:0)
```

Zatwierdzona zmiana przetrwała awaryjne zatrzymanie.

---

## 26. ERRORLOG – crash recovery

```sql
EXEC sys.xp_readerrorlog
    0,
    1,
    N'ProcmonRecoveryLab';
GO
```

Zaobserwowany timeline:

```text
13:21:02.940 Starting up database 'ProcmonRecoveryLab'.
13:21:03.930 Parallel redo is started ... worker pool size [2].
13:21:03.950 1 transactions rolled forward ...
13:21:03.960 0 transactions rolled back ...
13:21:03.960 Parallel redo is shutdown ...
```

---

## 27. Fizyczny odczyt konkretnej strony użytkownika

Procmon:

```text
13:21:03.9495735
ReadFile
ProcmonRecoveryLab.mdf
Offset: 3 080 192
Length: 8192
TID: 22496
SUCCESS
Non-cached
```

Ponieważ:

```text
3 080 192 / 8192 = 376
```

jest to `Page 1:376`, czyli strona zawierająca kontrolowany rekord `dbo.RecoveryTest.Id = 1` w slocie `0`.

---

## 28. Korelacja czasu REDO

```text
13:21:03.930      Parallel redo started
13:21:03.9495735 ReadFile MDF page 1:376
13:21:03.950      1 transaction rolled forward
13:21:03.960      0 transactions rolled back
13:21:03.960      Parallel redo shutdown
```

Odczyt strony nastąpił około `19.6 ms` po rozpoczęciu Parallel Redo.

---

## 29. Call stack odczytu strony 1:376

Najbardziej wiarygodna część:

```text
FCB::ScatterReadInternal
→ FCB::AsyncRead
→ FCB::AsyncReadInternal
→ DiskReadAsync
→ KernelBase!ReadFile
→ ntdll!NtReadFile
→ Windows kernel
→ FLTMGR
```

Wniosek:

> Podczas udokumentowanego `Parallel redo` SQL Server fizycznie odczytał stronę `1:376` przez własną warstwę storage engine.

---

## 30. Fizyczny zapis tej samej strony

Późniejszy event:

```text
13:21:04.3137809
WriteFile
ProcmonRecoveryLab.mdf
Offset: 3 080 192
Length: 8192
TID: 24380
SUCCESS
Non-cached
Write Through
```

To nadal `Page 1:376`.

Różnica względem odczytu wyniosła około `364 ms`.

---

## 31. Call stack zapisu strony 1:376

Najważniejszy fragment:

```text
BPool::WriteOnlyIfDirty
→ FCB::GatherWriteInternal
→ FCB::AsyncWrite
→ FCB::AsyncWriteInternal
→ DiskWriteAsync
→ KernelBase!WriteFile
→ ntdll!ZwWriteFile
→ Windows kernel
→ FLTMGR
```

Wniosek:

> SQL Server zapisał tę samą stronę przez mechanizm buffer pool / dirty page.

---

## 32. Flush po recovery

```text
13:21:04.3400008
FlushBuffersFile
ProcmonRecoveryLab.mdf

13:21:04.3422861
FlushBuffersFile
ProcmonRecoveryLab_log.ldf
```

---

## 33. Pełny timeline eksperymentu

```text
dbo.RecoveryTest
Id = 1
page = 1:376
offset = 3 080 192
        │
        │ UPDATE
        ▼
XXXXXXXXXXXXXXXXXXXX
        →
RRRRRRRRRRRRRRRRRRRR
        │
        │ COMMIT
        │ brak CHECKPOINT
        ▼
SHUTDOWN WITH NOWAIT
        │
        ▼
restart SQL Server
        │
        ▼
13:21:02.940
Starting up database
        │
        ▼
SQL Server czyta LDF
        │
        ▼
13:21:03.930
Parallel redo started
        │
        ▼
13:21:03.9495735
ReadFile MDF
page 1:376
offset 3 080 192
        │
        │ FCB::ScatterReadInternal
        │ → FCB::AsyncRead
        │ → DiskReadAsync
        │ → ReadFile
        ▼
13:21:03.950
1 transaction rolled forward
        │
        ▼
13:21:03.960
0 transactions rolled back
Parallel redo shutdown
        │
        ▼
rekord po recovery
RRRRRRRRRRRRRRRRRRRR
        │
        ▼
13:21:04.3137809
WriteFile MDF
page 1:376
offset 3 080 192
        │
        │ BPool::WriteOnlyIfDirty
        │ → FCB::GatherWriteInternal
        │ → FCB::AsyncWrite
        │ → DiskWriteAsync
        │ → WriteFile
        ▼
FlushBuffersFile MDF
```

---

## 34. Co ten eksperyment udowadnia

1. `COMMIT` nie oznacza, że zmieniona strona danych musi być już fizycznie zapisana do MDF.
2. Zatwierdzona transakcja może przetrwać awaryjne zatrzymanie dzięki logowi transakcyjnemu.
3. SQL Server przy starcie wykonuje recovery.
4. ERRORLOG pokazał fazę `Parallel redo`.
5. W czasie redo SQL Server odczytał konkretną stronę użytkownika `1:376`.
6. Na tej stronie znajdował się kontrolowany rekord `dbo.RecoveryTest.Id = 1`.
7. ERRORLOG raportował `1 transaction rolled forward`.
8. Rekord po recovery zawierał zatwierdzoną wartość `RRRR...`.
9. Ta sama strona została później fizycznie zapisana do MDF.
10. Call stack zapisu zawierał `BPool::WriteOnlyIfDirty`.

---

## 35. Czego eksperyment NIE udowadnia

Nie należy pisać:

```text
konkretny ReadFile = dokładnie ten jeden log record REDO
```

Procmon pokazuje fizyczne I/O, ale nie semantykę konkretnego rekordu logu transakcyjnego.

Nie mamy też publicznego symbolu w rodzaju:

```text
RedoLogRecord → page 1:376
```

Poprawne sformułowanie:

> Podczas udokumentowanego okna Parallel Redo SQL Server fizycznie odczytał stronę `1:376`, na której znajdował się testowy rekord. W tej samej fazie ERRORLOG raportował wykonanie jednej transakcji roll-forward. Po recovery zatwierdzona zmiana była obecna, a strona została następnie fizycznie zapisana jako dirty page.

---

## 36. Ostrożność przy interpretacji symboli

W publicznych symbolach mogą pojawiać się nazwy:

```text
BootPagePtr::Release
EntityVerMgr::SetEntityVersion
DbVerStateMgr::IsDbAlwaysVersioned
DBMgr::ShutdownDB
AutoOpenDB::Open
FsGarbageCollector::ProcessFsGarbageCollection
```

Nie należy automatycznie przypisywać im znaczenia semantycznego dla konkretnego eventu.

Przykład: `BootPagePtr::Release` w stacku zapisu offsetu `3 080 192` nie oznacza, że zapisywana była boot page. Offset jednoznacznie wskazuje `Page 1:376`.

---

## 37. Kierunek czytania stacku Procmon

Procmon pokazuje `frame 0` jako górę stosu. Przy analizie przyczynowej wygodniej czytać od dołu do góry:

```text
SQL Server worker
→ storage engine
→ FCB
→ DiskReadAsync / DiskWriteAsync
→ Win32 API
→ kernel
→ filesystem filters
```

---

## 38. FLTMGR nie oznacza końca fizycznego I/O

Końcowe ramki `FLTMGR.SYS` oznaczają przejście przez Windows Filter Manager. Nie oznacza to, że SQL Server kończy I/O w FLTMGR.

---

## 39. Najważniejszy wniosek architektoniczny

Scenariusz pokazuje praktyczne działanie zasady WAL:

```text
zmiana strony w pamięci
        ↓
log transaction record
        ↓
COMMIT
        ↓
log zapewnia trwałość transakcji
        ↓
strona danych może pozostać dirty
        ↓
awaria
        ↓
recovery
        ↓
REDO
        ↓
odtworzenie zatwierdzonej zmiany
        ↓
późniejszy zapis strony MDF
```

Dlatego:

> trwałość transakcji nie wymaga, aby wszystkie zmodyfikowane strony danych zostały zapisane do MDF przed zakończeniem `COMMIT`.

---

## 40. Wnioski DBA

Procmon bardzo dobrze pokazuje:

```text
który plik
jaki offset
jaka długość I/O
jaki proces
jaki wątek
jaki call stack
```

Ale sam Procmon nie zastępuje ERRORLOG, DMV, DBCC, Extended Events ani analizy logu transakcyjnego.

Najbardziej wiarygodny obraz powstaje po korelacji:

```text
Procmon
+
ERRORLOG
+
PageID
+
PhysicalLocation
+
call stack
+
stan danych po recovery
```

---

## 41. Minimalny zestaw dowodów dla podobnego incydentu

```text
1. dokładny czas startu bazy
2. wpisy ERRORLOG recovery
3. fizyczny adres rekordu / strony
4. offset pliku MDF
5. ReadFile / WriteFile z Procmon
6. call stack
7. stan rekordu przed awarią
8. stan rekordu po recovery
```

---

## 42. Podsumowanie

W laboratorium udało się przejść od obserwacji ogólnego startupu bazy do śledzenia konkretnego rekordu:

```text
dbo.RecoveryTest
Id = 1
PhysicalLocation = (1:376:0)
```

Zmiana:

```text
XXXXXXXXXXXXXXXXXXXX
→
RRRRRRRRRRRRRRRRRRRR
```

została zatwierdzona, po czym instancję zatrzymano przez `SHUTDOWN WITH NOWAIT`.

Po ponownym uruchomieniu ERRORLOG pokazał:

```text
Parallel redo started
1 transaction rolled forward
0 transactions rolled back
```

Procmon zarejestrował fizyczny odczyt:

```text
Page 1:376
Offset 3 080 192
Length 8192
```

oraz późniejszy zapis dokładnie tej samej strony.

Call stack odczytu:

```text
FCB::ScatterReadInternal
→ FCB::AsyncRead
→ DiskReadAsync
→ ReadFile
```

Call stack zapisu:

```text
BPool::WriteOnlyIfDirty
→ FCB::GatherWriteInternal
→ FCB::AsyncWrite
→ DiskWriteAsync
→ WriteFile
```

Scenariusz stanowi praktyczną demonstrację:

```text
WAL
+
Crash Recovery
+
REDO
+
Buffer Pool
+
Physical I/O
```

w SQL Server.

---

## Status scenariusza

```text
Scenario 03 – User Database Startup & Crash Recovery
STATUS: COMPLETE
```

Następny scenariusz:

```text
Scenario 04 – CHECKPOINT
Dirty Page → Physical Write
```
