SET NOCOUNT ON;

SELECT
    DB_NAME() AS database_name,
    actual_state_desc,
    desired_state_desc,
    current_storage_size_mb,
    max_storage_size_mb,
    readonly_reason,
    interval_length_minutes,
    stale_query_threshold_days,
    query_capture_mode_desc,
    size_based_cleanup_mode_desc
FROM sys.database_query_store_options;

IF EXISTS (SELECT 1 FROM sys.database_query_store_options WHERE actual_state_desc <> 'OFF')
BEGIN
    SELECT TOP (25)
        q.query_id,
        p.plan_id,
        rs.count_executions,
        CAST(rs.avg_duration / 1000.0 AS decimal(18,2)) AS avg_duration_ms,
        CAST(rs.avg_cpu_time / 1000.0 AS decimal(18,2)) AS avg_cpu_ms,
        rs.avg_logical_io_reads,
        rs.avg_logical_io_writes,
        LEFT(qt.query_sql_text, 4000) AS query_sql_text
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    JOIN sys.query_store_query AS q ON q.query_id = p.query_id
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    ORDER BY rs.avg_duration DESC;
END;
