# Procmon: SQL Server Configuration Runbook

Ten runbook pokazuje, jak krok po kroku i w sposób powtarzalny prześledzić mechanizm konfiguracji instancji SQL Server: od `sys.configurations`, przez wewnętrzny operator `CFGPROP`, po fizyczny zapis strony konfiguracyjnej w `master.mdf` wykonywany przez `RECONFIGURE`.

Runbook opiera się na kontrolowanym teście wykonanym dla SQL Server 2022 Express 16.0.4265.3. Konkretne offsety, stacki i zachowanie mogą różnić się między wersjami SQL Server, buildami i edycjami. Procedura eksperymentalna pozostaje jednak powtarzalna.

> Wnioski w tym dokumencie dotyczą obserwowanego ustawienia `user instance timeout` i konkretnego testu. Nie należy automatycznie zakładać identycznego mechanizmu dla wszystkich opcji `sp_configure`.

---

## 1. Cel scenariusza

Chcemy odpowiedzieć na pytania:

1. skąd `sys.configurations` pobiera dane,
2. czym jest `sys.configurations$`,
3. jak w planie wykonania pojawia się `CFGPROP`,
4. co robi samo `sp_configure`,
5. co robi `RECONFIGURE`,
6. czy zmiana zapisuje się do Registry,
7. czy `RECONFIGURE` powoduje fizyczny zapis do `master.mdf`,
8. jaka strona jest zapisywana,
9. jaki stack prowadzi od `RECONFIGURE` do `WriteFile`,
10. czy ustawienie pozostaje po restarcie SQL Server.

Schemat końcowy:

```text
sys.configurations
    ↓
sys.configurations$
    ↓
CFGPROP
    ↓
sp_configure
    ↓
configured value
    ↓
RECONFIGURE
    ↓
SysConfigPagePtr
    ↓
FCB::SyncWrite
    ↓
DiskWriteAsync
    ↓
WriteFile
    ↓
master.mdf : page 10
    ↓
restart
    ↓
wartość pozostaje zachowana
```

---

## 2. Wymagania wstępne

### 2.1. SQL Server

Do odtworzenia testu potrzebujesz:

- instancji SQL Server,
- uprawnień pozwalających wykonać `sp_configure` i `RECONFIGURE`,
- najlepiej środowiska laboratoryjnego.

Test referencyjny:

```text
Edition        : Express Edition (64-bit)
ProductVersion : 16.0.4265.3
ProductLevel   : RTM
```

### 2.2. Procmon

Uruchom Sysinternals Process Monitor jako Administrator na hoście SQL Server.

Przed każdym krótkim eksperymentem:

```text
Ctrl+E  - stop capture
Ctrl+X  - clear
Ctrl+E  - start capture
```

Zalecane kolumny:

- `Time of Day`
- `Process Name`
- `PID`
- `Operation`
- `Path`
- `Result`
- `Detail`
- `Duration`
- `TID`

### 2.3. Symbole

Symbole są bardzo zalecane, ponieważ kluczowa część scenariusza wykorzystuje:

```text
Event Properties -> Stack
```

Pełny workflow symboli offline znajduje się w:

```text
Docs/Offline-Symbols-Workflow.md
```

Skrypty pomocnicze:

```text
PowerShell/Copy-SqlSymbolTargetsToWorkstation.ps1
PowerShell/Prepare-OfflineSymbols.ps1
```

Przykładowa konfiguracja Procmon:

```text
Options -> Configure Symbols...

DbgHelp.dll:
C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbghelp.dll

Symbol path offline:
D:\DBATools\Symbols
```

W środowisku z Internetem można użyć:

```text
srv*C:\Symbols*https://msdl.microsoft.com/download/symbols
```

PDB powinny odpowiadać dokładnej wersji binarium. Publiczne symbole SQL Server mogą nie zawierać pełnych prywatnych nazw funkcji, dlatego pojedyncze nazwy symboli należy interpretować ostrożnie.

---

# 3. ETAP 1 - baseline konfiguracji

Najpierw nie uruchamiaj Procmon i niczego nie zmieniaj.

