/* SQLDBA Emergency Toolkit - Stop emergency XE sessions */
DECLARE @Sessions table(name sysname);
INSERT INTO @Sessions(name) VALUES
(N'SQLDBA_Blocking'),
(N'SQLDBA_Deadlocks'),
(N'SQLDBA_LongRunning'),
(N'SQLDBA_IOErrors'),
(N'SQLDBA_LoginFailures'),
(N'SQLDBA_FileGrowth');

DECLARE @name sysname, @sql nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT s.name
FROM sys.dm_xe_sessions s
JOIN @Sessions e ON e.name = s.name;

OPEN c;
FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'ALTER EVENT SESSION ' + QUOTENAME(@name) + N' ON SERVER STATE = STOP;';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM c INTO @name;
END
CLOSE c;
DEALLOCATE c;
