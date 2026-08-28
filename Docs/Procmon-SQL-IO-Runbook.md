# Procmon: jak podejrzeć zapis SQL Server do plików danych i logu

Ten runbook pokazuje, jak za pomocą Sysinternals Process Monitor (Procmon) prześledzić operacje I/O wykonywane przez `sqlservr.exe`, w szczególności zapisy do plików MDF/NDF/LDF oraz stos wywołań Windows prowadzący do operacji typu `WriteFile`.

> Procmon jest narzędziem diagnostycznym. Na obciążonej produkcji zawsze używaj wąskich filtrów i krótkich okien capture.

## Cel

Chcemy odpowiedzieć na pytania:

- które operacje plikowe wykonuje `sqlservr.exe`,
- do jakich plików zapisuje,
- jaka jest kolejność operacji wokół COMMIT/CHECKPOINT,
- jak wygląda stack dla `WriteFile`,
- gdzie pojawiają się `KERNELBASE.dll`, `ntdll.dll`, `ntfs.sys`, `fltmgr.sys`, `storport.sys` itd.,
- czym różni się zapis do MDF/NDF od zapisu do LDF.

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

Na produkcji najlepiej ograniczać się do konkretnego pliku lub katalogu.

## 2. Jakie operacje obserwować

Nie ograniczaj pierwszego testu tylko do `WriteFile`.

Warto obserwować m.in.:

- `CreateFile`
- `WriteFile`
- `ReadFile`
- `QueryInformationFile`
- `QueryInformationVolume`
- operacje związane z flush/synchronizacją

Po pierwszym przeglądzie możesz zawęzić filtr do:

```text
Operation    is    WriteFile    Include
```

## 3. Kontrolowany test SQL

Najlepiej wykonać test w bazie laboratoryjnej.

Przykład tabeli:

```sql
CREATE TABLE dbo.TestIO
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    SomeValue varchar(8000) NOT NULL
);
```

### Test A - INSERT

```sql
INSERT INTO dbo.TestIO(SomeValue)
VALUES (REPLICATE('X', 1000));
```

### Test B - COMMIT

```sql
BEGIN TRAN;

INSERT INTO dbo.TestIO(SomeValue)
VALUES (REPLICATE('L', 1000));

COMMIT;
```

### Test C - CHECKPOINT

```sql
CHECKPOINT;
```

### Test D - większa porcja danych

```sql
INSERT INTO dbo.TestIO(SomeValue)
SELECT TOP (10000)
       REPLICATE('D', 4000)
FROM sys.all_objects a
CROSS JOIN sys.all_objects b;
```

Po uruchomieniu testu zatrzymaj capture `Ctrl+E`.

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
COMMIT
  -> zapis odpowiedniego fragmentu logu
  -> LDF
```

natomiast dirty pages z buffer pool mogą zostać zapisane do MDF później, np. przez CHECKPOINT.

To dobry sposób, aby zobaczyć praktyczną różnicę między trwałością transakcji a fizycznym zapisem stron danych.

## 5. Stack dla konkretnego zdarzenia

Kliknij dwukrotnie zdarzenie, np.:

```text
sqlservr.exe
WriteFile
D:\SQLData\MyDatabase.mdf
SUCCESS
```

Przejdź do zakładki:

```text
Stack
```

Bez poprawnie skonfigurowanych symboli możesz zobaczyć głównie moduły i offsety:

```text
sqlservr.exe+0x...
KERNELBASE.dll+0x...
ntdll.dll+0x...
ntoskrnl.exe+0x...
ntfs.sys+0x...
```

Po załadowaniu symboli część stacku Windows może zostać rozwiązana do nazw funkcji.

Przykładowa ścieżka może wyglądać mniej więcej tak:

```text
sqlservr.exe
  -> KERNELBASE.dll
  -> ntdll.dll!NtWriteFile
  -> ntoskrnl.exe
  -> fltmgr.sys
  -> ntfs.sys
  -> storport.sys / stornvme.sys / driver storage vendor
```

Dokładny stack zależy od wersji Windows, sterowników i warstwy storage.

## 6. Konfiguracja symboli online

Jeżeli serwer ma dostęp do Internetu, możesz użyć Microsoft Symbol Server.

W Procmon:

```text
Options
-> Configure Symbols...
```

Przykładowy symbol path:

```text
srv*C:\Symbols*https://msdl.microsoft.com/download/symbols
```

`C:\Symbols` będzie lokalnym cache.

Pierwsze otwarcie stacku może być wolniejsze, bo symbole będą pobierane na żądanie.

## 7. Symbole offline

Dla serwera bez Internetu użyj:

```text
PowerShell/Prepare-OfflineSymbols.ps1
```

Skrypt ma dwa tryby:

- `CollectTargets`
- `DownloadSymbols`

### Krok 1 - serwer SQL bez Internetu

Najpierw sprawdź ścieżkę do procesu SQL Server:

```powershell
Get-Process sqlservr | Select-Object -ExpandProperty Path
```

Przykład:

```text
C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn\sqlservr.exe
```

Uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode CollectTargets `
    -WorkingDirectory C:\SQLSymbols `
    -SqlBinnPath "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn"
```

