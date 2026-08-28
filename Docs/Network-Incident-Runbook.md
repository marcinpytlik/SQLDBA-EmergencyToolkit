# SQL Server Network Incident Runbook

## Cel

Szybka diagnostyka problemów połączeniowych SQL Server: timeout, pre-login handshake, TLS, DNS, port, firewall, SPN/Kerberos, listener FCI/AG.

## 1. Zapisz kontekst

Zanotuj:

- dokładny czas problemu,
- klienta / host źródłowy,
- nazwę instancji,
- port,
- nazwę listenera/VNN,
- czy SSMS działa,
- czy problem dotyczy PowerShell/.NET/aplikacji,
- czy problem jest stały czy losowy.

## 2. Uruchom podstawowy test

```powershell
.\Network\Test-SqlConnectivity.ps1 -ServerInstance "SQLPROD01,1433"
```

Sprawdź `Network-Summary.csv` oraz pliki DNS, ping, Test-NetConnection, klist i SPN.

## 3. DNS

Porównaj adres zwrócony przez DNS z oczekiwanym adresem listenera/VNN.

```powershell
Resolve-DnsName SQLPROD01
```

Przy klastrze zwróć uwagę na wiele rekordów IP oraz cache klienta.

## 4. TCP

```powershell
Test-NetConnection SQLPROD01 -Port 1433 -InformationLevel Detailed
```

Jeśli TCP nie przechodzi, sprawdź firewall, routing, listener i port SQL Server.

Jeśli TCP przechodzi, ale aplikacja nadal timeoutuje, problem może występować później: TLS, pre-login, uwierzytelnienie lub zachowanie klienta.

## 5. SPN i Kerberos

```powershell
setspn -Q MSSQLSvc/SQLPROD01*
klist
```

Sprawdź duplikaty SPN, konto usługi SQL Server i to, czy klient otrzymał ticket Kerberos.

## 6. SQL Browser

Dla nazwanych instancji bez jawnego portu klient może korzystać z SQL Browser (UDP 1434). W diagnostyce awaryjnej preferuj test z jawnym portem:

```text
SQLPROD01,1530
```

Pozwala to oddzielić problem SQL Browser od właściwego połączenia TCP do SQL Server.

## 7. FCI / Availability Group

Dla listenera lub VNN sprawdź:

- DNS,
- aktualny adres IP,
- aktywny węzeł,
- port listenera,
- stan zasobu sieciowego,
- routing z klienta do każdego potencjalnego adresu IP.

## 8. Wireshark

Zacznij od capture filter:

```text
tcp port 1433
```

Następnie przeanalizuj:

1. SYN -> SYN/ACK -> ACK,
2. retransmisje,
3. TCP RST,
4. początek TLS,
5. TLS alert,
6. różnice pomiędzy SSMS a aplikacją/PowerShell.

Gotowe filtry znajdują się w `Network/Wireshark-Filters.md`.

## 9. Zasada diagnostyczna

Nie zakładaj, że `Test-NetConnection = True` oznacza poprawne połączenie SQL Server. To potwierdza przede wszystkim osiągalność TCP. Pre-login, TLS i logowanie następują później.

## 10. Zbieranie pełnej paczki

```powershell
.\PowerShell\Collect-SqlIncident.ps1 -ServerInstance "SQLPROD01,1433"
```

Wyniki sieciowe trafiają do podkatalogu `Network` razem z diagnostyką SQL i logami systemowymi.
