# SQLDBA Emergency Toolkit

Praktyczny zestaw narzędzi, skryptów i procedur dla administratora Microsoft SQL Server podczas diagnostyki awarii, problemów wydajnościowych, blokad, problemów sieciowych i operacyjnych.

## Założenie

Repozytorium ma działać jak plecak awaryjny DBA: minimum teorii, maksimum skryptów gotowych do użycia.

## Wersja 0.8

Wersja 0.8 dodaje **Storage & IO Emergency Pack**.

Toolkit potrafi teraz korelować:

- latency per plik SQL Server,
- ustawienia autogrowth,
- liczbę VLF,
- IO tempdb,
- wolne miejsce na wolumenach,
- liczniki dysków logicznych i fizycznych Windows,
- aktywny node FCI z właściwym hostem storage.

Wszystkie collectory storage są diagnostyczne/read-only.

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

### FCI — automatyczne wykrycie aktywnego noda

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

W tym trybie diagnostyka SQL idzie do VNN, a dane OS/storage są zbierane z aktywnego fizycznego noda.

### Availability Group

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLAGLISTENER,1433" `
    -ComputerName "SQLAG02"
```

## Nowe pliki v0.8

```text
TSQL/
├── StorageIO.sql
├── FileGrowth.sql
├── VLF.sql
└── TempdbIO.sql

OS/
└── Get-StorageSnapshot.ps1

Docs/
└── Storage-IO-Emergency-Runbook.md
```

## Storage & IO Emergency Pack

### SQL Server

`TSQL/StorageIO.sql` korzysta z `sys.dm_io_virtual_file_stats` i pokazuje m.in.:

- bazę,
- typ pliku,
- ścieżkę fizyczną,
- liczbę odczytów i zapisów,
- bytes read/write,
- `AvgReadLatencyMs`,
- `AvgWriteLatencyMs`.

`TSQL/FileGrowth.sql` pokazuje rozmiary, MAXSIZE i konfigurację autogrowth.

`TSQL/VLF.sql` zbiera liczbę VLF dla baz użytkownika.

`TSQL/TempdbIO.sql` pokazuje latency osobno dla każdego pliku tempdb.

### Windows / storage

`OS/Get-StorageSnapshot.ps1` zbiera:

- `Volumes.csv`,
- `VolumeDetails.csv`,
- `PhysicalDisks.csv`,
- `LogicalDiskPerf.csv`,
- `PhysicalDiskPerf.csv`.

Dzięki temu można porównać latency widziane przez SQL Server z aktualnym stanem warstwy Windows.

## Wynik collectora

W paczce incydentu pojawia się teraz dodatkowy katalog:

```text
Storage/
├── Volumes.csv
├── VolumeDetails.csv
├── PhysicalDisks.csv
├── LogicalDiskPerf.csv
├── PhysicalDiskPerf.csv
└── Storage-Console.txt
```

Po stronie SQL dochodzą:

```text
SQL/
├── StorageIO.csv
├── FileGrowth.csv
├── VLF.csv
└── TempdbIO.csv
```

## Jak analizować IO

Najpierw sprawdź `SQL/StorageIO.csv` i ustal, które pliki mają najwyższe read/write latency. Następnie z `physical_name` ustal wolumen i porównaj go z `Storage/LogicalDiskPerf.csv` oraz `Storage/PhysicalDiskPerf.csv`.

Dla problemów z odczytem koreluj wyniki z waitami `PAGEIOLATCH_*`. Dla logu sprawdzaj szczególnie `WRITELOG`, growth logu i konfigurację VLF.

Wartości z `sys.dm_io_virtual_file_stats` są kumulowane, więc mogą obejmować długi okres od startu instancji. Snapshot Windows pokazuje bieżący stan i dlatego oba źródła należy interpretować razem.

Szczegółowy runbook: `Docs/Storage-IO-Emergency-Runbook.md`.

## FCI & Cluster Emergency Pack

Toolkit nadal potrafi:

- zebrać snapshot klastra,
- pokazać stany nodów, grup i zasobów,
- zebrać Network Name i IP,
- pokazać quorum,
- wykryć zasoby SQL Server/Agent,
- rozwiązać aktywny node FCI.

Żaden skrypt nie wykonuje failoveru ani zmian w konfiguracji klastra.

## Network

Warstwa Network działa z hosta collectora do `ServerInstance`. Pozytywny `Test-NetConnection` potwierdza osiągalność TCP, ale nie gwarantuje poprawnego TLS/pre-login handshake ani logowania SQL Server.

## Extended Events

Sesje XE w katalogu `XEvents` nie są uruchamiane automatycznie. Główny collector jedynie odczytuje ich stan.

## ProcDump i WPR

ProcDump i WPR/WPA pozostają akcjami ręcznymi. Toolkit nie uruchamia automatycznie dumpów ani trace ETW.

## Fallback

Jeżeli resolver FCI, zdalny CIM, Event Log, collector klastra lub collector storage nie działa, toolkit zapisuje `*-error.txt` i kontynuuje pozostałą diagnostykę.

## Wymagania

Typowo potrzebne są:

- `Invoke-Sqlcmd` lub `Invoke-DbaQuery`,
- `VIEW SERVER STATE` lub odpowiednie nowsze uprawnienia SQL Server,
- moduł `FailoverClusters` dla diagnostyki FCI,
- uprawnienia do zdalnego CIM/Event Log,
- poprawny DNS i firewall.

## Bezpieczeństwo

Collectory `TSQL`, `Network`, `OS`, `Storage` i `Cluster` są przeznaczone do odczytu.

Nie wykonują:

- shrink,
- resize/growth plików,
- zmian autogrowth,
- restartów usług,
- failoveru,
- zmian konfiguracji storage.

Skrypty `XEvents` są wyjątkiem — świadomie tworzą, uruchamiają lub zatrzymują sesje Extended Events.

## Autor

Marcin Pytlik

Repozytorium rozwijane jako praktyczny toolkit administratora Microsoft SQL Server.
