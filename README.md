# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

## Wersja 0.7

Wersja 0.7 dodaje **FCI & Cluster Emergency Pack**.

Toolkit potrafi teraz:

- zebrać snapshot Windows Server Failover Cluster,
- pokazać stany nodów, grup i zasobów,
- zebrać Network Name oraz adresy IP klastra,
- pokazać quorum,
- wykryć zasoby SQL Server / SQL Server Agent,
- zmapować grupę SQL FCI do aktywnego noda,
- opcjonalnie samodzielnie ustalić aktywny node FCI i użyć go jako `ComputerName` dla diagnostyki OS.

Żaden skrypt v0.7 nie wykonuje failoveru ani zmian w konfiguracji klastra.

## Szybki start

### Zwykła instancja

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

### Zdalny host Windows

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -ComputerName "SQLPROD01"
```

### FCI — znany aktywny node

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ComputerName "SQLNODE02" `
    -CollectCluster
```

### FCI — automatyczne wykrycie aktywnego noda

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

Dla `SQLFCI,1530` toolkit użyje nazwy `SQLFCI` jako Network Name/DNS Name FCI, spróbuje ustalić owner node grupy SQL i wykorzysta ten node do zdalnego collectora OS i Event Log.

### Availability Group

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLAGLISTENER,1433" `
    -ComputerName "SQLAG02"
```

### Query Store konkretnej bazy

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433" `
    -ComputerName "SQLPROD01" `
    -Database "MyDatabase"
```

Collector wykorzystuje `Invoke-Sqlcmd`, a jeżeli nie jest dostępny, próbuje `Invoke-DbaQuery` z modułu dbatools.

## Struktura

```text
SQLDBA-EmergencyToolkit/
├── TSQL/
├── PowerShell/
│   └── Collect-SqlIncident.ps1
├── Network/
│   ├── Test-SqlConnectivity.ps1
│   └── Wireshark-Filters.md
├── OS/
│   ├── Get-OSSnapshot.ps1
│   ├── Get-RemoteOSSnapshot.ps1
│   ├── Get-TopProcesses.ps1
│   ├── ProcDump-Runbook.md
│   └── WPR-Runbook.md
├── Cluster/
│   ├── Get-ClusterSnapshot.ps1
│   └── Resolve-FciActiveNode.ps1
├── XEvents/
├── Docs/
│   ├── Incident-Checklist.md
│   ├── Network-Incident-Runbook.md
│   ├── Windows-OS-Emergency-Runbook.md
│   ├── XEvents-Emergency-Runbook.md
│   ├── Remote-Collector-Runbook.md
│   └── Cluster-FCI-Emergency-Runbook.md
└── README.md
```

## FCI & Cluster Emergency Pack

Samodzielny snapshot klastra:

```powershell
.\Cluster\Get-ClusterSnapshot.ps1
```

Dla konkretnego klastra:

```powershell
.\Cluster\Get-ClusterSnapshot.ps1 `
    -ClusterName "CLUSTER01" `
    -OutputPath ".\ClusterSnapshot"
```

Wyniki obejmują:

- `Cluster.csv`
- `Nodes.csv`
- `Groups.csv`
- `Resources.csv`
- `NetworkNames.csv`
- `IPAddresses.csv`
- `Quorum.csv`
- `SqlClusterResources.csv`
- `SqlFciMap.csv`

Aktywny node FCI można sprawdzić osobno:

```powershell
.\Cluster\Resolve-FciActiveNode.ps1 `
    -SqlNetworkName "SQLFCI"
```

Szczegółowy runbook: `Docs/Cluster-FCI-Emergency-Runbook.md`.

## Remote Server Collector

`OS/Get-RemoteOSSnapshot.ps1` używa CIM/WMI oraz zdalnego odczytu Event Log i zbiera m.in. Windows, CPU, pamięć, dyski, procesy SQL Server, pagefile, usługi oraz podstawowe liczniki wydajności.

W FCI `ComputerName` powinien wskazywać aktualny fizyczny owner node grupy SQL. Opcja `-ResolveFciActiveNode` może wykonać to mapowanie automatycznie, jeśli z hosta collectora dostępny jest moduł `FailoverClusters` i informacje klastra.

## Network

Warstwa Network działa z hosta, na którym uruchamiasz toolkit, do `ServerInstance`. Dzięki temu pokazuje ścieżkę połączenia z punktu widzenia klienta DBA/aplikacji.

Pozytywny `Test-NetConnection` potwierdza osiągalność TCP, ale nie gwarantuje poprawnego TLS/pre-login handshake ani logowania SQL Server.

## Extended Events

Sesje XE w katalogu `XEvents` nie są uruchamiane automatycznie. Główny collector jedynie odczytuje stan sesji `SQLDBA_*`.

## ProcDump i WPR

ProcDump i WPR/WPA pozostają akcjami ręcznymi. Toolkit nie uruchamia automatycznie dumpów ani trace ETW.

## Fallback

Jeżeli resolver FCI, zdalny CIM, Event Log albo collector klastra nie działa, toolkit zapisuje `*-error.txt` w odpowiednim katalogu i kontynuuje pozostałą diagnostykę.

## Wymagania

Typowo potrzebne są:

- moduł PowerShell `FailoverClusters` dla diagnostyki klastra,
- odpowiednie prawa odczytu klastra,
- poprawny DNS,
- odpowiednie uprawnienia na hoście Windows,
- dostęp CIM/WinRM,
- reguły firewall dla zarządzania zdalnego,
- dostęp do zdalnego Event Log,
- `Invoke-Sqlcmd` lub `Invoke-DbaQuery` dla collectora SQL.

## Bezpieczeństwo

Collectory `TSQL`, `Network`, `OS` i `Cluster` są przeznaczone do odczytu. Nie restartują usług, nie zmieniają konfiguracji Windows, firewalla, WinRM ani klastra.

Skrypty v0.7 nie wywołują `Move-ClusterGroup`, `Stop-ClusterResource`, `Start-ClusterResource`, `Suspend-ClusterNode` ani operacji failover.

Skrypty `XEvents` wykonują świadome zmiany polegające na utworzeniu, uruchomieniu lub zatrzymaniu sesji Extended Events.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
