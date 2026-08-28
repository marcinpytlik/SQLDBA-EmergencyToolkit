SET NOCOUNT ON;

SELECT
    j.name AS job_name,
    j.enabled,
    SUSER_SNAME(j.owner_sid) AS owner_name,
    c.name AS category_name,
    ja.run_requested_date,
    ja.start_execution_date,
    ja.stop_execution_date,
    CASE
        WHEN ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL THEN 1
        ELSE 0
    END AS is_currently_running,
    h.run_status AS last_run_status,
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS last_run_datetime,
    h.message AS last_run_message
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.syscategories AS c
    ON j.category_id = c.category_id
LEFT JOIN msdb.dbo.sysjobactivity AS ja
    ON j.job_id = ja.job_id
   AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
OUTER APPLY
(
    SELECT TOP (1)
        h2.run_status,
        h2.run_date,
        h2.run_time,
        h2.message
    FROM msdb.dbo.sysjobhistory AS h2
    WHERE h2.job_id = j.job_id
      AND h2.step_id = 0
    ORDER BY h2.instance_id DESC
) AS h
ORDER BY is_currently_running DESC, j.enabled DESC, j.name;

SELECT
    j.name AS job_name,
    ja.start_execution_date,
    DATEDIFF(MINUTE, ja.start_execution_date, SYSDATETIME()) AS running_minutes,
    j.enabled
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobactivity AS ja
    ON j.job_id = ja.job_id
WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
  AND ja.start_execution_date IS NOT NULL
  AND ja.stop_execution_date IS NULL
ORDER BY ja.start_execution_date;
