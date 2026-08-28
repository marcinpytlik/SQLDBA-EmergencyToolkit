SET NOCOUNT ON;

SELECT
    physical_memory_kb / 1024 AS physical_memory_mb,
    available_physical_memory_kb / 1024 AS available_physical_memory_mb,
    total_page_file_kb / 1024 AS total_page_file_mb,
    available_page_file_kb / 1024 AS available_page_file_mb,
    system_memory_state_desc
FROM sys.dm_os_sys_memory;

SELECT
    physical_memory_in_use_kb / 1024 AS sql_process_memory_mb,
    locked_page_allocations_kb / 1024 AS locked_pages_mb,
    large_page_allocations_kb / 1024 AS large_pages_mb,
    memory_utilization_percentage,
    process_physical_memory_low,
    process_virtual_memory_low
FROM sys.dm_os_process_memory;

SELECT TOP (25)
    type,
    pages_kb / 1024 AS pages_mb,
    virtual_memory_committed_kb / 1024 AS virtual_memory_committed_mb,
    awe_allocated_kb / 1024 AS awe_allocated_mb
FROM sys.dm_os_memory_clerks
ORDER BY pages_kb DESC;
