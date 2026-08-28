SET NOCOUNT ON;

WITH LastBackups AS
(
    SELECT
        bs.database_name,
        bs.type,
        MAX(bs.backup_finish_date) AS backup_finish_date
    FROM msdb.dbo.backupset AS bs
    GROUP BY bs.database_name, bs.type
)
SELECT
    d.name AS database_name,
    d.recovery_model_desc,
    MAX(CASE WHEN lb.type = 'D' THEN lb.backup_finish_date END) AS last_full_backup,
    MAX(CASE WHEN lb.type = 'I' THEN lb.backup_finish_date END) AS last_diff_backup,
    MAX(CASE WHEN lb.type = 'L' THEN lb.backup_finish_date END) AS last_log_backup
FROM sys.databases AS d
LEFT JOIN LastBackups AS lb
    ON lb.database_name = d.name
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;

SELECT TOP (50)
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    CASE bs.type
        WHEN 'D' THEN 'FULL'
        WHEN 'I' THEN 'DIFF'
        WHEN 'L' THEN 'LOG'
        ELSE bs.type
    END AS backup_type,
    CAST(bs.backup_size / 1048576.0 AS decimal(18,2)) AS backup_size_mb,
    CAST(bs.compressed_backup_size / 1048576.0 AS decimal(18,2)) AS compressed_backup_size_mb,
    bs.is_copy_only,
    bs.has_backup_checksums,
    bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf
    ON bs.media_set_id = bmf.media_set_id
ORDER BY bs.backup_finish_date DESC;
