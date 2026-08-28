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

Parametr `-Database` wskazuje bazę używaną m.in. przez collector Query Store:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -Database "MyDatabase"
```

## 4. Zdalny host Windows

Jeżeli PowerShell uruchamiasz na stacji DBA, a dane OS mają pochodzić z serwera SQL, podaj `-ComputerName`:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -ComputerName "SQLPROD01"
```

W tym przypadku:

- diagnostyka SQL trafia do `SQLPROD01,1433`,
- diagnostyka OS/Event Log/storage jest pobierana z hosta `SQLPROD01`,
- diagnostyka Network pokazuje połączenie z hosta collectora do endpointu SQL.

Przed użyciem możesz sprawdzić dostęp zdalny:

```powershell
Test-WSMan SQLPROD01
Get-CimInstance Win32_OperatingSystem -ComputerName SQLPROD01
Get-WinEvent -ComputerName SQLPROD01 -LogName System -MaxEvents 5
```

## 5. SQL Server FCI

### Gdy znasz aktywny node

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ComputerName "SQLNODE02" `
    -CollectCluster
```

### Automatyczne wykrycie aktywnego noda

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

Toolkit użyje nazwy `SQLFCI` do odnalezienia Network Name FCI i spróbuje ustalić owner node grupy SQL.

Sam resolver można uruchomić osobno:

```powershell
.\Cluster\Resolve-FciActiveNode.ps1 `
    -SqlNetworkName "SQLFCI"
```

Pełny snapshot klastra:

```powershell
.\Cluster\Get-ClusterSnapshot.ps1 `
    -ClusterName "CLUSTER01" `
    -OutputPath ".\ClusterSnapshot"
```

## 6. Availability Group

Dla listenera AG wskaż listener jako `ServerInstance`, a jako `ComputerName` konkretną replikę, której system operacyjny chcesz analizować:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLAGLISTENER,1433" `
    -ComputerName "SQLAG02"
```

## 7. Diagnostyka sieci

Samodzielny test połączenia:

```powershell
.\Network\Test-SqlConnectivity.ps1 `
    -ServerInstance "SQLPROD01,1530"
```

Wyniki obejmują m.in. DNS, ping/TCP, routing, netstat, Kerberos/SPN oraz podstawowe dane potrzebne przy `pre-login handshake timeout`.

Filtry do Wiresharka znajdują się w:

```text
Network/Wireshark-Filters.md
```

Typowy workflow:

```text
DNS -> TCP -> TLS/pre-login -> login -> SQL request
```

Pamiętaj: poprawny `Test-NetConnection` nie potwierdza jeszcze poprawnego TLS/pre-login handshake.

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

Zdalny snapshot Windows:

```powershell
.\OS\Get-RemoteOSSnapshot.ps1 `
    -ComputerName "SQLNODE02" `
    -OutputPath ".\RemoteOSSnapshot"
```

## 9. Diagnostyka storage

Samodzielny snapshot Windows storage:

```powershell
.\OS\Get-StorageSnapshot.ps1 `
    -ComputerName "SQLNODE02" `
    -OutputPath ".\StorageSnapshot"
```

Najważniejsze collectory SQL dla storage możesz też uruchamiać bezpośrednio w SSMS:

```text
TSQL/StorageIO.sql
TSQL/FileGrowth.sql
TSQL/VLF.sql
TSQL/TempdbIO.sql
```

Praktyczny workflow:

```text
Wait Stats -> StorageIO.sql -> physical_name -> wolumen -> Windows disk counters
```

Dla problemów z logiem zwracaj uwagę na `WRITELOG`, growth logu i liczbę VLF. Dla problemów z odczytem koreluj wyniki z `PAGEIOLATCH_*`.

## 10. Skrypty T-SQL

Każdy plik z katalogu `TSQL` można uruchomić ręcznie w SSMS/Azure Data Studio przeciwko właściwej instancji.

Najczęściej używane:

```text
ActiveRequests.sql   - aktywne requesty
Blocking.sql         - blocking
WaitStats.sql        - waity
IOStats.sql          - IO baz i plików
Memory.sql           - pamięć
TempDB.sql           - tempdb
Log.sql              - log transakcyjny
Backups.sql          - historia backupów
AgentJobs.sql        - SQL Agent
Replication.sql      - replikacja
AG.sql               - Availability Groups
StorageIO.sql        - latency plików
FileGrowth.sql       - growth/maxsize
VLF.sql              - liczba VLF
TempdbIO.sql         - IO tempdb
XEventsStatus.sql    - status sesji SQLDBA_*
```

Większość tych skryptów wymaga praw typu `VIEW SERVER STATE` lub odpowiednich nowszych uprawnień w SQL Server 2022+.

## 11. Extended Events Emergency Pack

Skrypty w katalogu `XEvents` **zmieniają stan instancji**, ponieważ tworzą/uruchamiają/zatrzymują sesje XE. Główny collector nie uruchamia ich automatycznie.

Przykład - deadlocki:

1. Otwórz w SSMS:

```text
XEvents/02-Deadlocks.sql
```

2. Wykonaj skrypt świadomie.
3. Odtwórz problem.
4. Zatrzymaj sesje:

