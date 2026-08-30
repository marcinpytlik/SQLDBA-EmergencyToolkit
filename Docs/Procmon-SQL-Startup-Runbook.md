# Procmon: SQL Server Startup Runbook

Ten runbook pokazuje, jak krok po kroku i w sposób powtarzalny prześledzić start procesu `sqlservr.exe` za pomocą Sysinternals Process Monitor (Procmon).

Celem jest zbudowanie osi czasu od uruchomienia procesu SQL Server do komunikatu:

```text
SQL Server is now ready for client connections.
```

Runbook opiera się na praktycznym capture wykonanym dla SQL Server 2022, instancja domyślna `MSSQLSERVER`. Konkretne timestampy i kolejność pojedynczych operacji mogą różnić się pomiędzy wersjami SQL Server, Windows, konfiguracjami i środowiskami. Procedura oraz filtry pozostają jednak powtarzalne.

> Na produkcji używaj krótkiego capture i wąskich filtrów. Plik PML może zawierać dane środowiskowe procesu, ścieżki, nazwy serwerów i inne informacje wrażliwe. Traktuj go jak materiał diagnostyczny wymagający ochrony.

---

## 1. Wymagania wstępne

### 1.1. Uprawnienia

Procmon uruchom jako Administrator na hoście, na którym działa SQL Server.

Do kontrolowanego restartu usługi potrzebne są odpowiednie uprawnienia do SQL Server Service.

### 1.2. Process Monitor

Wymagany jest Sysinternals Process Monitor.

Przed rozpoczęciem:

1. uruchom Procmon jako Administrator,
2. zatrzymaj bieżący capture: `Ctrl+E`,
3. wyczyść bufor: `Ctrl+X`,
4. upewnij się, że widok jest sortowany rosnąco po `Time of Day`.

### 1.3. Zalecane kolumny Procmon

Włącz co najmniej:

- `Time of Day`
- `Process Name`
- `PID`
- `Operation`
- `Path`
- `Result`
- `Detail`
- `Duration`
- `TID`

Dzięki temu można korelować operacje systemowe z `ERRORLOG`, konkretnymi wątkami i czasem wykonania.

### 1.4. Symbole

Symbole nie są konieczne do zbudowania samej osi czasu, ale są wymagane, jeżeli chcemy analizować `Event Properties -> Stack` i rozwiązywać nazwy funkcji Windows oraz część funkcji SQL Server.

Pełny workflow symboli offline znajduje się w:

```text
Docs/Offline-Symbols-Workflow.md
```

Do przygotowania symboli w tym repo służą:

```text
PowerShell/Copy-SqlSymbolTargetsToWorkstation.ps1
PowerShell/Prepare-OfflineSymbols.ps1
```

Standardowa struktura:

```text
C:\SQLSymbols\
├── Targets\
├── Symbols\
├── Logs\
└── Tools\
```

Na serwerze SQL można zebrać dokładne binaria:

```powershell
.\PowerShell\Copy-SqlSymbolTargetsToWorkstation.ps1 `
    -DestinationPath "\\DBAWORKSTATION\SQLSymbols$\Targets" `
    -IncludeOptionalDrivers
```

Na stacji z dostępem do Internetu:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory "C:\SQLSymbols"
```

Na serwerze offline w Procmon:

```text
Options -> Configure Symbols...
```

Przykładowa konfiguracja:

```text
DbgHelp.dll:
C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll

