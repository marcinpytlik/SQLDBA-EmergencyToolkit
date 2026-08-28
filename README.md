# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

## Wersja 0.9

Wersja 0.9 dodaje **Incident Report Generator**.

Po zakończeniu collectora toolkit automatycznie analizuje zebrane pliki CSV i tworzy:

- `Incident-Summary.md`
- `Incident-Findings.csv`

Wyniki są grupowane jako:

- Critical
- Warning
- OK

Raport jest heurystycznym triage i nie zastępuje pełnej analizy RCA.

## Szybki start

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

### FCI — automatyczne wykrycie aktywnego noda

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

### Availability Group

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLAGLISTENER,1433" `
    -ComputerName "SQLAG02"
```

## Incident Report Generator

Generator znajduje się w:

```text
Reports/New-IncidentSummary.ps1
```

Można go również uruchomić samodzielnie dla istniejącej paczki:

```powershell
.\Reports\New-IncidentSummary.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"
```

Analizowane są obecnie m.in.:

- blocking,
- latency plików SQL,
- wolne miejsce na wolumenach,
- stan nodów klastra,
- błędy poszczególnych collectorów.

Przykładowe wyniki:

```text
Critical
- Blocking: Detected 5 blocking rows.
- StorageIO: High file latency 54.0 ms for D:\Data\MyDb.mdf.

Warning
- FreeSpace: D: has 16.2% free.
- Collector: 1 collector error file was generated.

OK
- Cluster: All captured cluster nodes are Up.
```

Progi są celowo traktowane jako heurystyki operacyjne, a nie SLA. Na przykład latency z `sys.dm_io_virtual_file_stats` jest kumulowane od startu instancji i należy je korelować z bieżącym workloadem oraz licznikami Windows.

## Wynik collectora

Przykładowa paczka v0.9:

```text
Incident-YYYYMMDD-HHMMSS/
├── SQL/
├── Network/
├── OS/
├── Storage/
├── Cluster/
├── EventLogs/
├── Notes/
├── incident-metadata.csv
├── Incident-Findings.csv
├── Incident-Summary.md
└── Incident-Report-Console.txt
```

## Storage & IO Emergency Pack

Toolkit koreluje:

- latency per plik SQL Server,
- ustawienia autogrowth,
- liczbę VLF,
- IO tempdb,
- wolne miejsce na wolumenach,
- liczniki dysków Windows,
- aktywny node FCI.

Szczegółowy runbook: `Docs/Storage-IO-Emergency-Runbook.md`.

## FCI & Cluster Emergency Pack

Toolkit potrafi zebrać snapshot klastra oraz opcjonalnie samodzielnie rozwiązać aktywny node FCI przez `-ResolveFciActiveNode`.

Żaden skrypt cluster collectora nie wykonuje failoveru ani zmian w konfiguracji klastra.

## Remote Server Collector

`ServerInstance` wskazuje endpoint SQL Server, a `ComputerName` konkretny host Windows. Dla FCI pozwala to osobno wskazać VNN i fizyczny node.

## Network

Warstwa Network działa z hosta collectora do `ServerInstance`. Pozytywny `Test-NetConnection` potwierdza osiągalność TCP, ale nie gwarantuje poprawnego TLS/pre-login handshake ani logowania SQL Server.

## Extended Events

Sesje XE w katalogu `XEvents` nie są uruchamiane automatycznie. Główny collector jedynie odczytuje ich stan.

## ProcDump i WPR

ProcDump i WPR/WPA pozostają akcjami ręcznymi. Toolkit nie uruchamia automatycznie dumpów ani trace ETW.

## Fallback

Jeżeli resolver FCI, zdalny CIM, Event Log, collector klastra, storage lub generator raportu nie działa, toolkit zapisuje `*-error.txt` i kontynuuje pozostałe kroki.

## Wymagania

Typowo potrzebne są:

- `Invoke-Sqlcmd` lub `Invoke-DbaQuery`,
- `VIEW SERVER STATE` lub odpowiednie nowsze uprawnienia SQL Server,
- moduł `FailoverClusters` dla diagnostyki FCI,
- uprawnienia do zdalnego CIM/Event Log,
- poprawny DNS i firewall.

## Bezpieczeństwo

Collectory `TSQL`, `Network`, `OS`, `Storage`, `Cluster` oraz generator raportu są przeznaczone do odczytu.

Nie wykonują shrink, zmian rozmiarów plików, restartów usług, failoveru ani zmian konfiguracji storage.

Skrypty `XEvents` są wyjątkiem — świadomie tworzą, uruchamiają lub zatrzymują sesje Extended Events.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
