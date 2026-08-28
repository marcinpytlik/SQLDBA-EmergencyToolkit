SET NOCOUNT ON;

SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    d.log_reuse_wait_desc,
    ls.total_log_size_mb,
    ls.active_log_size_mb,
    CAST(CASE WHEN ls.total_log_size_mb = 0 THEN 0 ELSE ls.active_log_size_mb * 100.0 / ls.total_log_size_mb END AS decimal(10,2)) AS active_log_percent
FROM sys.databases AS d
CROSS APPLY sys.dm_db_log_stats(d.database_id) AS ls
WHERE d.state_desc = 'ONLINE'
ORDER BY active_log_percent DESC, d.name;

SELECT
    DB_NAME(database_id) AS database_name,
    total_log_size_in_bytes / 1048576.0 AS total_log_size_mb,
    used_log_space_in_bytes / 1048576.0 AS used_log_space_mb,
    used_log_space_in_percent
FROM sys.dm_db_log_space_usage;