```sql
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel;
GO

SELECT
    configuration_id,
    name,
    value AS configured_value,
    value_in_use,
    minimum,
    maximum,
    is_dynamic,
    is_advanced
FROM sys.configurations
WHERE name IN
(
    N'user instance timeout',
    N'user instances enabled'
)
ORDER BY configuration_id;
GO
```

W teście referencyjnym:

```text
configuration_id = 1573
name             = user instance timeout
value            = 60
value_in_use     = 60
is_dynamic       = 1
```

Następnie sprawdź definicję widoku:

```sql
SELECT OBJECT_DEFINITION(OBJECT_ID(N'sys.configurations')) AS ViewDefinition;
GO
```

Wynik pokazuje, że `sys.configurations` odwołuje się do:

```text
sys.configurations$
```

czyli logicznie:

```text
sys.configurations
    ↓
sys.configurations$
```

---

# 4. ETAP 2 - czym jest sys.configurations$

Próba bezpośredniego zapytania:

```sql
SELECT *
FROM sys.configurations$;
GO
```

może zakończyć się:

```text
Msg 208
Invalid object name 'sys.configurations$'.
```

Sprawdź metadane:

```sql
SELECT
    o.object_id,
    o.name,
    o.type,
    o.type_desc
FROM sys.system_objects AS o
WHERE o.name LIKE N'%configuration%'
ORDER BY o.name;
GO

SELECT
    OBJECT_ID(N'sys.configurations')  AS ConfigurationsObjectId,
    OBJECT_ID(N'sys.configurations$') AS InternalConfigurationsObjectId;
GO

SELECT
    name,
    type_desc
FROM sys.all_objects
WHERE name IN
(
    N'configurations',
    N'configurations$'
);
GO
```

W teście referencyjnym:

```text
OBJECT_ID('sys.configurations')  = -224
OBJECT_ID('sys.configurations$') = NULL
```

`configurations$` nie pojawiało się również w `sys.all_objects`.

Wniosek operacyjny:

> `sys.configurations$` nie zachowuje się jak zwykła tabela lub widok dostępny bezpośrednio przez namespace `sys`. Jest elementem wewnętrznej warstwy katalogu wykorzystywanej przez silnik przy realizacji `sys.configurations`.

---

# 5. ETAP 3 - CFGPROP w planie wykonania

Włącz SHOWPLAN:

```sql
SET SHOWPLAN_XML ON;
GO

SELECT
    configuration_id,
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO

SET SHOWPLAN_XML OFF;
GO
```

W planie XML wyszukaj:

```text
CFGPROP
```

W capture referencyjnym plan zawierał:

```text
PhysicalOp="Table-valued function"
LogicalOp="Table-valued function"
Object Table="[CFGPROP]"
```

Kolumny operatora:

```text
CFGPROP.id
CFGPROP.value
CFGPROP.status
CFGPROP.name
CFGPROP.mastervalue
```

Plan pokazał również mapowanie:

```text
sys.configurations.value
    ← CONVERT(sql_variant, CFGPROP.mastervalue)

sys.configurations.value_in_use
    ← CONVERT(sql_variant, CFGPROP.value)
```

Czyli w tym planie:

```text
CFGPROP.mastervalue → configured value
CFGPROP.value       → runtime value
```

Filtr `is_not_use = 0` z definicji widoku był realizowany przez bit w `CFGPROP.status`.

---

# 6. ETAP 4 - test sp_configure + RECONFIGURE razem

Ustaw Procmon:

```text
Process Name    is    sqlservr.exe    Include
```

Na początku nie zawężaj po `master.mdf` ani Registry.

Wyczyść capture i uruchom:

```sql
EXEC sys.sp_configure
    N'user instance timeout',
    61;
GO

RECONFIGURE;
GO
```

Sprawdź:

```sql
SELECT
    configuration_id,
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO
```

W teście referencyjnym po wykonaniu całości:

```text
value        = 61
value_in_use = 61
```

Następnie filtr Procmon:

```text
Process Name    is         sqlservr.exe    Include
Path            contains   master.mdf      Include
```

Zaobserwowano dwa zapisy:

