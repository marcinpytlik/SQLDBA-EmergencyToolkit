/*
SQLDBA Emergency Toolkit
ActiveRequests.sql
Read-only diagnostic query.
*/
SET NOCOUNT ON;

SELECT
    r.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id) AS database_name,
    r.status,
    r.command,
    r.start_time,
    r.cpu_time,
    r.total_elapsed_time,
    r.reads,
    r.writes,
    r.logical_reads,
    r.wait_type,
    r.wait_time,
    r.wait_resource,
    r.blocking_session_id,
    r.percent_complete,
    r.estimated_completion_time,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    ) AS current_statement,
    t.text AS batch_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s
    ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;
