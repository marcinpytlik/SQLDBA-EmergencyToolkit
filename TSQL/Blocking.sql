/* SQLDBA Emergency Toolkit - read-only */
SET NOCOUNT ON;

SELECT
    r.session_id,
    r.blocking_session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id) AS database_name,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.cpu_time,
    r.total_elapsed_time,
    t.text AS batch_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.blocking_session_id <> 0
   OR EXISTS (
        SELECT 1
        FROM sys.dm_exec_requests AS r2
        WHERE r2.blocking_session_id = r.session_id
   )
ORDER BY CASE WHEN r.blocking_session_id = 0 THEN 0 ELSE 1 END,
         r.blocking_session_id,
         r.session_id;
