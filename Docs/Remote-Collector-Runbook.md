# Remote Server Collector Runbook

## Cel

Wersja 0.6 rozdziela dwa niezależne cele diagnostyczne:

- `ServerInstance` — endpoint SQL Server, np. VNN FCI, listener AG albo konkretny host/port.
- `ComputerName` — fizyczny host Windows, z którego pobieramy dane OS, Event Log i liczniki.

To rozdzielenie jest szczególnie ważne dla FCI i Availability Groups.

## Przykład FCI

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ComputerName "SQLNODE02"
```

SQL diagnostyka idzie do `SQLFCI,1530`, a dane Windows są pobierane z `SQLNODE02`.

## Wymagania

Zdalny collector OS używa CIM/WMI oraz zdalnego odczytu Event Log. W środowisku domenowym najczęściej wymaga:

- poprawnego DNS,
- uprawnień do zdalnego hosta,
- działającej komunikacji WinRM/CIM,
- odpowiednich reguł firewall,
- dostępu do zdalnych logów zdarzeń.

## Testy przed użyciem

```powershell
Test-WSMan SQLNODE02
Get-CimInstance Win32_OperatingSystem -ComputerName SQLNODE02
Get-WinEvent -ComputerName SQLNODE02 -LogName System -MaxEvents 5
```

Jeżeli CIM nie działa, collector SQL i sieciowy nadal może być użyteczny. Błąd zdalnego collectora OS jest zapisywany do pliku i nie powinien zatrzymywać całej paczki incydentu.

## FCI

Przy FCI `ComputerName` powinien wskazywać aktywny fizyczny node, a nie nazwę klastra ani VNN SQL Server.

Przykład:

```text
ServerInstance = SQLPROD-FCI,1530
ComputerName   = SQLNODE-B
```

## Availability Groups

Dla AG możesz kierować SQL diagnostykę do listenera, ale `ComputerName` powinien wskazywać replikę, którą chcesz analizować.

```text
ServerInstance = SQLAGLISTENER,1433
ComputerName   = SQLAG02
```

## Fallback

Jeżeli nie podasz `-ComputerName`, toolkit zachowuje tryb lokalny i zbiera OS hosta, na którym uruchomiono PowerShell.

Jeżeli podasz `-ComputerName`, a zdalny collector nie zadziała, paczka SQL/Network nadal jest tworzona. Szczegóły błędu znajdziesz w katalogu `OS`.

## Bezpieczeństwo

Remote collector jest przeznaczony do odczytu. Nie restartuje usług, nie zmienia konfiguracji Windows, nie modyfikuje firewalla ani WinRM.
