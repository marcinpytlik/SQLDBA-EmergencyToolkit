# Offline Symbols Workflow for SQL Server / Procmon

Ten dokument opisuje standardowy workflow przygotowania symboli offline dla analizy SQL Server I/O w Procmon.

## Docelowa struktura na stacji DBA

Przyjmujemy jeden stały katalog roboczy:

```text
C:\SQLSymbols\
├── Targets\
│   ├── SQLPROD01\
│   │   ├── Windows\
│   │   ├── Drivers\
│   │   ├── SQLServer\
│   │   │   ├── Instance-1\
│   │   │   └── Instance-2\
│   │   ├── Logs\
│   │   ├── SymbolTargets.csv
│   │   └── CopySummary.csv
│   └── SQLPROD02\
│       └── ...
├── Symbols\
├── Logs\
└── Tools\
```

Znaczenie katalogów:

- `Targets` - dokładne binaria skopiowane z serwerów produkcyjnych,
- `Symbols` - cache PDB pobrany z Microsoft Symbol Server,
- `Logs` - logi i CSV z działania `symchk.exe`,
- `Tools` - opcjonalne miejsce na dodatkowe narzędzia.

## Krok 1 - udostępnij katalog Targets

Na stacji DBA utwórz:

```powershell
New-Item -ItemType Directory -Path C:\SQLSymbols\Targets -Force
```

Udostępnij katalog w sposób zgodny z polityką bezpieczeństwa organizacji, np. jako:

```text
\\DBAWORKSTATION\SQLSymbols$\Targets
```

Konto uruchamiające collector na serwerze SQL musi mieć prawo zapisu do tego udziału.

## Krok 2 - zbierz binaria z produkcji

Na serwerze SQL uruchom:

```powershell
.\PowerShell\Copy-SqlSymbolTargetsToWorkstation.ps1 `
    -DestinationPath "\\DBAWORKSTATION\SQLSymbols$\Targets" `
    -IncludeOptionalDrivers
```

Skrypt utworzy automatycznie katalog serwera, np.:

```text
C:\SQLSymbols\Targets\SQLPROD01
```

Zbiera m.in.:

### Windows

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

Przy `-IncludeOptionalDrivers` dodatkowo m.in.:

- `stornvme.sys`
- `spaceport.sys`
- `partmgr.sys`
- `volume.sys`
- `mountmgr.sys`

### SQL Server

Skrypt wykrywa działające procesy `sqlservr.exe` i ich katalogi BINN.

Domyślnie zbiera m.in.:

- `sqlservr.exe`
- `sqllang.dll`
- `sqlmin.dll`
- `sqlos.dll`
- `sqltses.dll`
- `sqlmanager.dll`

Opcjonalnie można zebrać wszystkie EXE/DLL z BINN:

```powershell
-IncludeAllSqlBinnFiles
```

## Krok 3 - przygotuj Debugging Tools for Windows

Na stacji DBA z Internetem zainstaluj Debugging Tools for Windows.

Typowa lokalizacja `symchk.exe`:

```text
C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe
```

Sprawdzenie:

```powershell
Test-Path "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe"
```

## Krok 4 - pobierz symbole

Na stacji DBA uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory "C:\SQLSymbols"
```

Skrypt:

1. skanuje rekurencyjnie `C:\SQLSymbols\Targets`,
2. znajduje wszystkie `EXE`, `DLL` i `SYS`,
3. dla każdego pliku uruchamia `symchk.exe`,
4. pobiera zgodne symbole z Microsoft Symbol Server,
5. zapisuje cache w `C:\SQLSymbols\Symbols`,
6. zapisuje logi w `C:\SQLSymbols\Logs`.

Dzięki temu jeden przebieg może obsłużyć wiele serwerów:

```text
C:\SQLSymbols\Targets\SQLPROD01
C:\SQLSymbols\Targets\SQLPROD02
C:\SQLSymbols\Targets\SQLFCINODE01
C:\SQLSymbols\Targets\SQLFCINODE02
```

## Krok 5 - co kopiujemy z powrotem na produkcję

Z powrotem na serwer SQL kopiujemy przede wszystkim:

```text
C:\SQLSymbols\Symbols
```

np. do:

```text
D:\DBATools\Symbols
```

Nie ma potrzeby kopiowania z powrotem katalogu `Targets`.

Opcjonalnie można zachować na serwerze także `SymbolTargets.csv` jako dokumentację wersji binariów.

## Krok 6 - konfiguracja Procmon

Na serwerze SQL:

```text
Procmon
-> Options
-> Configure Symbols...
```

Ustaw symbol path na lokalny katalog, np.:

```text
D:\DBATools\Symbols
```

Dla serwera offline nie dodawaj adresu Microsoft Symbol Server.

## Krok 7 - analiza stacku

Przykładowy filtr Procmon:

```text
Process Name is sqlservr.exe
AND
Path begins with D:\SQLData\
```

Dla pojedynczego pliku:

```text
Process Name is sqlservr.exe
AND
Path is D:\SQLData\ProblemDatabase.mdf
```

Następnie:

```text
WriteFile
-> Event Properties
-> Stack
```

Przykładowe warstwy, które mogą pojawić się w stacku:

```text
sqlservr.exe
KERNELBASE.dll
ntdll.dll!NtWriteFile
ntoskrnl.exe
fltmgr.sys
ntfs.sys
storport.sys / stornvme.sys / vendor driver
```

Dokładny stack zależy od wersji Windows, SQL Server, sterowników, SAN/HBA, hypervisora oraz warstwy filtrującej.

## Uwagi o symbolach SQL Server

Microsoft Public Symbol Server może nie udostępniać pełnych prywatnych symboli SQL Server. W takim przypadku część ramek może pozostać w formie:

```text
sqlservr.exe+0x...
```

Symbole Windows nadal są bardzo przydatne, bo pozwalają lepiej odczytać przejście z user mode do warstwy kernel/file system/storage.

## Bezpieczeństwo

Skrypty do przygotowania symboli:

- nie restartują SQL Server,
- nie zatrzymują usług,
- nie modyfikują rejestru,
- nie zmieniają konfiguracji Windows,
- nie wykonują failoveru,
- nie modyfikują plików baz danych.

Collector jedynie czyta wskazane binaria i kopiuje ich kopie do katalogu docelowego.

## Skrócony workflow

```text
PROD SQL
  |
  | Copy-SqlSymbolTargetsToWorkstation.ps1
  v
C:\SQLSymbols\Targets\<SERVER>
  |
  | Prepare-OfflineSymbols.ps1 -Mode DownloadSymbols
  v
Microsoft Symbol Server
  |
  v
C:\SQLSymbols\Symbols
  |
  | copy back
  v
PROD SQL: D:\DBATools\Symbols
  |
  v
Procmon -> WriteFile -> Stack
```