Symbol path:
D:\DBATools\Symbols
```

W środowisku z Internetem można użyć cache i Microsoft Symbol Server, np.:

```text
srv*C:\Symbols*https://msdl.microsoft.com/download/symbols
```

PDB musi odpowiadać dokładnej wersji binarium. Nie należy zakładać, że wszystkie prywatne symbole SQL Server będą publicznie dostępne.

---

## 2. Przygotowanie capture

### 2.1. Minimalny filtr bazowy

Ustaw:

```text
Process Name    is    sqlservr.exe    Include
```

Na tym etapie nie dodawaj filtra `Operation` ani `Path`.

### 2.2. Przygotowanie restartu

Dla instancji domyślnej:

```powershell
Stop-Service MSSQLSERVER
```

Dla instancji nazwanej:

```powershell
Stop-Service 'MSSQL$NAZWA_INSTANCJI'
```

Sprawdź, czy usługa rzeczywiście się zatrzymała.

### 2.3. Start capture

1. `Ctrl+X` - wyczyść stare zdarzenia.
2. `Ctrl+E` - rozpocznij capture.
3. uruchom usługę SQL Server:

```powershell
Start-Service MSSQLSERVER
```

4. poczekaj aż instancja będzie dostępna,
5. `Ctrl+E` - zatrzymaj capture.

### 2.4. Zapis PML

Zapisz pełny capture jako `Native Process Monitor Format (PML)`, np.:

```text
SQLServer-Startup-Full.pml
```

Nie zapisuj wyłącznie aktualnie przefiltrowanego widoku. Pełny PML pozwala później wielokrotnie zmieniać filtry bez ponownego restartowania SQL Server.

---

# 3. Scenariusz krok po kroku

## ETAP 1 - Process Start i bootstrap Windows

### Filtr

```text
Process Name    is    sqlservr.exe    Include
```

Bez dodatkowych filtrów.

### Szukamy

- `Process Start`
- `Thread Create`
- pierwszych `Load Image`

Zapisz:

- timestamp `Process Start`,
- PID procesu,
- command line,
- current directory,
- pierwszy TID.

W capture referencyjnym:

```text
10:12:38.7681591  Process Start  sqlservr.exe  PID 5288
```

Command line zawierała:

```text
-sMSSQLSERVER
```

Następnie widoczne były m.in.:

```text
sqlservr.exe
ntdll.dll
kernel32.dll
KernelBase.dll
```

`Process Start` traktujemy jako punkt `T0` całego pomiaru.

---

## ETAP 2 - ładowanie modułów SQL Server

### Filtry

```text
Process Name    is    sqlservr.exe    Include
Operation       is    Load Image      Include
Path            contains MSSQL16.MSSQLSERVER Include
```

Dla innej wersji/instancji dostosuj fragment `MSSQL16.MSSQLSERVER`.

### Szukamy pierwszych wystąpień

```text
sqlos.dll
sqltses.dll
sqldk.dll
qds.dll
sqlmin.dll
sqllang.dll
sqlboot.dll
```

Capture referencyjny:

```text
10:12:38.7822872  sqlos.dll
10:12:38.7830818  sqltses.dll
10:12:38.7856139  sqldk.dll
10:12:38.7859689  qds.dll
10:12:38.7946596  sqlmin.dll
10:12:38.7984425  sqllang.dll
10:12:39.0486781  sqlboot.dll
```

Ważne:

> Kolejność `Load Image` pokazuje kolejność mapowania modułów przez loader Windows. Nie należy traktować jej jako diagramu zależności architektury SQL Server.

---

## ETAP 3 - startup parameters z Registry

Usuń filtr `Load Image`.

### Filtry

```text
Process Name    is            sqlservr.exe              Include
Operation       begins with   Reg                       Include
Path            contains      MSSQLServer\Parameters    Include
```

Jeżeli filtr jest zbyt wąski:

```text
Path contains MSSQL16.MSSQLSERVER
```

### Szukamy

```text
SQLArg0
SQLArg1
SQLArg2
```

W capture referencyjnym:

```text
SQLArg0 = -d...\master.mdf
SQLArg1 = -e...\ERRORLOG
SQLArg2 = -l...\mastlog.ldf
```

Znaczenie:

```text
-d = master data file
-e = SQL Server ERRORLOG
-l = master transaction log
```

Referencyjny timestamp odczytu parametrów:

```text
10:12:39.058...
```

Wcześniejsze `NAME NOT FOUND` dla nazw typu `masterdatafile`, `masterlogfile` i `errorlogfile` nie oznaczały błędu startu - SQL Server chwilę później poprawnie enumerował wartości `SQLArg*`.

---

## ETAP 4 - ERRORLOG i rotacja logów

### Filtry

```text
Process Name    is        sqlservr.exe          Include
Path            contains  \MSSQL\Log\ERRORLOG  Include
```

Na początku nie ograniczaj `Operation`.

### Szukamy

- `CreateFile`
- `SetRenameInformationFile`
- `WriteFile`

Typowa rotacja:

```text
ERRORLOG.5 -> ERRORLOG.6
ERRORLOG.4 -> ERRORLOG.5
ERRORLOG.3 -> ERRORLOG.4
ERRORLOG.2 -> ERRORLOG.3
ERRORLOG.1 -> ERRORLOG.2
ERRORLOG   -> ERRORLOG.1
```

Następnie tworzony jest nowy `ERRORLOG`.

W capture referencyjnym pierwszy zapis nastąpił:

```text
10:12:39.1199005
WriteFile ERRORLOG
Offset: 0
Length: 2
```

Potem pojawiały się kolejne sekwencyjne zapisy do pliku.

---

## ETAP 5 - master.mdf

### Filtry

```text
Process Name    is        sqlservr.exe    Include
Path            contains  \master.mdf     Include
```

Bez filtra `Operation`.

### Szukamy

- `CreateFile`
- `Query...`
- `ReadFile`
- `WriteFile`
- `DeviceIoControl`
- `FileSystemControl`

Kluczowe otwarcie może zawierać:

```text
Write Through
No Buffering
Synchronous IO Non-Alert
```

Capture referencyjny:

```text
10:12:39.1317813
ReadFile master.mdf
Offset: 81920
Length: 8192
I/O Flags: Non-cached
```

Dla MDF/NDF:

```text
PageID = Offset / 8192
```

czyli:

```text
81920 / 8192 = 10
```

W tym przypadku był to `master:1:10`.

Opcjonalnie dla SQL Server 2019+:

```sql
USE master;
GO

