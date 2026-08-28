SET NOCOUNT ON;
USE tempdb;

SELECT
    df.file_id,
    df.name,
    df.type_desc,
    CAST(df.size / 128.0 AS decimal(18,2)) AS size_mb,
    CASE WHEN df.is_percent_growth = 1
         THEN CAST(df.growth AS varchar(20)) + '%'
         ELSE CAST(df.growth / 128.0 AS varchar(20)) + ' MB'
    END AS autogrowth,
    CAST(FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 AS decimal(18,2)) AS used_mb,
    CAST((df.size - FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS decimal(18,2)) AS free_mb,
    df.physical_name
FROM sys.database_files AS df
ORDER BY df.file_id;

SELECT
    SUM(user_object_reserved_page_count) * 8.0 / 1024 AS user_objects_mb,
    SUM(internal_object_reserved_page_count) * 8.0 / 1024 AS internal_objects_mb,
    SUM(version_store_reserved_page_count) * 8.0 / 1024 AS version_store_mb,
    SUM(unallocated_extent_page_count) * 8.0 / 1024 AS unallocated_mb,
    SUM(mixed_extent_page_count) * 8.0 / 1024 AS mixed_extent_mb
FROM sys.dm_db_file_space_usage;

SELECT TOP (50)
    session_id,
    user_objects_alloc_page_count * 8.0 / 1024 AS user_alloc_mb,
    user_objects_dealloc_page_count * 8.0 / 1024 AS user_dealloc_mb,
    internal_objects_alloc_page_count * 8.0 / 1024 AS internal_alloc_mb,
    internal_objects_dealloc_page_count * 8.0 / 1024 AS internal_dealloc_mb
FROM sys.dm_db_session_space_usage
ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC;
