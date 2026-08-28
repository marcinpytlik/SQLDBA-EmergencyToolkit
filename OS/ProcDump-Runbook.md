# ProcDump – SQL Server emergency notes

ProcDump jest narzędziem Sysinternals. Ten dokument opisuje bezpieczny sposób przygotowania do diagnostyki; toolkit nie uruchamia ProcDump automatycznie.

## Kiedy rozważyć ProcDump

- proces `sqlservr.exe` przestaje odpowiadać,
- podejrzenie hang/crash,
- potrzebny zrzut procesu do dalszej analizy,
- Microsoft Support prosi o dump.

## Ważne

Pełny dump `sqlservr.exe` może być bardzo duży i mocno obciążyć IO. Na serwerze z dużą pamięcią RAM najpierw sprawdź ilość wolnego miejsca na wolumenie docelowym.

## Identyfikacja PID

```powershell
Get-Process sqlservr | Select-Object Id, ProcessName, StartTime, WorkingSet64
```

## Przykład pełnego dumpu

Uruchamiaj świadomie i tylko po sprawdzeniu miejsca:

```text
procdump64.exe -accepteula -ma <PID> C:\SQLDiag\Dumps
```

## Dump przy wyjątku / crash

```text
procdump64.exe -accepteula -ma -e 1 <PID> C:\SQLDiag\Dumps
```

## Zasada operacyjna

Collector SQLDBA Emergency Toolkit nie wykonuje dumpów automatycznie. Dump jest akcją aktywną i powinien być uruchamiany świadomie, najlepiej zgodnie z procedurą incident response lub zaleceniem wsparcia Microsoft.