```text
XEvents/99-Stop-EmergencySessions.sql
```

5. Odczytaj pliki `.xel` zgodnie z:

```text
XEvents/90-Read-XEventFiles.sql
```

Dostępne scenariusze:

```text
01-Blocking.sql
02-Deadlocks.sql
03-LongRunningQueries.sql
04-IOErrors-823-824-825.sql
05-LoginFailures.sql
06-LogGrowth.sql
```

## 12. Raporty po incydencie

Po pełnym collectorze raporty powstają automatycznie.

Dla istniejącej paczki możesz wygenerować je ponownie.

Najpierw summary:

```powershell
.\Reports\New-IncidentSummary.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"
```

Następnie HTML:

```powershell
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

Raport HTML można otworzyć bezpośrednio w przeglądarce.

## 13. Gdzie zapisywane są dane

Domyślnie:

```text
.\Incidents\Incident-YYYYMMDD-HHMMSS\
```

Możesz zmienić katalog główny:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -OutputRoot "D:\DBA\Incidents"
```

## 14. Najlepszy workflow podczas incydentu

1. Zapisz dokładny czas i objawy.
2. Uruchom główny `Collect-SqlIncident.ps1`.
3. Nie restartuj SQL Server przed zebraniem diagnostyki, jeśli sytuacja na to pozwala.
4. Sprawdź `Incident-Summary.md` oraz `Incident-Report.html`.
5. Przejrzyj `*-error.txt` - pokazują brakujące elementy collectora.
6. Jeżeli problem trwa nadal, włącz tylko odpowiednią sesję XE.
7. Przy problemach sieciowych zbierz dodatkowo PCAP w Wiresharku.
8. Przy problemach poniżej SQL Server rozważ ręcznie WPR/WPA lub ProcDump zgodnie z runbookami.
9. Po incydencie zachowaj całą paczkę do RCA.

## 15. Ważne zasady bezpieczeństwa

Collectory SQL/Network/OS/Storage/Cluster i generatory raportów są przeznaczone do odczytu.

Nie wykonują automatycznie:

- restartów usług,
- failoveru,
- shrink,
- zmian autogrowth,
- zmian konfiguracji storage,
- zmian firewalla/WinRM,
- ProcDump,
- WPR.

Wyjątkiem są skrypty `XEvents`, które świadomie tworzą i zarządzają sesjami Extended Events.

## 16. Szybka ściąga

Standardowa instancja:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQL01,1433"
```

Zdalny OS:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQL01,1433" -ComputerName "SQL01"
```

FCI:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQLFCI,1530" -ResolveFciActiveNode -CollectCluster
```

AG:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "AGLISTENER,1433" -ComputerName "SQLAG01"
```

Sieć:

```powershell
.\Network\Test-SqlConnectivity.ps1 -ServerInstance "SQL01,1433"
```

Raport dla istniejącej paczki:

```powershell
.\Reports\New-IncidentSummary.ps1 -IncidentPath ".\Incidents\Incident-YYYYMMDD-HHMMSS"
.\Reports\New-IncidentHtmlReport.ps1 -IncidentPath ".\Incidents\Incident-YYYYMMDD-HHMMSS"
```

## 17. Procmon i symbole offline dla analizy SQL Server I/O

Pełny runbook znajduje się w:

```text
Docs/Procmon-SQL-IO-Runbook.md
```

Skrypt do przygotowania symboli offline:

```text
PowerShell/Prepare-OfflineSymbols.ps1
```

### Serwer SQL bez Internetu

Najpierw znajdź katalog BINN:

```powershell
Get-Process sqlservr | Select-Object -ExpandProperty Path
```

Następnie zbierz dokładne wersje binariów Windows, sterowników i SQL Server:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode CollectTargets `
    -WorkingDirectory C:\SQLSymbols `
    -SqlBinnPath "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Binn"
```

### Komputer z Internetem

Po skopiowaniu katalogu `C:\SQLSymbols` na komputer z dostępem do Internetu uruchom:

```powershell
.\PowerShell\Prepare-OfflineSymbols.ps1 `
    -Mode DownloadSymbols `
    -WorkingDirectory C:\SQLSymbols
```

Wymagany jest `symchk.exe` z Debugging Tools for Windows.

Powstały cache:

```text
C:\SQLSymbols\Symbols
```

skopiuj z powrotem na serwer SQL i wskaż w Procmon:

```text
Options -> Configure Symbols...
```

np.:

```text
D:\DBATools\Symbols
```

### Minimalny filtr Procmon

```text
Process Name is sqlservr.exe
AND
Path begins with D:\SQLData\
```

Do bardzo krótkiego testu najlepiej użyć konkretnego pliku:

```text
Process Name is sqlservr.exe
AND
Path is D:\SQLData\ProblemDatabase.mdf
```

Następnie kliknij zdarzenie `WriteFile`, otwórz `Event Properties` i przejdź do zakładki `Stack`.

Szczegóły testów INSERT / COMMIT / CHECKPOINT / MDF / LDF oraz interpretacja stacku są opisane w `Docs/Procmon-SQL-IO-Runbook.md`.
