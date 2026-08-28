SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#vlf') IS NOT NULL DROP TABLE #vlf;
CREATE TABLE #vlf
(
    DatabaseName sysname,
    VlfCount int
);

DECLARE @db sysname, @sql nvarchar(max);
DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
SELECT name
FROM sys.databases
WHERE state_desc = 'ONLINE'
  AND database_id > 4;

OPEN dbs;
FETCH NEXT FROM dbs INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
        INSERT INTO #vlf(DatabaseName,VlfCount)
        SELECT DB_NAME(), COUNT(*)
        FROM sys.dm_db_log_info(DB_ID());';
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        INSERT INTO #vlf(DatabaseName,VlfCount) VALUES(@db,NULL);
    END CATCH;
    FETCH NEXT FROM dbs INTO @db;
END
CLOSE dbs;
DEALLOCATE dbs;

SELECT DatabaseName, VlfCount
FROM #vlf
ORDER BY VlfCount DESC, DatabaseName;
