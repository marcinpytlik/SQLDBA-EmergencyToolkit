# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

## Wersja 0.6

Wersja 0.6 dodaje **Remote Server Collector**. `ServerInstance` i `ComputerName` są teraz niezależne:

- `ServerInstance` wskazuje endpoint SQL Server, np. FCI VNN, AG listener albo `host,port`.
- `ComputerName` wskazuje fizyczny host Windows, z którego pobierane są dane OS i Event Log.

Jeżeli `-ComputerName` nie zostanie podany, toolkit działa jak wcześniej i zbiera dane OS lokalnie.

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

### FCI

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ComputerName "SQLNODE02"
```

SQL diagnostyka idzie do `SQLFCI,1530`, a Windows/OS do fizycznego noda `SQLNODE02`.

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
├── XEvents/
├── Docs/
│   ├── Incident-Checklist.md
│   ├── Network-Incident-Runbook.md
│   ├── Windows-OS-Emergency-Runbook.md
│   ├── XEvents-Emergency-Runbook.md
│   └── Remote-Collector-Runbook.md
└── README.md
```

## Remote Server Collector

`OS/Get-RemoteOSSnapshot.ps1` używa CIM/WMI oraz zdalnego odczytu Event Log i zbiera m.in.:

- Windows/version/uptime,
- CPU i pamięć,
- dyski oraz wolne miejsce,
- procesy `sqlservr.exe`,
- pagefile,
- usługi SQL Server/Agent/Browser/Cluster,
- liczniki CPU, pamięci i dysków,
- TOP procesów według CPU i pamięci,
- logi System i Application.

Szczegóły znajdują się w `Docs/Remote-Collector-Runbook.md`.

## Ważne przy FCI i AG

W FCI `ComputerName` powinien być aktywnym fizycznym nodem, nie VNN ani nazwą klastra.

W AG `ServerInstance` może wskazywać listener, ale `ComputerName` powinien być konkretną repliką, której OS chcesz analizować.

Przykład:

```text
ServerInstance = SQLPROD-FCI,1530
ComputerName   = SQLNODE-B
```

## Network

Warstwa Network nadal działa z hosta, na którym uruchamiasz toolkit, do `ServerInstance`. Dzięki temu pokazuje ścieżkę połączenia z punktu widzenia klienta DBA/aplikacji.

Pozytywny `Test-NetConnection` potwierdza osiągalność TCP, ale nie gwarantuje poprawnego TLS/pre-login handshake ani logowania SQL Server.

## Extended Events

Sesje XE w katalogu `XEvents` nie są uruchamiane automatycznie. Główny collector jedynie odczytuje stan sesji `SQLDBA_*`.

## ProcDump i WPR

ProcDump i WPR/WPA pozostają akcjami ręcznymi. Toolkit nie uruchamia automatycznie dumpów ani trace ETW.

## Fallback

Jeżeli zdalny CIM albo Event Log nie działa, collector zapisuje `*-error.txt` w katalogu `OS` lub `EventLogs` i kontynuuje pozostałą diagnostykę SQL/Network.

## Wymagania zdalnego collectora

Typowo potrzebne są:

- poprawny DNS,
- odpowiednie uprawnienia na hoście Windows,
- dostęp CIM/WinRM,
- reguły firewall dla zarządzania zdalnego,
- dostęp do zdalnego Event Log.

Przydatne testy:

```powershell
Test-WSMan SQLNODE02
Get-CimInstance Win32_OperatingSystem -ComputerName SQLNODE02
Get-WinEvent -ComputerName SQLNODE02 -LogName System -MaxEvents 5
```

## Bezpieczeństwo

Collectory `TSQL`, `Network` i `OS` są przeznaczone do odczytu. Nie restartują usług i nie zmieniają konfiguracji Windows, firewalla ani WinRM.

Skrypty `XEvents` wykonują świadome zmiany polegające na utworzeniu, uruchomieniu lub zatrzymaniu sesji Extended Events.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
