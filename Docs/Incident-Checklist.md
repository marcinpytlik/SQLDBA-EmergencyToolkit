# SQL Server Incident Checklist

## 1. Zanim cokolwiek zmienisz

- Zapisz dokładny czas rozpoczęcia problemu.
- Zapisz nazwę instancji, serwera i bazy.
- Nie restartuj SQL Server, jeśli można jeszcze zebrać diagnostykę.
- Nie czyść plan cache ani wait stats przed zebraniem danych.
- Nie zabijaj sesji bez zapisania informacji o blockerze i wykonywanym zapytaniu.

## 2. SQL Server

Uruchom kolejno:

1. `TSQL/ActiveRequests.sql`
2. `TSQL/Blocking.sql`
3. `TSQL/WaitStats.sql`
4. `TSQL/IOStats.sql`

Dodatkowo zbierz:

- SQL Server Error Log,
- historię SQL Agent Jobs,
- informacje z Query Store, jeśli jest włączony,
- deadlock XML/XEL,
- konfigurację instancji,
- informacje o ostatnich zmianach deployment/configuration.

## 3. Windows

Sprawdź:

- CPU,
- pamięć,
- paging,
- opóźnienia dysków,
- Windows Event Log,
- Process Explorer,
- Process Monitor,
- RAMMap,
- TCPView.

## 4. Sieć

Dla timeoutów, login timeout i pre-login handshake:

- sprawdź DNS,
- sprawdź port TCP,
- wykonaj `Test-NetConnection`,
- wykonaj test PsPing,
- sprawdź TCPView,
- zbierz PCAP w Wireshark,
- sprawdź TLS/certyfikat,
- porównaj działające i niedziałające klienty.

## 5. Dane incydentu

Zalecana struktura katalogu:

```text
Incident-YYYYMMDD-HHMM/
├── SQL/
├── XEvents/
├── PerfMon/
├── Network/
├── EventLogs/
└── Notes/
```

## 6. Po ustabilizowaniu sytuacji

- określ root cause,
- oddziel przyczynę od skutków,
- zapisz timeline,
- zapisz działania naprawcze,
- przygotuj działania zapobiegawcze,
- dodaj nowe zapytanie lub procedurę diagnostyczną do toolkitu, jeśli incydent ujawnił lukę.
