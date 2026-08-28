SET NOCOUNT ON;

SELECT
    DB_NAME(database_id) AS DatabaseName,
    type_desc,
    name AS LogicalName,
    physical_name,
    CAST(size / 128.0 AS decimal(18,2)) AS SizeMB,
    CASE WHEN max_size = -1 THEN 'UNLIMITED' ELSE CAST(CAST(max_size / 128.0 AS decimal(18,2)) AS varchar(40)) END AS MaxSizeMB,
    is_percent_growth,
    CASE
        WHEN is_percent_growth = 1 THEN CAST(growth AS varchar(20)) + '%'
        ELSE CAST(CAST(growth / 128.0 AS decimal(18,2)) AS varchar(40)) + ' MB'
    END AS GrowthSetting
FROM sys.master_files
ORDER BY DB_NAME(database_id), type_desc, file_id;
