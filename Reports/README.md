# Incident Report Generator

Wersja 0.9 dodaje automatyczne podsumowanie paczki incydentu.

Generator analizuje pliki CSV utworzone przez `Collect-SqlIncident.ps1` i zapisuje:

- `Incident-Summary.md`
- `Incident-Findings.csv`

Kategorie wyników:

- Critical
- Warning
- OK

Analiza jest heurystyczna i nie zastępuje pełnej analizy RCA.
