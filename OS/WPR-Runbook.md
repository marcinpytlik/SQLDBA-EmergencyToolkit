# WPR / WPA – emergency tracing

Windows Performance Recorder (WPR) i Windows Performance Analyzer (WPA) są przeznaczone do głębszej analizy problemów CPU, scheduling, storage i latency na poziomie systemu operacyjnego.

## Kiedy użyć

- wysoki CPU bez oczywistej przyczyny w SQL Server,
- skoki latency dysków,
- podejrzenie problemu storage / filesystem,
- problemy scheduler / DPC / ISR,
- problem występuje krótko i trzeba zebrać ślad ETW.

## Sprawdzenie dostępności

```powershell
Get-Command wpr.exe
Get-Command wpa.exe
```

## Start podstawowego trace

```text
wpr.exe -start GeneralProfile -filemode
```

## Stop i zapis

```text
wpr.exe -stop C:\SQLDiag\WPR\SQLIncident.etl
```

## Analiza

Otwórz plik `.etl` w Windows Performance Analyzer i zacznij od:

- CPU Usage (Sampled),
- CPU Usage (Precise),
- Disk Usage,
- File I/O,
- DPC/ISR,
- Processes and Threads.

## Ważne

Toolkit nie uruchamia WPR automatycznie. Trace ETW może generować zauważalny narzut i duże pliki, dlatego powinien być uruchamiany tylko podczas aktywnego incydentu i zatrzymany po zebraniu materiału.
