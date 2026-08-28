# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Jak uruchamiać toolkit

Pełny przewodnik z gotowymi komendami dla standardowej instancji, FCI, AG, sieci, OS, storage, Extended Events i raportów znajduje się tutaj:

**[Docs/How-To-Run.md](Docs/How-To-Run.md)**

Jeżeli używasz toolkitu pierwszy raz, zacznij właśnie od tego dokumentu.

## Wersja 1.0

Wersja 1.0 dodaje **Health Score + HTML Report**.

Po zakończeniu collectora toolkit automatycznie generuje:

- `Incident-Summary.md`
- `Incident-Findings.csv`
- `Incident-HealthScore.csv`
- `Incident-Report.html`

Raport HTML zawiera Health Score 0-100, status ogólny, executive summary oraz sekcje Critical / Warning / OK.

## Szybki start

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLPROD01,1433"
```

### FCI

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

## Health Score

Model v1.0 jest celowo prosty i transparentny:

- start: 100 punktów,
- Critical: -20 punktów,
- Warning: -7 punktów,
- minimum: 0.

Status:

- 90-100: Healthy
- 70-89: Degraded
- 50-69: Warning
- 0-49: Critical

To heurystyka operacyjna, nie SLA ani automatyczne RCA.

## Raporty

Generator tekstowy:

```powershell
.\Reports\New-IncidentSummary.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"
```

Generator HTML:

```powershell
.\Reports\New-IncidentHtmlReport.ps1 `
    -IncidentPath ".\Incidents\Incident-20260828-120000"
```

Generator HTML korzysta z `Incident-Findings.csv`, dlatego przy ręcznym uruchamianiu najpierw wykonaj `New-IncidentSummary.ps1`.

## Obszary diagnostyki

Toolkit obejmuje:

- aktywne requesty i blocking,
- wait stats,
- pamięć i tempdb,
- log transakcyjny,
- backupy i SQL Agent,
- AG i replikację,
- Extended Events,
- sieć, DNS, TCP, SPN/Kerberos i TLS/pre-login,
- Windows/OS,
- zdalny collector hosta Windows,
- FCI i Windows Server Failover Cluster,
- storage, latency, autogrowth i VLF,
- automatyczny incident summary i HTML report.

## Wynik collectora

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
├── Incident-HealthScore.csv
└── Incident-Report.html
```

## Zasady bezpieczeństwa

Collectory `TSQL`, `Network`, `OS`, `Storage`, `Cluster` oraz generatory raportów są przeznaczone do diagnostyki i odczytu.

Nie wykonują:

- restartów usług,
- failoveru,
- shrink,
- zmian autogrowth,
- zmian konfiguracji storage,
- zmian konfiguracji Windows ani firewalla.

Skrypty w katalogu `XEvents` są wyjątkiem: świadomie tworzą, uruchamiają lub zatrzymują sesje Extended Events i nie są uruchamiane automatycznie przez główny collector.

ProcDump i WPR/WPA pozostają akcjami ręcznymi.

## Wymagania

Typowo potrzebne są:

- `Invoke-Sqlcmd` lub `Invoke-DbaQuery`,
- odpowiednie uprawnienia diagnostyczne SQL Server,
- moduł `FailoverClusters` dla FCI,
- uprawnienia do zdalnego CIM/Event Log dla remote collectora,
- poprawny DNS i firewall.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
