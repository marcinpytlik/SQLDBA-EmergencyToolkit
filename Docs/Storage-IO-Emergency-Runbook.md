# Storage & IO Emergency Runbook

## Cel

Pakiet v0.8 pomaga szybko odpowiedzieć na pytanie: czy problem wydajnościowy pochodzi z SQL Server, konkretnego pliku bazy, tempdb, logu transakcyjnego czy z warstwy Windows/storage.

## Pliki

- `TSQL/StorageIO.sql` — latency per plik z `sys.dm_io_virtual_file_stats`.
- `TSQL/FileGrowth.sql` — rozmiar i ustawienia autogrowth wszystkich plików.
- `TSQL/VLF.sql` — liczba VLF dla baz użytkownika.
- `TSQL/TempdbIO.sql` — latency per plik tempdb.
- `OS/Get-StorageSnapshot.ps1` — wolumeny, dyski fizyczne i snapshot liczników Windows.

## Kolejność analizy

1. Otwórz `SQL/StorageIO.csv`.
2. Posortuj po `AvgReadLatencyMs` i `AvgWriteLatencyMs`.
3. Sprawdź `physical_name`, aby ustalić wolumen pliku.
4. Porównaj z `Storage/LogicalDiskPerf.csv` i `Storage/PhysicalDiskPerf.csv`.
5. Sprawdź `Storage/Volumes.csv` pod kątem wolnego miejsca.
6. Sprawdź `SQL/FileGrowth.csv`, czy pliki nie rosną małymi przyrostami lub procentowo.
7. Dla logu sprawdź również `SQL/Log.csv` i `SQL/VLF.csv`.
8. Dla tempdb sprawdź `SQL/TempdbIO.csv` i `SQL/TempDB.csv`.

## Interpretacja latency

Nie traktuj jednego progu jako absolutnego SLA. Liczy się workload, storage i trend. Jako szybka heurystyka diagnostyczna:

- poniżej kilku ms — zwykle bardzo dobrze,
- około 5–10 ms — często akceptowalne,
- 10–20 ms — warto korelować z workloadem i waitami,
- stale powyżej 20 ms — sygnał do dokładniejszej analizy,
- wysokie wartości wraz z `PAGEIOLATCH_*`, `WRITELOG` lub kolejkami dyskowymi wzmacniają podejrzenie storage.

Wartości z `sys.dm_io_virtual_file_stats` są średnimi od startu instancji / resetu liczników, więc nie są tym samym co chwilowy snapshot Windows.

## Data vs log

### DATA

Wysokie read latency koreluj z:

- `PAGEIOLATCH_SH`,
- dużą liczbą physical reads,
- brakującymi indeksami / skanami,
- presją pamięci,
- równoległymi operacjami backup/restore/CHECKDB.

### LOG

Wysokie write latency koreluj z:

- `WRITELOG`,
- częstymi commitami,
- autogrowth logu,
- zbyt małymi przyrostami,
- synchronicznym AG,
- wolnym storage logowym.

## Autogrowth

Preferuj stały przyrost MB zamiast procentu. Rozmiar growth powinien być dopasowany do wielkości bazy i tempa wzrostu. Bardzo małe przyrosty mogą generować serię growth eventów i fragmentację VLF.

## VLF

Duża liczba VLF nie oznacza automatycznie awarii, ale może pogarszać recovery, backup/restore i operacje na logu. Zawsze interpretuj ją razem z rozmiarem logu, historią growth i workloadem.

## tempdb

Porównaj wszystkie pliki tempdb. Duże różnice latency lub rozmiaru mogą wskazywać na nierówną konfigurację albo problemy storage. Nie zakładaj, że każdy przypadek wymaga zwiększenia liczby plików.

## FCI

W FCI snapshot Windows/storage powinien pochodzić z aktywnego noda. Najwygodniej:

```powershell
.\PowerShell\Collect-SqlIncident.ps1 `
    -ServerInstance "SQLFCI,1530" `
    -ResolveFciActiveNode `
    -CollectCluster
```

Wtedy `Storage` jest zbierany z noda ustalonego przez resolver FCI.

## Bezpieczeństwo

Wszystkie skrypty storage w v0.8 są diagnostyczne/read-only. Nie wykonują shrink, growth, resize, defrag, failover ani zmian konfiguracji storage.
