/* SQLDBA Emergency Toolkit - Extended Events: Deadlocks */
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SQLDBA_Deadlocks')
    DROP EVENT SESSION [SQLDBA_Deadlocks] ON SERVER;
GO
CREATE EVENT SESSION [SQLDBA_Deadlocks] ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
(
    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.session_id,sqlserver.sql_text,sqlserver.username)
)
ADD TARGET package0.event_file
(
    SET filename=N'SQLDBA_Deadlocks.xel',max_file_size=100,max_rollover_files=10
)
WITH(MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=5 SECONDS,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF);
GO
ALTER EVENT SESSION [SQLDBA_Deadlocks] ON SERVER STATE = START;
GO