```text
WriteFile master.mdf
Offset: 81 920
Length: 8 192
Non-cached, Write Through
```

Dla MDF/NDF:

```text
PageID = Offset / 8192
```

czyli:

```text
81 920 / 8 192 = 10
```

To prowadzi do:

```text
master:1:10
```

---

# 7. ETAP 5 - identyfikacja strony 10

Dla SQL Server 2019+:

```sql
USE master;
GO

SELECT
    database_id,
    file_id,
    page_id,
    page_type,
    page_type_desc,
    object_id,
    index_id,
    partition_id,
    alloc_unit_id
FROM sys.dm_db_page_info
(
    DB_ID('master'),
    1,
    10,
    'DETAILED'
);
GO
```

W teście referencyjnym:

```text
master:1:10
page_type_desc = SYSCONFIG_PAGE
```

To jest kluczowe połączenie:

```text
Procmon Offset 81 920
        ↓
PageID 10
        ↓
SYSCONFIG_PAGE
```

---

# 8. ETAP 6 - czy zapis trafia do Registry

Na tym samym krótkim capture zastosuj:

```text
Process Name    is            sqlservr.exe    Include
Operation       begins with   Reg             Include
```

Opcjonalnie zawęź czas do momentu eksperymentu.

Szukaj szczególnie:

```text
RegSetValue
RegCreateKey
RegDeleteValue
```

W kontrolowanym teście dla `user instance timeout` nie zaobserwowano zapisu Registry w momencie zmiany i `RECONFIGURE`.

Wniosek należy formułować precyzyjnie:

> Dla badanego ustawienia i tego konkretnego testu nie zaobserwowano zapisu Registry. Nie oznacza to, że żadna konfiguracja SQL Server nigdy nie korzysta z Registry.

---

# 9. ETAP 7 - rozdzielenie sp_configure od RECONFIGURE

To najważniejszy eksperyment kontrolny.

## 9.1. Samo sp_configure

Załóżmy stan początkowy:

```text
value        = 61
value_in_use = 61
```

Uruchom Procmon z filtrem:

```text
Process Name    is         sqlservr.exe    Include
Path            ends with  master.mdf      Include
```

Następnie wykonaj tylko:

```sql
EXEC sys.sp_configure
    N'user instance timeout',
    64;
GO
```

Bez `RECONFIGURE`.

Sprawdź:

```sql
SELECT
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO
```

W teście referencyjnym:

```text
value        = 64
value_in_use = 61
```

W capture pojawiły się inne zapisy do `master.mdf`, ale nie było:

```text
Offset 81 920
Length 8 192
```

czyli nie zaobserwowano zapisu `master:1:10`.

Wniosek:

```text
sp_configure
    ↓
zmienia configured value
    ↓
value = 64
value_in_use = 61
    ↓
brak WriteFile do SYSCONFIG_PAGE w tym eksperymencie
```

Nie należy przypisywać innych zapisów do `master.mdf` mechanizmowi konfiguracji bez dodatkowego mapowania stron i stacków.

---

# 10. ETAP 8 - samo RECONFIGURE

Mamy idealny stan pośredni:

```text
value        = 64
value_in_use = 61
```

W Procmon:

```text
Process Name    is         sqlservr.exe    Include
Path            ends with  master.mdf      Include
```

Wyczyść capture i wykonaj wyłącznie:

```sql
RECONFIGURE;
GO
```

Następnie:

```sql
SELECT
    configuration_id,
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO
```

W teście referencyjnym wynik po `RECONFIGURE`:

```text
value        = 64
value_in_use = 64
```

Procmon pokazał dwa zapisy:

```text
11:59:04.3084838  WriteFile master.mdf
Offset: 81 920
Length: 8 192
Non-cached, Write Through

11:59:04.3317688  WriteFile master.mdf
Offset: 81 920
Length: 8 192
Non-cached, Write Through
```

Oba trafiają do:

```text
master:1:10
SYSCONFIG_PAGE
```

Kluczowy wniosek eksperymentalny:

```text
sp_configure 64
    ↓
value = 64
value_in_use = 61
    ↓
RECONFIGURE
    ↓
2 x WriteFile master:1:10
    ↓
value = 64
value_in_use = 64
```

