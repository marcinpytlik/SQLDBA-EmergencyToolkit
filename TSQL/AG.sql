SET NOCOUNT ON;

IF SERVERPROPERTY('IsHadrEnabled') = 1
BEGIN
    SELECT
        ag.name AS availability_group,
        ar.replica_server_name,
        ars.role_desc,
        ars.operational_state_desc,
        ars.connected_state_desc,
        ars.synchronization_health_desc
    FROM sys.availability_groups AS ag
    JOIN sys.availability_replicas AS ar
        ON ag.group_id = ar.group_id
    LEFT JOIN sys.dm_hadr_availability_replica_states AS ars
        ON ar.replica_id = ars.replica_id
       AND ars.is_local = 1;

    SELECT
        ag.name AS availability_group,
        DB_NAME(drs.database_id) AS database_name,
        ar.replica_server_name,
        drs.synchronization_state_desc,
        drs.synchronization_health_desc,
        drs.is_suspended,
        drs.suspend_reason_desc,
        drs.log_send_queue_size,
        drs.log_send_rate,
        drs.redo_queue_size,
        drs.redo_rate,
        drs.last_commit_time
    FROM sys.dm_hadr_database_replica_states AS drs
    JOIN sys.availability_replicas AS ar
        ON drs.replica_id = ar.replica_id
    JOIN sys.availability_groups AS ag
        ON ar.group_id = ag.group_id
    ORDER BY ag.name, database_name, ar.replica_server_name;
END
ELSE
BEGIN
    SELECT CAST('Always On Availability Groups are not enabled on this instance.' AS nvarchar(200)) AS information;
END;