Powstanie m.in.:

```text
C:\SQLSymbols\
├── Targets\
│   ├── Windows\
│   ├── Drivers\
│   └── SQLServer\
├── Logs\
└── SymbolTargets.csv
```

`SymbolTargets.csv` zawiera wersje plików, dzięki czemu wiadomo, dla jakiego buildu przygotowano cache.

### Krok 2 - komputer z Internetem

Na komputerze z Internetem zainstaluj Debugging Tools for Windows i upewnij się, że dostępny jest `symchk.exe`.

Typowa lokalizacja:

```text
C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe
```

Skopiuj na ten komputer katalog `C:\SQLSymbols`, a następnie uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory C:\SQLSymbols
```

Skrypt użyje Microsoft Symbol Server i utworzy lokalny cache:

```text
C:\SQLSymbols\Symbols
```

### Krok 3 - powrót na serwer offline

Skopiuj katalog `Symbols` na serwer, np.:

```text
D:\DBATools\Symbols
```

W Procmon ustaw:

```text
Options
-> Configure Symbols...
```

Symbol path:

```text
D:\DBATools\Symbols
```

Bez adresu internetowego.

## 8. Co pobiera Prepare-OfflineSymbols.ps1

Skrypt zbiera m.in.:

### Windows user mode

- `ntdll.dll`
- `kernel32.dll`
- `KernelBase.dll`
- `advapi32.dll`
- `rpcrt4.dll`
- `ntoskrnl.exe`

### File system / storage drivers

- `ntfs.sys`
- `fltmgr.sys`
- `disk.sys`
- `volmgr.sys`
- `volsnap.sys`
- `storport.sys`
- `stornvme.sys`
- `spaceport.sys`
- `classpnp.sys`

### SQL Server

Jeżeli podasz `-SqlBinnPath`, skrypt kopiuje m.in.:

- `sqlservr.exe`
- `sqllang.dll`
- `sqlmin.dll`
- `sqlos.dll`
- `sqltses.dll`
- `sqlmanager.dll`

Publiczny Microsoft Symbol Server może nie zawierać pełnych prywatnych symboli SQL Server. Dlatego po stronie SQL Server często nadal zobaczysz offsety zamiast nazw funkcji.

## 9. Przydatne kolumny w Procmon

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

`Duration` bywa szczególnie przydatne podczas diagnozy wolnego storage.

## 10. Bezpieczeństwo na produkcji

Nie uruchamiaj szerokiego capture typu:

```text
Process Name is sqlservr.exe
```

na długo na bardzo obciążonej instancji.

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

Zbieraj przez kilkanaście-kilkadziesiąt sekund, wykonaj kontrolowaną operację i zatrzymaj capture.

## 11. Co oznaczają typowe obserwacje

### WriteFile do LDF po COMMIT

Normalne zachowanie wynikające z trwałości transakcji.

### WriteFile do MDF po CHECKPOINT

Normalny zapis dirty pages z buffer pool do plików danych.

### Długi Duration przy WriteFile

Może wskazywać na opóźnienie storage, ale nie przesądza o przyczynie. Koreluj z:

- `sys.dm_io_virtual_file_stats`
- waitami `WRITELOG`, `PAGEIOLATCH_*`
- Windows PerfMon
- Storage & IO Emergency Pack z tego repo

### Stack zawiera driver producenta HBA/SAN/VM

Warto dołączyć ten sterownik do listy plików w `Prepare-OfflineSymbols.ps1`, aby przygotować właściwe symbole, jeśli producent je udostępnia.

## 12. Polecany mini-LAB

Najlepszy zestaw testów:

1. INSERT bez CHECKPOINT
2. INSERT + COMMIT
3. CHECKPOINT
4. duży INSERT
5. opcjonalnie BACKUP DATABASE

Dla każdego porównaj osobno:

- MDF/NDF
- LDF
- plik backupu
- stack wywołań
- Duration

Dzięki temu można bardzo dobrze zobaczyć, jak SQL Server używa Windows I/O w praktyce.