---

# 11. ETAP 9 - stack pierwszego zapisu SYSCONFIG_PAGE

Otwórz pierwszy `WriteFile`:

```text
Event Properties -> Stack
```

Kluczowy fragment stacku z testu referencyjnego:

```text
sqlmin.dll  reconfig
sqlmin.dll  SysConfigPagePtr::Write
sqlmin.dll  SysConfigPagePtr::IsAWE_SKU
sqlmin.dll  AcquireBulkOperationLock
sqlmin.dll  FCB::SyncWrite
sqlmin.dll  FCB::AsyncWrite
sqlmin.dll  FCB::AsyncWriteInternal
sqlmin.dll  DiskWriteAsync
KERNELBASE.dll WriteFile
ntdll.dll      ZwWriteFile
ntoskrnl.exe   NtWriteFile
ntoskrnl.exe   IofCallDriver
FLTMGR.SYS
```

Czytając przyczynowo od starszych callerów do aktualnej operacji:

```text
T-SQL RECONFIGURE
    ↓
sqllang!CSQLSource::Execute
    ↓
sqlmin!reconfig
    ↓
sqlmin!SysConfigPagePtr::Write
    ↓
sqlmin!FCB::SyncWrite
    ↓
sqlmin!FCB::AsyncWrite
    ↓
sqlmin!DiskWriteAsync
    ↓
KERNELBASE!WriteFile
    ↓
ntdll!ZwWriteFile
    ↓
ntoskrnl!NtWriteFile
    ↓
IofCallDriver
    ↓
FLTMGR.SYS
```

To jest bezpośredni most między:

```text
RECONFIGURE
```

a fizycznym:

```text
WriteFile master.mdf : page 10
```

---

# 12. ETAP 10 - stack drugiego zapisu

Drugi `WriteFile` do tego samego offsetu miał bardzo podobny, ale nie identyczny stack.

Kluczowy fragment:

```text
sqlmin.dll  reconfig
sqlmin.dll  SysConfigPagePtr::IsAWE_SKU
sqlmin.dll  AcquireBulkOperationLock
sqlmin.dll  FCB::SyncWrite
sqlmin.dll  FCB::AsyncWrite
sqlmin.dll  FCB::AsyncWriteInternal
sqlmin.dll  DiskWriteAsync
KERNELBASE.dll WriteFile
```

Pierwszy stack zawierał jawnie:

```text
SysConfigPagePtr::Write
```

Drugi nie miał tej samej ramki w identycznym miejscu.

Nie należy z tego automatycznie wyciągać wniosku, że poznaliśmy dokładne dwie logiczne fazy `RECONFIGURE`.

Bezpieczny wniosek:

> `RECONFIGURE` spowodowało w tym przebiegu dwie osobne operacje zapisu tej samej strony `SYSCONFIG_PAGE`, a stacki prowadzą przez wspólny rdzeń `reconfig -> SysConfigPagePtr -> FCB -> DiskWriteAsync -> WriteFile`.

Pojedyncze nazwy funkcji z publicznych symboli należy interpretować ostrożnie, zwłaszcza gdy występują jako `symbol + offset`.

---

# 13. ETAP 11 - test trwałości po restarcie

Po `RECONFIGURE` sprawdź:

```sql
SELECT
    configuration_id,
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO
```

W teście:

```text
64 / 64
```

Następnie zrestartuj instancję.

Dla instancji domyślnej:

```powershell
Restart-Service MSSQLSERVER
```

Po starcie wykonaj ponownie:

```sql
SELECT
    configuration_id,
    name,
    value,
    value_in_use
FROM sys.configurations
WHERE name = N'user instance timeout';
GO
```

W teście referencyjnym po restarcie nadal było:

```text
value        = 64
value_in_use = 64
```

To potwierdza trwałość ustawienia między restartami dla badanego parametru.

---

# 14. Co ten scenariusz udowodnił

Dla SQL Server 2022 Express 16.0.4265.3 i `user instance timeout`:

