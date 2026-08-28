# Windows & OS Emergency Runbook

Pakiet `OS` służy do szybkiego zebrania stanu systemu Windows podczas incydentu SQL Server.

## Kluczowa zasada

Skrypty `OS/*.ps1` zbierają dane z komputera, na którym są uruchamiane. Jeżeli główny collector uruchamiasz z laptopa DBA, katalog `OS` opisuje laptop DBA, a nie host SQL Server.

Aby zebrać stan hosta SQL Server:

- uruchom toolkit bezpośrednio na hoście SQL Server, albo
- uruchom skrypty przez zatwierdzony PowerShell Remoting / jump host.

W środowisku FCI pamiętaj, że interesuje Cię aktywny fizyczny node, nie tylko VNN SQL Server.

## Co zbiera Get-OSSnapshot.ps1

- wersję i uptime Windows,
- całkowitą i wolną pamięć RAM,
- CPU i liczbę rdzeni/logical processors,
- lokalne wolumeny i wolne miejsce,
- procesy `sqlservr.exe`,
- aktywne połączenia TCP,
- pagefile,
- usługi SQL Server / SQL Agent / SQL Browser / Cluster Service,
- krótki snapshot PerfMon.

## Liczniki PerfMon

Collector próbuje zebrać 5 próbek co 1 sekundę dla:

- `Processor(_Total)\\% Processor Time`,
- `System\\Processor Queue Length`,
- `Memory\\Available MBytes`,
- `Memory\\Pages/sec`,
- `PhysicalDisk(_Total)\\Avg. Disk sec/Read`,
- `PhysicalDisk(_Total)\\Avg. Disk sec/Write`,
- `PhysicalDisk(_Total)\\Avg. Disk Queue Length`.

To jest szybki snapshot, nie pełny monitoring trendu. Przy problemach sporadycznych potrzebny jest dłuższy Data Collector Set, WPR lub system monitoringu.

## Szybka interpretacja

### CPU

Sprawdź `CPU.csv`, `PerfCounters.csv` oraz `TopProcessesByCPU.csv`.

Wysoki CPU hosta nie oznacza automatycznie, że źródłem jest SQL Server. Porównaj proces `sqlservr.exe` z innymi procesami i jednocześnie sprawdź `TSQL/ActiveRequests.sql` oraz wait stats.

### Pamięć

Sprawdź:

- wolną pamięć w `OS.csv`,
- `Memory\\Available MBytes`,
- `Memory\\Pages/sec`,
- `PageFile.csv`,
- `SqlServerProcesses.csv`,
- `TSQL/Memory.sql`.

Nie diagnozuj presji pamięci wyłącznie na podstawie jednego licznika.

### Dyski

`Disks.csv` pokazuje pojemność i wolne miejsce. `PerfCounters.csv` daje szybki obraz latency.

Dla SQL Server zestaw dane Windows z `TSQL/IOStats.sql`; wysoka latencja na poziomie SQL i Windows jednocześnie jest znacznie mocniejszym sygnałem problemu storage.

### Proces SQL Server

`SqlServerProcesses.csv` pokazuje m.in. PID, czas uruchomienia, CPU, working set i private memory. PID jest potrzebny również przy świadomym użyciu ProcDump.

## ProcDump

Patrz `OS/ProcDump-Runbook.md`.

Toolkit nigdy nie wykonuje dumpu automatycznie. Pełny dump dużej instancji może mieć dziesiątki lub setki GB i powodować istotny ruch IO.

## WPR / WPA

Patrz `OS/WPR-Runbook.md`.

WPR jest przydatny, gdy problem leży poniżej SQL Server: scheduling, storage, filesystem, DPC/ISR lub krótkotrwałe skoki CPU/IO.

## Kolejność podczas incydentu

1. Zapisz godzinę rozpoczęcia problemu.
2. Uruchom `Collect-SqlIncident.ps1`.
3. Potwierdź, czy katalog `OS` pochodzi z właściwego hosta.
4. Porównaj SQL wait stats z licznikami Windows.
5. Sprawdź wolne miejsce i latency dysków.
6. Sprawdź CPU i top procesy.
7. Sprawdź pamięć i pagefile.
8. Dopiero jeśli potrzebujesz głębszego śladu, rozważ WPR lub ProcDump.
9. Nie restartuj SQL Server przed zabezpieczeniem danych diagnostycznych, jeśli sytuacja operacyjna na to pozwala.
