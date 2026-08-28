/* SQLDBA Emergency Toolkit - Extended Events status (read-only) */
SELECT
    ses.name AS session_name,
    CASE WHEN dxs.name IS NULL THEN 0 ELSE 1 END AS is_running,
    ses.startup_state,
    ses.event_retention_mode_desc,
    ses.max_dispatch_latency,
    ses.track_causality,
    st.target_name,
    CAST(st.target_data AS xml) AS target_data
FROM sys.server_event_sessions AS ses
LEFT JOIN sys.dm_xe_sessions AS dxs
    ON dxs.name = ses.name
LEFT JOIN sys.dm_xe_session_targets AS st
    ON st.event_session_address = dxs.address
WHERE ses.name LIKE N'SQLDBA[_]%'
ORDER BY ses.name, st.target_name;
