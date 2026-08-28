# Jak uruchamiać SQLDBA Emergency Toolkit

Ten dokument opisuje praktyczne uruchamianie narzędzi z repozytorium `SQLDBA-EmergencyToolkit`.

## 1. Przygotowanie

Sklonuj repozytorium i przejdź do jego katalogu:

```powershell
git clone https://github.com/marcinpytlik/SQLDBA-EmergencyToolkit.git
cd .\SQLDBA-EmergencyToolkit
```

Sprawdź politykę wykonywania skryptów PowerShell:

```powershell
Get-ExecutionPolicy -List
```

Jeżeli pliki zostały pobrane z Internetu i Windows je blokuje, możesz odblokować skrypty w lokalnym katalogu repozytorium:

```powershell
Get-ChildItem -Path . -Recurse -Filter *.ps1 | Unblock-File
```

Do collectora SQL potrzebny jest przynajmniej jeden z modułów:

```powershell
Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
Get-Command Invoke-DbaQuery -ErrorAction SilentlyContinue
```

Jeżeli używasz `Invoke-Sqlcmd`, moduł to zwykle `SqlServer`. Alternatywnie można użyć `dbatools`.

## 2. Najprostszy scenariusz - pełny incident collector

Dla standardowej instancji SQL Server:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

Collector utworzy katalog `Incidents\Incident-YYYYMMDD-HHMMSS` i zapisze w nim diagnostykę SQL, sieci, Windows, storage, logów oraz raport końcowy.

Jeżeli instancja używa domyślnego portu i nazwy hosta wystarcza:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01"
```

## 3. Query Store dla konkretnej bazy

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -Database "MyDatabase"
```

## 4. Zdalny host Windows

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -ComputerName "SQLPROD01"
```

W tym przypadku diagnostyka SQL trafia do endpointu SQL, a dane OS/Event Log/storage są pobierane z podanego hosta Windows.

## 5. SQL Server FCI

Gdy znasz aktywny node:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ComputerName "SQLNODE02" `
    -CollectCluster
```

Automatyczne wykrycie aktywnego noda:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

## 6. Availability Group

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLAGLISTENER,1433" `
    -ComputerName "SQLAG02"
```

## 7. Diagnostyka sieci

```powershell
.\Network\Test-SqlConnectivity.ps1 `
    -ServerInstance "SQLPROD01,1530"
```

Filtry do Wiresharka:

```text
Network/Wireshark-Filters.md
```

## 8. Diagnostyka Windows i OS

Lokalny snapshot:

```powershell
.\OS\Get-OSSnapshot.ps1 `
    -OutputPath ".\OSSnapshot"
```

Top procesów:

```powershell
.\OS\Get-TopProcesses.ps1 `
    -Top 25 `
    -OutputPath ".\OSSnapshot"
```

Zdalny snapshot:

```powershell
.\OS\Get-RemoteOSSnapshot.ps1 `
    -ComputerName "SQLNODE02" `
    -OutputPath ".\RemoteOSSnapshot"
```

## 9. Diagnostyka storage

```powershell
.\OS\Get-StorageSnapshot.ps1 `
    -ComputerName "SQLNODE02" `
    -OutputPath ".\StorageSnapshot"
```

Najważniejsze skrypty T-SQL:

```text
TSQL/StorageIO.sql
TSQL/FileGrowth.sql
TSQL/VLF.sql
TSQL/TempdbIO.sql
```

## 10. Skrypty T-SQL

Najczęściej używane:

```text
ActiveRequests.sql
Blocking.sql
WaitStats.sql
IOStats.sql
Memory.sql
TempDB.sql
Log.sql
Backups.sql
AgentJobs.sql
Replication.sql
AG.sql
StorageIO.sql
FileGrowth.sql
VLF.sql
TempdbIO.sql
XEventsStatus.sql
```

## 11. Extended Events Emergency Pack

Skrypty w katalogu `XEvents` zmieniają stan instancji, ponieważ tworzą/uruchamiają/zatrzymują sesje XE. Główny collector nie uruchamia ich automatycznie.

Przykład:

```text
XEvents/02-Deadlocks.sql
XEvents/99-Stop-EmergencySessions.sql
XEvents/90-Read-XEventFiles.sql
```

## 12. Raporty po incydencie

```powershell
.\Reports\New-IncidentSummary.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"

