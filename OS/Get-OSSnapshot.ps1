param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\OSSnapshot"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

function Write-CollectorError {
    param([string]$Name,[object]$ErrorRecord)
    $ErrorRecord | Out-String | Out-File (Join-Path $OutputPath "$Name-error.txt") -Encoding utf8
}

try {
    Get-CimInstance Win32_OperatingSystem |
        Select-Object CSName, Caption, Version, BuildNumber, LastBootUpTime,
            @{n='TotalMemoryGB';e={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}},
            @{n='FreeMemoryGB';e={[math]::Round($_.FreePhysicalMemory/1MB,2)}} |
        Export-Csv (Join-Path $OutputPath 'OS.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'OS' $_ }

try {
    Get-CimInstance Win32_Processor |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage |
        Export-Csv (Join-Path $OutputPath 'CPU.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'CPU' $_ }

try {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID, VolumeName, FileSystem,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},
            @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,2)}},
            @{n='FreePercent';e={if ($_.Size) {[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}} |
        Export-Csv (Join-Path $OutputPath 'Disks.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Disks' $_ }

try {
    Get-Process sqlservr -ErrorAction Stop |
        Select-Object Id, ProcessName, StartTime,
            @{n='CPUSeconds';e={[math]::Round($_.CPU,2)}},
            @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,2)}},
            @{n='PrivateMemoryMB';e={[math]::Round($_.PrivateMemorySize64/1MB,2)}},
            Handles, Threads |
        Export-Csv (Join-Path $OutputPath 'SqlServerProcesses.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'SqlServerProcesses' $_ }

try {
    Get-NetTCPConnection -State Established -ErrorAction Stop |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
        Export-Csv (Join-Path $OutputPath 'EstablishedTCP.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'EstablishedTCP' $_ }

try {
    Get-Counter -Counter @(
        '\Processor(_Total)\% Processor Time',
        '\System\Processor Queue Length',
        '\Memory\Available MBytes',
        '\Memory\Pages/sec',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length'
    ) -SampleInterval 1 -MaxSamples 5 |
        ForEach-Object { $_.CounterSamples } |
        Select-Object Timestamp, Path, CookedValue |
        Export-Csv (Join-Path $OutputPath 'PerfCounters.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'PerfCounters' $_ }

try {
    Get-CimInstance Win32_PageFileUsage |
        Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage |
        Export-Csv (Join-Path $OutputPath 'PageFile.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'PageFile' $_ }

try {
    Get-CimInstance Win32_Service |
        Where-Object { $_.Name -match '^MSSQL|^SQLAgent|SQLBrowser|ClusSvc' } |
        Select-Object Name, DisplayName, State, StartMode, StartName, ProcessId |
        Export-Csv (Join-Path $OutputPath 'Services.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Services' $_ }

Write-Host "OS snapshot written to: $OutputPath"
