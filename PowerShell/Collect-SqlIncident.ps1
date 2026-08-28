param(
    [Parameter(Mandatory=$true)]
    [string]$ServerInstance,

    [Parameter(Mandatory=$false)]
    [string]$OutputRoot = ".\Incidents"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$incidentDir = Join-Path $OutputRoot "Incident-$timestamp"

$folders = @(
    $incidentDir,
    (Join-Path $incidentDir "SQL"),
    (Join-Path $incidentDir "Network"),
    (Join-Path $incidentDir "EventLogs"),
    (Join-Path $incidentDir "Notes")
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

$meta = [pscustomobject]@{
    CollectedAt    = Get-Date
    ComputerName   = $env:COMPUTERNAME
    UserName       = $env:USERNAME
    ServerInstance = $ServerInstance
}

$meta | Export-Csv (Join-Path $incidentDir "incident-metadata.csv") -NoTypeInformation -Encoding UTF8

try {
    Test-NetConnection -ComputerName ($ServerInstance.Split(',')[0]) |
        Format-List * |
        Out-File (Join-Path $incidentDir "Network\Test-NetConnection.txt") -Encoding utf8
}
catch {
    $_ | Out-File (Join-Path $incidentDir "Network\Test-NetConnection-error.txt") -Encoding utf8
}

try {
    Get-WinEvent -LogName System -MaxEvents 300 |
        Export-Csv (Join-Path $incidentDir "EventLogs\System.csv") -NoTypeInformation -Encoding UTF8
}
catch {
    $_ | Out-File (Join-Path $incidentDir "EventLogs\System-error.txt") -Encoding utf8
}

try {
    Get-WinEvent -LogName Application -MaxEvents 300 |
        Export-Csv (Join-Path $incidentDir "EventLogs\Application.csv") -NoTypeInformation -Encoding UTF8
}
catch {
    $_ | Out-File (Join-Path $incidentDir "EventLogs\Application-error.txt") -Encoding utf8
}

Write-Host "Incident package created: $incidentDir"
Write-Host "Next: collect SQL diagnostics and place results in the SQL folder."
