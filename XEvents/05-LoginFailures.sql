/* SQLDBA Emergency Toolkit - Extended Events: Login failures */
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SQLDBA_LoginFailures')
    DROP EVENT SESSION [SQLDBA_LoginFailures] ON SERVER;
GO
CREATE EVENT SESSION [SQLDBA_LoginFailures] ON SERVER
ADD EVENT sqlserver.error_reported
(
    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.session_id,sqlserver.username)
    WHERE ([error_number]=(18456))
)
ADD TARGET package0.event_file
(
    SET filename=N'SQLDBA_LoginFailures.xel',max_file_size=100,max_rollover_files=5
)
WITH(MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=5 SECONDS,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF);
GO
ALTER EVENT SESSION [SQLDBA_LoginFailures] ON SERVER STATE = START;
GO