SELECT *
FROM sys.dm_db_page_info
(
    DB_ID('master'),
    1,
    10,
    'DETAILED'
);
```

W capture referencyjnym strona była rozpoznana jako `SYSCONFIG_PAGE`.

Na potrzeby scenariusza startup nie analizujemy jej dalej - to osobny scenariusz dotyczący konfiguracji instancji.

---

## ETAP 6 - mastlog.ldf

### Filtry

```text
Process Name    is        sqlservr.exe    Include
Path            contains  \mastlog.ldf    Include
```

### Szukamy

- właściwego `CreateFile` z `Generic Read/Write`,
- `Write Through`,
- `No Buffering`,
- pierwszych `ReadFile`,
- pierwszych `WriteFile`.

Capture referencyjny:

```text
10:12:39.5659882
CreateFile mastlog.ldf
Generic Read/Write
Write Through
No Buffering
Random Access
```

Pierwszy odczyt:

```text
10:12:39.6015682
ReadFile
Offset: 0
Length: 8192
```

Następnie widoczne były odczyty po 4096 bajtów, np.:

```text
Offset 8192      Length 4096
Offset 262144    Length 4096
Offset 524288    Length 4096
```

Pierwszy zapis w capture referencyjnym:

```text
10:12:39.6084192
WriteFile
Offset: 626688
Length: 4096
Non-cached, Write Through
```

Ważne:

> Dla LDF nie wyliczamy `PageID = Offset / 8192`. Log transakcyjny ma inną strukturę niż pliki danych MDF/NDF.

---

## ETAP 7 - model

### Filtry

```text
Process Name    is        sqlservr.exe    Include
Path            contains  \model          Include
```

### Szukamy

- pierwszy `CreateFile model.mdf`,
- pierwszy `ReadFile model.mdf`,
- pierwszy `CreateFile modellog.ldf`,
- pierwszy `ReadFile modellog.ldf`.

Capture referencyjny:

```text
10:12:39.9912124  pierwszy kontakt z model.mdf
10:12:40.0557505  ReadFile model.mdf, Offset 0, Length 8192
10:12:40.0602831  pierwszy kontakt z modellog.ldf
10:12:40.1215761  ReadFile modellog.ldf, Offset 0, Length 8192
```

---

## ETAP 8 - tempdb

### Filtry

```text
Process Name    is        sqlservr.exe    Include
Path            contains  tempdb          Include
```

Jeżeli pliki mają inne nazwy, filtruj po rzeczywistych nazwach plików z konfiguracji instancji.

### Szukamy szczególnie

```text
CreateFile
SetPositionInformationFile
SetEndOfFileInformationFile
SetAllocationInformationFile
WriteFile
ReadFile
```

Capture referencyjny:

```text
10:12:40.1399988  pierwszy CreateFile tempdb.mdf
```

Następnie:

```text
10:12:40.3006349  SetPositionInformationFile  Position: 8388608
10:12:40.3006796  SetEndOfFileInformationFile EndOfFile: 8388608
10:12:40.3009511  SetAllocationInformationFile AllocationSize: 8388608
```

Potem SQL Server zapisuje strony 8 KB, np.:

```text
Offset 8192   Length 8192
Offset 16384  Length 8192
Offset 24576  Length 8192
```

oraz zapis strony od offsetu 0.

Ten etap pokazuje inicjalizację roboczej struktury `tempdb` podczas startu. Szczegółowa analiza PFS/GAM/SGAM, data files, logu i wpływu IFI powinna być wykonywana jako osobny scenariusz.

---

## ETAP 9 - msdb

### Filtry

```text
Process Name    is        sqlservr.exe    Include
Path            contains  MSDB            Include
```

### Szukamy

- pierwszy `CreateFile MSDBData.mdf`,
- pierwszy `ReadFile MSDBData.mdf`,
- pierwszy `CreateFile MSDBLog.ldf`,
- pierwszy `ReadFile MSDBLog.ldf`.

Capture referencyjny:

```text
10:12:39.8337068  pierwszy kontakt MSDBData.mdf
10:12:39.8929796  pierwszy ReadFile MSDBData.mdf
10:12:39.8940035  pierwszy kontakt MSDBLog.ldf
10:12:39.9538460  pierwszy ReadFile MSDBLog.ldf
```

W tym capture pierwszy kontakt z `msdb` wystąpił przed pierwszym kontaktem z `model`.

Nie należy zakładać z góry kolejności I/O baz systemowych - należy ją zmierzyć.

---

## ETAP 10 - Resource Database i bazy użytkownika

### Widok wszystkich data files

```text
Process Name    is          sqlservr.exe    Include
Path            ends with   .mdf            Include
```

Jeżeli są pliki dodatkowe:

```text
Path            ends with   .ndf            Include
```

Szukamy pierwszego `CreateFile` dla każdego unikalnego pliku.

W capture referencyjnym pojawiła się również Resource Database:

```text
10:12:39.8390488
...\MSSQL\Binn\mssqlsystemresource.mdf
```

W tym konkretnym capture nie zaobserwowano otwarcia data file bazy użytkownika przed momentem `ready for client connections`.

To również jest prawidłowy wynik pomiaru - nie należy sztucznie zakładać, że każda baza użytkownika musi pojawić się w wybranym oknie czasowym.

---

## ETAP 11 - moment gotowości instancji

Procmon pokazuje fizyczny zapis do `ERRORLOG`, ale nie interpretuje treści wpisu. Dlatego końcowy timestamp korelujemy z SQL Server `ERRORLOG`.

### Procmon

Filtry:

```text
Process Name    is        sqlservr.exe          Include
Path            contains  \MSSQL\Log\ERRORLOG  Include
Operation       is        WriteFile             Include
```

### SQL Server

```sql
EXEC sys.xp_readerrorlog
    0,
    1,
    N'ready for client connections';
