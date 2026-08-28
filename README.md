# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

## Wersja 0.4

Wersja 0.4 dodaje **Extended Events Emergency Pack**. Główny collector pozostaje read-only i nie uruchamia sesji XE automatycznie. Sesje Extended Events uruchamiasz świadomie tylko wtedy, gdy są potrzebne do konkretnego incydentu.

## Szybki start

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

Dla diagnostyki Query Store konkretnej bazy:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -Database "MyDatabase"
```

Samodzielny test połączenia:

```powershell
.\Network\Test-SqlConnectivity.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

Collector wykorzystuje `Invoke-Sqlcmd`, a jeżeli nie jest dostępny, próbuje `Invoke-DbaQuery` z modułu dbatools.

## Struktura

```text
SQLDBA-EmergencyToolkit/
├── TSQL/
│   ├── ActiveRequests.sql
│   ├── Blocking.sql
│   ├── WaitStats.sql
│   ├── IOStats.sql
│   ├── Memory.sql
│   ├── TempDB.sql
│   ├── QueryStore.sql
│   ├── Log.sql
│   ├── Backups.sql
│   ├── AgentJobs.sql
│   ├── Replication.sql
│   ├── AG.sql
│   └── XEventsStatus.sql
├── PowerShell/
│   └── Collect-SqlIncident.ps1
├── Network/
│   ├── Test-SqlConnectivity.ps1
│   └── Wireshark-Filters.md
├── XEvents/
│   ├── 01-Blocking.sql
│   ├── 02-Deadlocks.sql
│   ├── 03-LongRunningQueries.sql
│   ├── 04-IOErrors-823-824-825.sql
│   ├── 05-LoginFailures.sql
│   ├── 06-LogGrowth.sql
│   ├── 90-Read-XEventFiles.sql
│   └── 99-Stop-EmergencySessions.sql
├── Incident/
├── Docs/
│   ├── Incident-Checklist.md
│   ├── Network-Incident-Runbook.md
│   └── XEvents-Emergency-Runbook.md
└── README.md
```

## Extended Events Emergency Pack

Pakiet XE zawiera gotowe sesje do:

- blockingu,
- deadlocków,
- długich zapytań,
- błędów I/O 823/824/825,
- błędów logowania 18456,
- wzrostu plików baz danych, w tym logu transakcyjnego.

Szczegółowa instrukcja znajduje się w `Docs/XEvents-Emergency-Runbook.md`.

### Ważne

Skrypty z katalogu `XEvents` **tworzą i uruchamiają sesje server-level Extended Events**. Nie są więc read-only. Główny collector ich nie uruchamia — pobiera wyłącznie stan istniejących sesji `SQLDBA_*` przez `TSQL/XEventsStatus.sql`.

Przy blockingu `blocked_process_report` wymaga ustawionego `blocked process threshold (s) > 0`. Toolkit tylko sprawdza tę konfigurację; nie zmienia jej automatycznie.

## Wynik Collect-SqlIncident.ps1

Przykładowa paczka:

```text
Incident-20260828-112500/
├── SQL/
│   ├── ActiveRequests.csv
│   ├── Blocking.csv
│   ├── WaitStats.csv
│   ├── IOStats.csv
│   ├── Memory.csv
│   ├── TempDB.csv
│   ├── QueryStore.csv
│   ├── Log.csv
│   ├── Backups.csv
│   ├── AgentJobs.csv
│   ├── Replication.csv
│   ├── AG.csv
│   └── XEventsStatus.csv
├── Network/
│   ├── Network-Summary.csv
│   ├── DNS.csv
│   ├── Ping.csv
│   ├── Test-NetConnection.txt
│   ├── ipconfig-all.txt
│   ├── route-print.txt
│   ├── netstat-ano.txt
│   ├── klist.txt
│   └── SPN-query.txt
├── EventLogs/
│   ├── System.csv
│   └── Application.csv
├── Notes/
│   └── incident-notes.txt
└── incident-metadata.csv
```

Jeżeli któryś collector nie może wykonać zapytania, zapisuje plik `*-error.txt` i przechodzi do kolejnych modułów.

## Diagnostyka połączeń SQL Server

Warstwa `Network` pomaga rozdzielić problemy DNS, routingu, TCP, SQL Browser, SPN/Kerberos oraz TLS/pre-login handshake.

Ważna zasada: pozytywny wynik `Test-NetConnection` potwierdza osiągalność TCP, ale nie oznacza jeszcze poprawnego pre-login handshake, TLS ani logowania do SQL Server.

Gotowy runbook znajduje się w `Docs/Network-Incident-Runbook.md`, a filtry Wiresharka w `Network/Wireshark-Filters.md`.

## Narzędzia zewnętrzne

Repozytorium nie przechowuje binariów narzędzi firm trzecich. Warto mieć lokalnie:

- SQL Server Management Studio
- Sysinternals Suite
- Wireshark
- dbatools
- sp_WhoIsActive
- First Responder Kit
- SQL LogScout
- SQL Nexus
- Windows Performance Recorder / Windows Performance Analyzer
- PerfMon

## Szybki scenariusz awarii

1. Nie restartuj usługi SQL Server bez zebrania diagnostyki, jeśli sytuacja na to pozwala.
2. Zapisz dokładny czas rozpoczęcia problemu.
3. Uruchom `Collect-SqlIncident.ps1`.
4. Sprawdź aktywne requesty i blocking.
5. Przeanalizuj waity, IO, pamięć, tempdb oraz log transakcyjny.
6. Sprawdź backupy, SQL Server Agent, AG i replikację, jeśli są używane.
7. Przy problemach z połączeniem sprawdź DNS, port, TCP, SPN/Kerberos, TLS i pre-login handshake oraz zbierz PCAP w Wiresharku.
8. Jeżeli potrzebujesz obserwacji w czasie, uruchom tylko odpowiednią sesję XE z katalogu `XEvents`.
9. Zatrzymaj sesję XE po reprodukcji problemu i zachowaj `.xel` razem z paczką incydentu.
10. Zachowaj całą paczkę incydentu przed restartem lub zmianą konfiguracji.

## Uprawnienia

Część DMV wymaga `VIEW SERVER STATE` lub odpowiednich uprawnień w nowszych wersjach SQL Server. Dane Agent/backup/replikacja mogą wymagać dostępu do `msdb` oraz `distribution`.

Polecenia `setspn` i `klist` służą tu do diagnostyki. Skrypt nie dodaje ani nie usuwa SPN.

Tworzenie i zarządzanie serwerowymi sesjami Extended Events wymaga odpowiednich uprawnień serwerowych.

## Bezpieczeństwo

Skrypty diagnostyczne w katalogu `TSQL` są przeznaczone do odczytu. Skrypty w katalogu `XEvents` wykonują zmiany polegające na utworzeniu, uruchomieniu lub zatrzymaniu sesji Extended Events i są celowo oddzielone od collectorów read-only.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
