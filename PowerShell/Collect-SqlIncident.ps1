param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $false)]
    [string]$ComputerName,

    [Parameter(Mandatory = $false)]
    [switch]$ResolveFciActiveNode,

    [Parameter(Mandatory = $false)]
    [switch]$CollectCluster,

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
$storageDir = Join-Path $incidentDir "Storage"
$clusterDir = Join-Path $incidentDir "Cluster"
$eventDir = Join-Path $incidentDir "EventLogs"
$notesDir = Join-Path $incidentDir "Notes"

@($incidentDir, $sqlDir, $networkDir, $osDir, $storageDir, $clusterDir, $eventDir, $notesDir) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

$fciResolution = $null
if ($ResolveFciActiveNode) {
    try {
        $sqlNetworkName = ($ServerInstance -split ',')[0]
        $resolver = Join-Path $ToolkitRoot "Cluster\Resolve-FciActiveNode.ps1"
        if (-not (Test-Path $resolver)) { throw "FCI resolver not found: $resolver" }
        $fciResolution = & $resolver -SqlNetworkName $sqlNetworkName
        if ($fciResolution.ActiveNode) {
            $ComputerName = [string]$fciResolution.ActiveNode
            $fciResolution | Export-Csv (Join-Path $clusterDir "FciResolution.csv") -NoTypeInformation -Encoding UTF8
        }
        else {
            throw "Resolver did not return ActiveNode."
        }
    }
    catch {
        $_ | Out-File (Join-Path $clusterDir "FciResolution-error.txt") -Encoding utf8
    }
}