```

Szukamy:

```text
SQL Server is now ready for client connections.
```

W capture referencyjnym `ERRORLOG` zawierał:

```text
2026-08-30 10:12:40.410
SQL Server is now ready for client connections.
```

Procmon w tym samym momencie pokazał:

```text
10:12:40.4104494
WriteFile ERRORLOG
Offset: 13814
Length: 638
```

To jest punkt końcowy osi startup.

---

# 4. Referencyjna oś czasu

Poniższa oś pochodzi z jednego konkretnego capture. Ma być przykładem sposobu dokumentowania, a nie wzorcem czasowym dla innych serwerów.

```text
10:12:38.7681591  Process Start sqlservr.exe, PID 5288
        |
        +--> Windows loader / Thread Create
        |
10:12:38.7822872  sqlos.dll
10:12:38.7830818  sqltses.dll
10:12:38.7856139  sqldk.dll
10:12:38.7859689  qds.dll
10:12:38.7946596  sqlmin.dll
10:12:38.7984425  sqllang.dll
        |
10:12:39.0486781  sqlboot.dll
        |
10:12:39.058...   Registry: MSSQLServer\Parameters
                   SQLArg0 -> master.mdf
                   SQLArg1 -> ERRORLOG
                   SQLArg2 -> mastlog.ldf
        |
