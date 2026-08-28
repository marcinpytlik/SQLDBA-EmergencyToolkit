# Extended Events Emergency Pack v0.4

Pakiet gotowych sesji Extended Events do szybkiej diagnostyki incydentów SQL Server.

## Zawartość

- `01-Blocking.sql` – blocked process reports i deadlock chain.
- `02-Deadlocks.sql` – XML deadlock graph.
- `03-LongRunningQueries.sql` – RPC i batch trwające co najmniej 5 sekund.
- `04-IOErrors-823-824-825.sql` – krytyczne błędy I/O 823, 824 i 825.
- `05-LoginFailures.sql` – błędy logowania 18456.
- `06-LogGrowth.sql` – zmiany rozmiaru plików baz danych, w tym logu.
- `90-Read-XEventFiles.sql` – pomocniczy odczyt plików `.xel`.
- `99-Stop-EmergencySessions.sql` – zatrzymanie wszystkich sesji pakietu.

## Ważne przed uruchomieniem

Skrypty tworzą obiekty `EVENT SESSION` na poziomie serwera, więc nie są read-only. Każdy skrypt najpierw usuwa istniejącą sesję o tej samej nazwie i tworzy ją ponownie.

Sprawdź ścieżkę `event_file`. Gdy podana jest tylko nazwa pliku, SQL Server zapisze plik w lokalizacji wynikającej z konfiguracji Extended Events. W środowisku produkcyjnym warto użyć jawnej ścieżki na dysku z odpowiednią ilością miejsca.

## Blocking

`blocked_process_report` generuje zdarzenia tylko wtedy, gdy `blocked process threshold (s)` jest większe od 0.

Sprawdzenie konfiguracji:

```sql
EXEC sys.sp_configure N'blocked process threshold (s)';
```

Pakiet nie zmienia tej wartości automatycznie.

## Long-running queries

Domyślny próg wynosi 5 sekund:

```text
duration >= 5000000 microseconds
```

Przy bardzo obciążonych systemach rozważ 10–30 sekund albo filtr po `database_id`, aplikacji lub loginie.

## Błędy 823/824/825

Ta sesja używa `NO_EVENT_LOSS`, ponieważ utrata takiego zdarzenia jest mniej akceptowalna niż przy typowej telemetrii. Sesję warto uruchamiać świadomie i obserwować koszt w bardzo obciążonych środowiskach.

## Odczyt plików

Możesz otworzyć `.xel` w SSMS albo użyć `90-Read-XEventFiles.sql` po ustawieniu właściwej ścieżki.

## Zatrzymanie sesji

```sql
:r .\XEvents\99-Stop-EmergencySessions.sql
```

Lub wykonaj zawartość skryptu w SSMS.

## Bezpieczny workflow podczas incydentu

1. Najpierw uruchom `Collect-SqlIncident.ps1`, aby zebrać stan bieżący.
2. Wybierz tylko potrzebną sesję XE zamiast uruchamiać cały pakiet bez powodu.
3. Zapisz godzinę startu sesji.
4. Odtwórz lub odczekaj na wystąpienie problemu.
5. Zatrzymaj sesję.
6. Zachowaj `.xel` razem z paczką incydentu.
7. Przeanalizuj zdarzenia w kontekście DMV, logów SQL Server, Windows i danych sieciowych.

## Uprawnienia

Tworzenie i zarządzanie serwerowymi sesjami XE wymaga odpowiednich uprawnień serwerowych. Do samego odczytu DMV i metadanych mogą być wymagane `VIEW SERVER STATE` lub `VIEW SERVER PERFORMANCE STATE`, zależnie od wersji SQL Server.
