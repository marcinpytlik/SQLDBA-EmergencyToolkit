/* SQLDBA Emergency Toolkit - Extended Events: I/O errors 823/824/825 */
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SQLDBA_IOErrors')
    DROP EVENT SESSION [SQLDBA_IOErrors] ON SERVER;
GO
CREATE EVENT SESSION [SQLDBA_IOErrors] ON SERVER
ADD EVENT sqlserver.error_reported
(
    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.session_id,sqlserver.sql_text,sqlserver.username)
    WHERE ([error_number]=(823) OR [error_number]=(824) OR [error_number]=(825))
)
ADD TARGET package0.event_file
(
    SET filename=N'SQLDBA_IOErrors.xel',max_file_size=100,max_rollover_files=10
)
WITH(MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=NO_EVENT_LOSS,MAX_DISPATCH_LATENCY=5 SECONDS,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF);
GO
ALTER EVENT SESSION [SQLDBA_IOErrors] ON SERVER STATE = START;
GO