10:12:39.1199005  pierwszy WriteFile do nowego ERRORLOG
        |
10:12:39.1258084  pierwszy kontakt z master.mdf
10:12:39.1317813  ReadFile master.mdf, offset 81920, 8 KB
        |
10:12:39.8337068  pierwszy kontakt MSDBData.mdf
10:12:39.8390488  pierwszy kontakt mssqlsystemresource.mdf
        |
10:12:39.9912124  pierwszy kontakt model.mdf
        |
10:12:40.1399988  pierwszy kontakt tempdb.mdf
        |
10:12:40.3006796  tempdb SetEndOfFile = 8 MB
        |
10:12:40.4100000  ERRORLOG: SQL Server is now ready for client connections
10:12:40.4104494  Procmon: odpowiadający WriteFile do ERRORLOG
```

Rzeczywista kolejność pierwszego kontaktu z data files w tym capture:

```text
master
  -> msdb
  -> Resource Database
  -> model
  -> tempdb
```

---

## 5. Obliczenie czasu startup

Punkt początkowy:

```text
10:12:38.7681591  Process Start
```

Punkt końcowy wg wpisu ERRORLOG:

```text
10:12:40.4100000  ready for client connections
```

Czas:

```text
~1.642 s
```

Jeżeli jako punkt końcowy przyjmiemy skorelowany `WriteFile` z Procmon:

```text
10:12:40.4104494
```

wynik wynosi około:

```text
1.6422903 s
```

Ważne:

> Nie traktuj tego czasu jako benchmarku SQL Server. Jest to wynik jednej instancji i jednego uruchomienia. W produkcji wpływ mają m.in. liczba baz, recovery, storage, AV/EDR, konfiguracja Windows, wersja SQL Server i inne komponenty.

---

# 6. Szablon dokumentowania własnego startup

```text
Server / Instance :
SQL Server build  :
Windows build     :
Capture date      :
Procmon version   :
PID               :

T0 Process Start              :
First SQL module              :
Startup Parameters            :
ERRORLOG created              :
master first CreateFile       :
master first ReadFile         :
msdb first CreateFile         :
Resource DB first CreateFile  :
model first CreateFile        :
tempdb first CreateFile       :
tempdb SetEndOfFile           :
Ready for client connections  :

