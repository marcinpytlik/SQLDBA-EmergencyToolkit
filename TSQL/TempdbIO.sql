SET NOCOUNT ON;

SELECT
    DB_NAME(vfs.database_id) AS DatabaseName,
    mf.file_id,
    mf.name AS LogicalName,
    mf.type_desc,
    mf.physical_name,
    CAST(mf.size / 128.0 AS decimal(18,2)) AS SizeMB,
    vfs.num_of_reads,
    vfs.num_of_writes,
    vfs.io_stall_read_ms,
    vfs.io_stall_write_ms,
    CASE WHEN vfs.num_of_reads = 0 THEN NULL ELSE CAST(1.0 * vfs.io_stall_read_ms / vfs.num_of_reads AS decimal(18,2)) END AS AvgReadLatencyMs,
    CASE WHEN vfs.num_of_writes = 0 THEN NULL ELSE CAST(1.0 * vfs.io_stall_write_ms / vfs.num_of_writes AS decimal(18,2)) END AS AvgWriteLatencyMs
FROM sys.dm_io_virtual_file_stats(2,NULL) vfs
JOIN tempdb.sys.database_files mf
  ON mf.file_id = vfs.file_id
ORDER BY mf.file_id;
