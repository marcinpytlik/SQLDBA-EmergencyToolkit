/* SQLDBA Emergency Toolkit - Read XE event files
Replace @Path with the actual .xel path or wildcard.
*/
DECLARE @Path nvarchar(4000) = N'C:\Temp\SQLDBA_*.xel';

SELECT
    object_name,
    file_name,
    file_offset,
    event_data
FROM sys.fn_xe_file_target_read_file(@Path, NULL, NULL, NULL)
ORDER BY file_name, file_offset;