Startup duration              :
```

---

# 7. Filtry - szybka ściąga

## Wszystko dla procesu

```text
Process Name is sqlservr.exe Include
```

## Loader

```text
Process Name is sqlservr.exe Include
Operation is Load Image Include
```

## Parametry startowe

```text
Process Name is sqlservr.exe Include
Operation begins with Reg Include
Path contains MSSQLServer\Parameters Include
```

## ERRORLOG

```text
Process Name is sqlservr.exe Include
Path contains \MSSQL\Log\ERRORLOG Include
```

## master

```text
Process Name is sqlservr.exe Include
Path contains \master.mdf Include
```

## master log

```text
Process Name is sqlservr.exe Include
Path contains \mastlog.ldf Include
```

## msdb

```text
Process Name is sqlservr.exe Include
Path contains MSDB Include
```

## model

```text
Process Name is sqlservr.exe Include
Path contains \model Include
```

## tempdb

```text
Process Name is sqlservr.exe Include
Path contains tempdb Include
```

## Wszystkie data files

```text
Process Name is sqlservr.exe Include
Path ends with .mdf Include
Path ends with .ndf Include
```

## ERRORLOG tylko WriteFile

```text
Process Name is sqlservr.exe Include
Path contains \MSSQL\Log\ERRORLOG Include
Operation is WriteFile Include
```

---

# 8. Jak czytać stack Procmon

Dla interesującego zdarzenia:

```text
Event Properties -> Stack
```

Zasada:

```text
lista główna Procmon: chronologia od góry do dołu
stack: historia wywołań przyczynowych czytana zwykle od dołu do góry
```

`U` oznacza user mode, `K` kernel mode.

Przy analizie I/O wygodnie grupować stack jako:

```text
SQL Server
  -> Windows user mode
     -> Windows kernel
        -> filter/file system/storage
```

Nie interpretuj samej obecności `FLTMGR.SYS`, sterownika AV/EDR lub storage jako dowodu przyczyny problemu. Do takiego wniosku potrzebna jest korelacja z czasami, błędami i innymi pomiarami.

Szczegółowa analiza stacków oraz mapowanie `Offset -> PageID -> object/index` znajduje się w:

```text
Docs/Procmon-SQL-IO-Runbook.md
```

---

# 9. Najważniejsze zasady interpretacji

1. `NAME NOT FOUND`, `NOT A DIRECTORY`, `BUFFER OVERFLOW` lub niektóre `INVALID PARAMETER` w pojedynczych operacjach Procmon nie są automatycznie błędami SQL Server. Patrz na cały ciąg operacji i wynik startu.
2. `Load Image` pokazuje kolejność mapowania DLL, a nie pełny diagram zależności architektury SQL Server.
3. Dla MDF/NDF offset wyrównany do 8192 można mapować do początkowego `PageID`.
4. Dla LDF nie stosuj mapowania `Offset / 8192 = PageID`.
5. Procmon pokazuje operacje systemowe, a `ERRORLOG` nadaje im znaczenie z punktu widzenia SQL Server.
6. Najbardziej wartościowa jest korelacja timestampów Procmon + ERRORLOG + DMV/DBCC/Extended Events zależnie od scenariusza.
7. Zawsze zapisuj pełny PML przed rozpoczęciem analizy filtrami.

---

# 10. Wynik końcowy scenariusza

Po wykonaniu runbooka powinieneś potrafić odpowiedzieć na pytania:

- kiedy dokładnie wystartował proces `sqlservr.exe`,
- jakie kluczowe DLL zostały załadowane i w jakiej kolejności,
- skąd SQL Server pobrał `-d`, `-e` i `-l`,
- kiedy nastąpiła rotacja i utworzenie `ERRORLOG`,
- kiedy SQL Server pierwszy raz dotknął `master`, `msdb`, Resource Database, `model` i `tempdb`,
- jakie podstawowe operacje I/O wykonano na plikach,
- kiedy SQL Server zgłosił gotowość do przyjmowania połączeń,
- ile czasu upłynęło od `Process Start` do `ready for client connections`.

To daje powtarzalny sposób analizy startup SQL Server na poziomie procesu, filesystemu i silnika.