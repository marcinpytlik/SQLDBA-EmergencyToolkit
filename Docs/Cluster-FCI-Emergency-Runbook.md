# Cluster & FCI Emergency Runbook

## Cel

Pakiet v0.7 służy do diagnostyki Windows Server Failover Cluster oraz SQL Server Failover Cluster Instance (FCI) bez wykonywania failoveru i bez modyfikowania konfiguracji klastra.

## Najważniejsze pytania podczas incydentu

1. Który node jest obecnie aktywny dla grupy SQL Server?
2. Czy wszystkie nody klastra są `Up`?
3. Czy grupa SQL Server i jej zasoby są `Online`?
4. Jaki VNN / Network Name i jakie adresy IP należą do grupy SQL?
5. Czy zasoby SQL Server i SQL Server Agent są na oczekiwanym nodzie?
6. Czy quorum jest dostępne?
7. Czy przed wystąpieniem problemu nastąpił failover lub przeniesienie grupy?

## Snapshot klastra

```powershell
.\Cluster\Get-ClusterSnapshot.ps1
```

Dla wskazanego klastra:

```powershell
.\Cluster\Get-ClusterSnapshot.ps1 `
    -ClusterName "CLUSTER01" `
    -OutputPath ".\ClusterSnapshot"
```

Wyniki:

- `Cluster.csv`
- `Nodes.csv`
- `Groups.csv`
- `Resources.csv`
- `NetworkNames.csv`
- `IPAddresses.csv`
- `Quorum.csv`
- `SqlClusterResources.csv`
- `SqlFciMap.csv`

## Ustalenie aktywnego noda FCI

```powershell
.\Cluster\Resolve-FciActiveNode.ps1 `
    -SqlNetworkName "SQLFCI01"
```

Wynik zawiera m.in. `ActiveNode` i `ClusterGroup`.

## Integracja z głównym collectorem

Jeżeli znasz fizyczny node:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI01,1530" `
    -ComputerName "SQLNODE02" `
    -CollectCluster
```

Jeżeli chcesz, aby toolkit spróbował sam ustalić aktywny node FCI:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI01,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

`ResolveFciActiveNode` wykorzystuje część hosta z `ServerInstance`, więc dla `SQLFCI01,1530` szuka `SQLFCI01` jako Network Name / DNS Name klastra.

## Wymagania

- moduł PowerShell `FailoverClusters`,
- uprawnienia do odczytu klastra,
- możliwość komunikacji z klastrem z hosta, na którym działa collector.

## Bezpieczeństwo

Skrypty v0.7 wykonują wyłącznie operacje odczytu. Nie wywołują `Move-ClusterGroup`, `Stop-ClusterResource`, `Start-ClusterResource`, `Suspend-ClusterNode` ani żadnych operacji failover.

## Interpretacja

### Node Down / Paused

Jeżeli node nie jest `Up`, sprawdź Event Log `System`, usługę `ClusSvc`, komunikację sieciową oraz ostatnie zdarzenia klastra.

### Group Offline / Failed

Sprawdź `Resources.csv`, aby wskazać zasób, który nie jest online. Nie przenoś grupy przed zebraniem logów, jeśli sytuacja na to pozwala.

### Network Name / IP

Jeżeli VNN jest online, ale klient nie łączy się z SQL Server, porównaj `NetworkNames.csv`, `IPAddresses.csv`, DNS i test TCP z pakietem `Network`.

### ActiveNode

Dla FCI dane OS powinny być zbierane z aktualnego owner node grupy SQL. Po failoverze ponownie ustal aktywny node przed interpretacją CPU, RAM i Event Logów.
