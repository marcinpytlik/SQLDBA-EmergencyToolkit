SET NOCOUNT ON;

;WITH io AS
(
    SELECT
        DB_NAME(vfs.database_id) AS DatabaseName,
        mf.type_desc,
        mf.name AS LogicalName,
        mf.physical_name,
        vfs.num_of_reads,
        vfs.num_of_writes,
        vfs.num_of_bytes_read,
        vfs.num_of_bytes_written,
        vfs.io_stall_read_ms,
        vfs.io_stall_write_ms,
        vfs.size_on_disk_bytes,
        CASE WHEN vfs.num_of_reads = 0 THEN NULL ELSE CAST(1.0 * vfs.io_stall_read_ms / vfs.num_of_reads AS decimal(18,2)) END AS AvgReadLatencyMs,
        CASE WHEN vfs.num_of_writes = 0 THEN NULL ELSE CAST(1.0 * vfs.io_stall_write_ms / vfs.num_of_writes AS decimal(18,2)) END AS AvgWriteLatencyMs
    FROM sys.dm_io_virtual_file_stats(NULL,NULL) vfs
    JOIN sys.master_files mf
      ON mf.database_id = vfs.database_id
     AND mf.file_id = vfs.file_id
)
SELECT *
FROM io
ORDER BY
    CASE WHEN AvgReadLatencyMs IS NULL THEN 0 ELSE AvgReadLatencyMs END DESC,
    CASE WHEN AvgWriteLatencyMs IS NULL THEN 0 ELSE AvgWriteLatencyMs END DESC;
