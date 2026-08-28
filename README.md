# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

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
│   └── AG.sql
├── PowerShell/
│   └── Collect-SqlIncident.ps1
├── XEvents/
├── Network/
├── Incident/
├── Docs/
│   └── Incident-Checklist.md
└── README.md
```

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
3. Uruchom `TSQL/ActiveRequests.sql`.
4. Sprawdź `TSQL/Blocking.sql`.
5. Pobierz bieżące waity przez `TSQL/WaitStats.sql`.
6. Sprawdź IO i pliki baz danych.
7. Jeżeli problem dotyczy połączeń, zbierz TCP/PCAP i sprawdź port, DNS, TLS oraz pre-login handshake.
8. Zachowaj logi SQL Server, Windows Event Log oraz wyniki diagnostyki w jednym katalogu incydentu.

## Bezpieczeństwo

Skrypty diagnostyczne w katalogu `TSQL` powinny być domyślnie read-only. Skrypty wykonujące zmiany będą wyraźnie oznaczone w dokumentacji.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
