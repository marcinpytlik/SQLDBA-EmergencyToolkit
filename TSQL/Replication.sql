SET NOCOUNT ON;

IF OBJECT_ID('msdb.dbo.MSreplication_subscriptions') IS NOT NULL
BEGIN
    SELECT
        publisher,
        publisher_db,
        publication,
        subscriber,
        subscriber_db,
        subscription_type,
        sync_type,
        status
    FROM msdb.dbo.MSreplication_subscriptions
    ORDER BY publisher, publisher_db, publication, subscriber;
END;

IF OBJECT_ID('distribution.dbo.MSdistribution_agents') IS NOT NULL
BEGIN
    SELECT
        name,
        publisher_db,
        publication,
        subscriber_name,
        subscriber_db,
        subscription_type,
        job_id
    FROM distribution.dbo.MSdistribution_agents
    ORDER BY publisher_db, publication, subscriber_name;
END;

SELECT
    j.name AS replication_job,
    j.enabled,
    ja.start_execution_date,
    ja.stop_execution_date,
    CASE WHEN ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL THEN 1 ELSE 0 END AS is_running
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobactivity AS ja
    ON j.job_id = ja.job_id
   AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
WHERE j.category_id IN
(
    SELECT category_id
    FROM msdb.dbo.syscategories
    WHERE category_class = 1
      AND name LIKE 'REPL%'
)
ORDER BY j.name;