$osTarget = if ([string]::IsNullOrWhiteSpace($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }
$osMode = if ([string]::IsNullOrWhiteSpace($ComputerName)) { "Local" } else { "Remote" }

$meta = [pscustomobject]@{
    CollectedAt          = Get-Date
    CollectorHost        = $env:COMPUTERNAME
    CollectorUser        = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    ServerInstance       = $ServerInstance
    ComputerName         = $osTarget
    OSCollection         = $osMode
    ResolveFciActiveNode = [bool]$ResolveFciActiveNode
    CollectCluster       = [bool]$CollectCluster
    Database             = $Database
    ToolkitRoot          = $ToolkitRoot
    PowerShell           = $PSVersionTable.PSVersion.ToString()
    ToolkitVersion       = "1.0"
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
    @{ Name = "StorageIO";      File = "StorageIO.sql";      Database = "master" },
    @{ Name = "FileGrowth";     File = "FileGrowth.sql";     Database = "master" },
    @{ Name = "VLF";            File = "VLF.sql";            Database = "master" },
    @{ Name = "TempdbIO";       File = "TempdbIO.sql";       Database = "tempdb" },
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
        Write-Host "Collecting Network diagnostics from $env:COMPUTERNAME to $ServerInstance..."
        & $networkScript -ServerInstance $ServerInstance -OutputPath $networkDir | Out-String |
            Out-File (Join-Path $networkDir "Network-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $networkDir "Network-Collector-error.txt") -Encoding utf8
    }
}

if ($CollectCluster) {
    $clusterSnapshotScript = Join-Path $ToolkitRoot "Cluster\Get-ClusterSnapshot.ps1"
    if (Test-Path $clusterSnapshotScript) {
        try {
            Write-Host "Collecting cluster diagnostics..."
            & $clusterSnapshotScript -OutputPath $clusterDir | Out-String |
                Out-File (Join-Path $clusterDir "Cluster-Console.txt") -Encoding utf8
        }
        catch {
            $_ | Out-File (Join-Path $clusterDir "Cluster-Collector-error.txt") -Encoding utf8
        }
    }
}

if ($osMode -eq 'Remote') {
    $remoteOSScript = Join-Path $ToolkitRoot "OS\Get-RemoteOSSnapshot.ps1"
    if (Test-Path $remoteOSScript) {
        try {
            Write-Host "Collecting remote Windows/OS diagnostics from $osTarget..."
            & $remoteOSScript -ComputerName $osTarget -OutputPath $osDir | Out-String |
                Out-File (Join-Path $osDir "OS-Console.txt") -Encoding utf8
        }
        catch {
            $_ | Out-File (Join-Path $osDir "OS-Collector-error.txt") -Encoding utf8
        }
    }
}
else {
    $osSnapshotScript = Join-Path $ToolkitRoot "OS\Get-OSSnapshot.ps1"
    if (Test-Path $osSnapshotScript) {
        try {
            Write-Host "Collecting local Windows/OS diagnostics..."
            & $osSnapshotScript -OutputPath $osDir | Out-String |
                Out-File (Join-Path $osDir "OS-Console.txt") -Encoding utf8
        }
        catch {
            $_ | Out-File (Join-Path $osDir "OS-Collector-error.txt") -Encoding utf8
        }
    }

    $topProcessesScript = Join-Path $ToolkitRoot "OS\Get-TopProcesses.ps1"
    if (Test-Path $topProcessesScript) {
        try { & $topProcessesScript -OutputPath $osDir }
        catch { $_ | Out-File (Join-Path $osDir "TopProcesses-error.txt") -Encoding utf8 }
    }
}

$storageScript = Join-Path $ToolkitRoot "OS\Get-StorageSnapshot.ps1"
if (Test-Path $storageScript) {
    try {
        Write-Host "Collecting Windows storage diagnostics from $osTarget..."
        & $storageScript -ComputerName $osTarget -OutputPath $storageDir | Out-String |
            Out-File (Join-Path $storageDir "Storage-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $storageDir "Storage-Collector-error.txt") -Encoding utf8
    }
}

try {
    if ($osMode -eq 'Remote') {
        Get-WinEvent -ComputerName $osTarget -LogName System -MaxEvents 500 |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv (Join-Path $eventDir "System.csv") -NoTypeInformation -Encoding UTF8
    }
    else {
        Get-WinEvent -LogName System -MaxEvents 500 |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv (Join-Path $eventDir "System.csv") -NoTypeInformation -Encoding UTF8
    }
}
catch { $_ | Out-File (Join-Path $eventDir "System-error.txt") -Encoding utf8 }

try {
    if ($osMode -eq 'Remote') {
        Get-WinEvent -ComputerName $osTarget -LogName Application -MaxEvents 500 |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv (Join-Path $eventDir "Application.csv") -NoTypeInformation -Encoding UTF8
    }
    else {
        Get-WinEvent -LogName Application -MaxEvents 500 |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv (Join-Path $eventDir "Application.csv") -NoTypeInformation -Encoding UTF8
    }
}
catch { $_ | Out-File (Join-Path $eventDir "Application-error.txt") -Encoding utf8 }

@"
Incident notes
==============
Start time:
Symptoms:
Affected applications:
Recent changes:
Actions already taken:
SQL target: $ServerInstance
Windows target: $osTarget
OS collection mode: $osMode
FCI active-node resolution: $ResolveFciActiveNode
Cluster collection: $CollectCluster
Storage symptoms / affected volume:
Extended Events session started:
Extended Events start time:
ProcDump/WPR started:
ProcDump/WPR output path:
Additional observations:
"@ | Out-File (Join-Path $notesDir "incident-notes.txt") -Encoding utf8

$summaryScript = Join-Path $ToolkitRoot "Reports\New-IncidentSummary.ps1"
if (Test-Path $summaryScript) {
    try {
        Write-Host "Generating incident summary..."
        & $summaryScript -IncidentPath $incidentDir | Out-String |
            Out-File (Join-Path $incidentDir "Incident-Report-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $incidentDir "Incident-Report-error.txt") -Encoding utf8
    }
}

$htmlScript = Join-Path $ToolkitRoot "Reports\New-IncidentHtmlReport.ps1"
if (Test-Path $htmlScript) {
    try {
        Write-Host "Generating HTML health report..."
        & $htmlScript -IncidentPath $incidentDir | Out-String |
            Out-File (Join-Path $incidentDir "Incident-HtmlReport-Console.txt") -Encoding utf8
    }
    catch {
        $_ | Out-File (Join-Path $incidentDir "Incident-HtmlReport-error.txt") -Encoding utf8
    }
}

Write-Host ""
Write-Host "Incident package created: $incidentDir"
Write-Host "SQL target: $ServerInstance"
Write-Host "Windows target: $osTarget ($osMode)"
Write-Host "Storage diagnostics: $storageDir"
Write-Host "Incident summary: $(Join-Path $incidentDir 'Incident-Summary.md')"
Write-Host "HTML report: $(Join-Path $incidentDir 'Incident-Report.html')"
if ($ResolveFciActiveNode) { Write-Host "FCI active-node resolution requested." }
if ($CollectCluster) { Write-Host "Cluster snapshot requested." }
Write-Host "Review *-error.txt files to see which collectors could not run."
Write-Host "XE sessions, ProcDump, WPR and cluster failover actions are NOT started automatically."