.\Reports\New-IncidentHtmlReport.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"
```

Wynik:

```text
Incident-Summary.md
Incident-Findings.csv
Incident-HealthScore.csv
Incident-Report.html
```

## 13. Gdzie zapisywane są dane

Domyślnie:

```text
.\Incidents\Incident-YYYYMMDD-HHMMSS\
```

Możesz zmienić katalog główny przez `-OutputRoot`.

## 14. Najlepszy workflow podczas incydentu

1. Zapisz dokładny czas i objawy.
2. Uruchom `Collect-SqlIncident.ps1`.
3. Nie restartuj SQL Server przed zebraniem diagnostyki, jeśli sytuacja na to pozwala.
4. Sprawdź `Incident-Summary.md` oraz `Incident-Report.html`.
5. Przejrzyj `*-error.txt`.
6. Jeżeli problem trwa nadal, włącz tylko odpowiednią sesję XE.
7. Przy problemach sieciowych zbierz PCAP w Wiresharku.
8. Przy problemach poniżej SQL Server użyj odpowiedniego runbooka Procmon/WPR/ProcDump.
9. Zachowaj całą paczkę do RCA.

## 15. Ważne zasady bezpieczeństwa

Collectory SQL/Network/OS/Storage/Cluster i generatory raportów są przeznaczone do odczytu. Nie wykonują automatycznie restartów, failoveru, shrink, zmian autogrowth, zmian firewalla/WinRM, ProcDump ani WPR.

Wyjątkiem są skrypty `XEvents`, które świadomie tworzą i zarządzają sesjami Extended Events.

## 16. Szybka ściąga

Standardowa instancja:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQL01,1433"
```

FCI:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQLFCI,1530" -ResolveFciActiveNode -CollectCluster
```

Sieć:

```powershell
.\Network\Test-SqlConnectivity.ps1 -ServerInstance "SQL01,1433"
```

## 17. Procmon i symbole offline dla SQL Server I/O

Pełne dokumenty:

```text
Docs/Procmon-SQL-IO-Runbook.md
Docs/Offline-Symbols-Workflow.md
```

Przyjmujemy standardową strukturę na stacji DBA:

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

### Krok 1 - produkcja

Na serwerze SQL uruchom:

```powershell
.\PowerShell\Copy-SqlSymbolTargetsToWorkstation.ps1 `
    -DestinationPath "\\DBAWORKSTATION\SQLSymbols$\Targets" `
    -IncludeOptionalDrivers
```

Skrypt automatycznie utworzy:

```text
C:\SQLSymbols\Targets\<COMPUTERNAME>
```

oraz zbierze Windows DLL, kernel/storage drivers i binaria wszystkich wykrytych procesów `sqlservr.exe`.

### Krok 2 - stacja DBA z Internetem

Uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory "C:\SQLSymbols"
```

Skrypt rekurencyjnie przejrzy wszystkie serwery w:

```text
C:\SQLSymbols\Targets
```

i pobierze symbole do:

```text
C:\SQLSymbols\Symbols
```

Logi trafią do:

```text
C:\SQLSymbols\Logs
```

### Krok 3 - powrót na serwer offline

Na produkcję kopiujesz przede wszystkim:

```text
C:\SQLSymbols\Symbols
```

np. do:

```text
D:\DBATools\Symbols
```

W Procmon:

```text
Options -> Configure Symbols...
```

Symbol path:

```text
D:\DBATools\Symbols
```

### Minimalny filtr Procmon

```text
Process Name is sqlservr.exe
AND
Path begins with D:\SQLData\
```

Następnie:

```text
WriteFile -> Event Properties -> Stack
```

Szczegóły testów `INSERT`, `COMMIT`, `CHECKPOINT`, MDF/LDF i interpretacji stacku są opisane w `Docs/Procmon-SQL-IO-Runbook.md`.
