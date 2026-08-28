/* SQLDBA Emergency Toolkit - Extended Events: Long-running queries
Default threshold: 5 seconds (duration is microseconds).
Tune predicate before production use.
*/
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SQLDBA_LongRunning')
    DROP EVENT SESSION [SQLDBA_LongRunning] ON SERVER;
GO
CREATE EVENT SESSION [SQLDBA_LongRunning] ON SERVER
ADD EVENT sqlserver.rpc_completed
(
    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.session_id,sqlserver.sql_text,sqlserver.username)
    WHERE ([duration] >= 5000000)
),
ADD EVENT sqlserver.sql_batch_completed
(
    ACTION(sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_id,sqlserver.session_id,sqlserver.sql_text,sqlserver.username)
    WHERE ([duration] >= 5000000)
)
ADD TARGET package0.event_file
(
    SET filename=N'SQLDBA_LongRunning.xel',max_file_size=200,max_rollover_files=5
)
WITH(MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=10 SECONDS,TRACK_CAUSALITY=ON,STARTUP_STATE=OFF);
GO
ALTER EVENT SESSION [SQLDBA_LongRunning] ON SERVER STATE = START;
GO