1. `sys.configurations` jest widokiem odwołującym się do wewnętrznego `sys.configurations$`.
2. `sys.configurations$` nie był dostępny jako zwykły obiekt przez `OBJECT_ID` lub `sys.all_objects`.
3. Plan wykonania ujawnił wewnętrzny TVF `CFGPROP`.
4. `CFGPROP.mastervalue` odpowiadało `sys.configurations.value`.
5. `CFGPROP.value` odpowiadało `sys.configurations.value_in_use`.
6. Samo `sp_configure` zmieniło `value`, ale nie `value_in_use`.
7. W tym kontrolowanym teście samo `sp_configure` nie zapisało `master:1:10`.
8. `RECONFIGURE` zmieniło `value_in_use`.
9. `RECONFIGURE` wykonało dwa `WriteFile` do `master.mdf` pod offset `81 920`.
10. Offset `81 920` odpowiada `PageID 10`.
11. `master:1:10` zostało rozpoznane jako `SYSCONFIG_PAGE`.
12. Stack prowadził przez `reconfig`, `SysConfigPagePtr`, `FCB::SyncWrite`, `DiskWriteAsync`, `WriteFile`.
13. W kontrolowanym oknie nie zaobserwowano zapisu Registry dla tego ustawienia.
14. Po restarcie wartość nadal wynosiła `64 / 64`.

---

# 15. Czego nie należy nadinterpretować

Nie należy automatycznie twierdzić, że:

- każda opcja `sp_configure` zachowuje się identycznie,
- żadna konfiguracja SQL Server nigdy nie jest przechowywana w Registry,
- każde `RECONFIGURE` zawsze zapisuje stronę 10 dokładnie dwa razy,
- nazwa pojedynczej funkcji z publicznych symboli opisuje w 100% faktyczną prywatną implementację,
- wszystkie zapisy do `master.mdf` obserwowane podczas `sp_configure` są związane z konfiguracją.

Każdy taki wniosek wymaga osobnego kontrolowanego eksperymentu.

---

# 16. Szybka ściąga filtrów Procmon

## Cały krótki eksperyment

```text
Process Name is sqlservr.exe Include
```

## Tylko master.mdf

```text
Process Name is sqlservr.exe Include
Path ends with master.mdf Include
```

## Tylko Registry

```text
Process Name is sqlservr.exe Include
Operation begins with Reg Include
```

## Tylko fizyczne zapisy master.mdf

```text
Process Name is sqlservr.exe Include
Path ends with master.mdf Include
Operation is WriteFile Include
```

## Konkretna strona konfiguracyjna

W Procmon nie filtrujemy bezpośrednio po `Offset`, dlatego po filtrze `WriteFile` wyszukujemy w `Detail`:

```text
Offset: 81 920
Length: 8 192
```

---

# 17. Szablon do powtórzenia na innej instancji

```text
Server:
Edition:
Version:
Configuration option:
Initial value:
Initial value_in_use:

SHOWPLAN:
CFGPROP visible: YES / NO
mastervalue mapping:
value mapping:

sp_configure only:
new value:
value:
value_in_use:
WriteFile master:1:10: YES / NO

RECONFIGURE only:
value:
value_in_use:
WriteFile offset:
WriteFile length:
number of writes:

Calculated PageID:
Page type:

Registry write observed: YES / NO

Stack core:
reconfig ->
SysConfigPagePtr ->
FCB::SyncWrite ->
DiskWriteAsync ->
WriteFile

After restart:
value:
value_in_use:
```

---

# 18. Referencyjny przebieg scenariusza 02

```text
Baseline: 60 / 60
        ↓
SHOWPLAN
        ↓
CFGPROP
        ↓
sp_configure 64
        ↓
64 / 61
        ↓
no WriteFile master:1:10
        ↓
RECONFIGURE
        ↓
2 x WriteFile
master.mdf
Offset 81 920
Length 8 192
        ↓
master:1:10
SYSCONFIG_PAGE
        ↓
64 / 64
        ↓
restart SQL Server
        ↓
64 / 64
```

To jest kompletna, powtarzalna ścieżka diagnostyczna dla tego scenariusza.