param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $false)]
    [string]$Database = "master",

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = ".\Incidents",

    [Parameter(Mandatory = $false)]
    [string]$ToolkitRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$incidentDir = Join-Path $OutputRoot "Incident-$timestamp"
$sqlDir = Join-Path $incidentDir "SQL"
$networkDir = Join-Path $incidentDir "Network"
$osDir = Join-Path $incidentDir "OS"
$eventDir = Join-Path $incidentDir "EventLogs"
$notesDir = Join-Path $incidentDir "Notes"

@($incidentDir, $sqlDir, $networkDir, $osDir, $eventDir, $notesDir) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

$meta = [pscustomobject]@{
    CollectedAt    = Get-Date
    CollectorHost  = $env:COMPUTERNAME
    CollectorUser  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    ServerInstance = $ServerInstance
    Database       = $Database
    ToolkitRoot    = $ToolkitRoot
    PowerShell     = $PSVersionTable.PSVersion.ToString()
    ToolkitVersion = "0.5"
}
$meta | Export-Csv (Join-Path $incidentDir "incident-metadata.csv") -NoTypeInformation -Encoding UTF8

function Write-ErrorFile {
    param([string]$Name, [object]$ErrorRecord)
    $ErrorRecord | Out-String | Out-File (Join-Path $sqlDir "$Name-error.txt") -Encoding utf8
}

function Invoke-ToolkitQuery {
    param(
        [string]$Name,
        [string]$Path,
        [string]$TargetDatabase = "master"
    )

    if (-not (Test-Path $Path)) {
        "Script not found: $Path" | Out-File (Join-Path $sqlDir "$Name-error.txt") -Encoding utf8
        return
    }

    $query = Get-Content -Path $Path -Raw

    try {
        if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
            $result = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $TargetDatabase -Query $query -QueryTimeout 60 -TrustServerCertificate
        }
        elseif (Get-Command Invoke-DbaQuery -ErrorAction SilentlyContinue) {
            $result = Invoke-DbaQuery -SqlInstance $ServerInstance -Database $TargetDatabase -Query $query -EnableException
        }
        else {
            throw "Neither Invoke-Sqlcmd nor Invoke-DbaQuery is available. Install the SqlServer or dbatools PowerShell module."
        }

        if ($null -ne $result) {
            $result | Export-Csv (Join-Path $sqlDir "$Name.csv") -NoTypeInformation -Encoding UTF8
        }
        else {
            "Query completed but returned no rows." | Out-File (Join-Path $sqlDir "$Name.txt") -Encoding utf8
        }
    }
    catch {
        Write-ErrorFile -Name $Name -ErrorRecord $_
    }
}

$scriptMap = @(
    @{ Name = "ActiveRequests"; File = "ActiveRequests.sql"; Database = "master" },
    @{ Name = "Blocking";       File = "Blocking.sql";       Database = "master" },
    @{ Name = "WaitStats";      File = "WaitStats.sql";      Database = "master" },
    @{ Name = "IOStats";        File = "IOStats.sql";        Database = "master" },
    @{ Name = "Memory";         File = "Memory.sql";         Database = "master" },
    @{ Name = "TempDB";         File = "TempDB.sql";         Database = "tempdb" },
    @{ Name = "Log";            File = "Log.sql";            Database = "master" },
    @{ Name = "Backups";        File = "Backups.sql";        Database = "master" },
    @{ Name = "AgentJobs";      File = "AgentJobs.sql";      Database = "msdb" },
    @{ Name = "Replication";    File = "Replication.sql";    Database = "master" },
    @{ Name = "AG";             File = "AG.sql";             Database = "master" },
    @{ Name = "XEventsStatus";  File = "XEventsStatus.sql";  Database = "master" },
    @{ Name = "QueryStore";     File = "QueryStore.sql";     Database = $Database }
)

foreach ($item in $scriptMap) {
    $path = Join-Path $ToolkitRoot (Join-Path "TSQL" $item.File)
    Write-Host ("Collecting {0}..." -f $item.Name)
    Invoke-ToolkitQuery -Name $item.Name -Path $path -TargetDatabase $item.Database
}

$networkScript = Join-Path $ToolkitRoot "Network\Test-SqlConnectivity.ps1"
if (Test-Path $networkScript) {
    try {
        Write-Host "Collecting Network diagnostics..."
        & $networkScript -ServerInstance $ServerInstance -OutputPath $networkDir | Out-String |
            Out-File (Join-Path $networkDir "Network-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $networkDir "Network-Collector-error.txt") -Encoding utf8
    }
}
else {
    "Network collector not found: $networkScript" | Out-File (Join-Path $networkDir "Network-Collector-error.txt") -Encoding utf8
}

$osSnapshotScript = Join-Path $ToolkitRoot "OS\Get-OSSnapshot.ps1"
if (Test-Path $osSnapshotScript) {
    try {
        Write-Host "Collecting Windows/OS diagnostics..."
        & $osSnapshotScript -OutputPath $osDir | Out-String |
            Out-File (Join-Path $osDir "OS-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $osDir "OS-Collector-error.txt") -Encoding utf8
    }
}
else {
    "OS collector not found: $osSnapshotScript" | Out-File (Join-Path $osDir "OS-Collector-error.txt") -Encoding utf8
}

$topProcessesScript = Join-Path $ToolkitRoot "OS\Get-TopProcesses.ps1"
if (Test-Path $topProcessesScript) {
    try {
        & $topProcessesScript -OutputPath $osDir
    }
    catch {
        $_ | Out-File (Join-Path $osDir "TopProcesses-error.txt") -Encoding utf8
    }
}

try {
    Get-WinEvent -LogName System -MaxEvents 500 |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv (Join-Path $eventDir "System.csv") -NoTypeInformation -Encoding UTF8
}
catch {
    $_ | Out-File (Join-Path $eventDir "System-error.txt") -Encoding utf8
}

try {
    Get-WinEvent -LogName Application -MaxEvents 500 |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv (Join-Path $eventDir "Application.csv") -NoTypeInformation -Encoding UTF8
}
catch {
    $_ | Out-File (Join-Path $eventDir "Application-error.txt") -Encoding utf8
}

@"
Incident notes
==============
Start time:
Symptoms:
Affected applications:
Recent changes:
Actions already taken:
Extended Events session started:
Extended Events start time:
ProcDump/WPR started:
ProcDump/WPR output path:
Additional observations:
"@ | Out-File (Join-Path $notesDir "incident-notes.txt") -Encoding utf8

Write-Host ""
Write-Host "Incident package created: $incidentDir"
Write-Host "Review *-error.txt files to see which collectors could not run."
Write-Host "XE sessions, ProcDump and WPR are NOT started automatically."
