/*
SQLDBA Emergency Toolkit - Extended Events: Blocking
Read-only diagnostic session.
Creates a server-level XE session and starts it.
Review output path before use in production.
*/

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SQLDBA_Blocking')
    DROP EVENT SESSION [SQLDBA_Blocking] ON SERVER;
GO

CREATE EVENT SESSION [SQLDBA_Blocking]
ON SERVER
ADD EVENT sqlserver.blocked_process_report
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_id,
        sqlserver.session_id,
        sqlserver.sql_text,
        sqlserver.username
    )
),
ADD EVENT sqlserver.lock_deadlock_chain
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_id,
        sqlserver.session_id,
        sqlserver.sql_text,
        sqlserver.username
    )
)
ADD TARGET package0.event_file
(
    SET filename = N'SQLDBA_Blocking.xel',
        max_file_size = 100,
        max_rollover_files = 5
)
WITH
(
    MAX_MEMORY = 4096 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    TRACK_CAUSALITY = ON,
    STARTUP_STATE = OFF
);
GO

ALTER EVENT SESSION [SQLDBA_Blocking] ON SERVER STATE = START;
GO

/*
Blocked process reports require blocked process threshold > 0.
Check only:
EXEC sys.sp_configure N'blocked process threshold (s)';
Do not change server configuration unless explicitly approved.
*/
