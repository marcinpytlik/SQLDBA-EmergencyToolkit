/* SQLDBA Emergency Toolkit - read-only */
SET NOCOUNT ON;

SELECT
    DB_NAME(vfs.database_id) AS database_name,
    mf.type_desc,
    mf.name AS logical_name,
    mf.physical_name,
    vfs.num_of_reads,
    vfs.io_stall_read_ms,
    CASE WHEN vfs.num_of_reads = 0 THEN 0
         ELSE CAST(1.0 * vfs.io_stall_read_ms / vfs.num_of_reads AS decimal(18,2)) END AS avg_read_ms,
    vfs.num_of_writes,
    vfs.io_stall_write_ms,
    CASE WHEN vfs.num_of_writes = 0 THEN 0
         ELSE CAST(1.0 * vfs.io_stall_write_ms / vfs.num_of_writes AS decimal(18,2)) END AS avg_write_ms,
    vfs.num_of_bytes_read,
    vfs.num_of_bytes_written,
    vfs.io_stall
FROM sys.dm_io_virtual_file_stats(NULL, NULL) AS vfs
JOIN sys.master_files AS mf
    ON mf.database_id = vfs.database_id
   AND mf.file_id = vfs.file_id
ORDER BY vfs.io_stall DESC;
