param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\OSSnapshot"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

function Write-CollectorError {
    param([string]$Name,[object]$ErrorRecord)
    $ErrorRecord | Out-String | Out-File (Join-Path $OutputPath "$Name-error.txt") -Encoding utf8
}

$cim = $null
try {
    $cim = New-CimSession -ComputerName $ComputerName
    [pscustomobject]@{
        ComputerName = $ComputerName
        CimSessionCreated = $true
        CollectedAt = Get-Date
    } | Export-Csv (Join-Path $OutputPath 'Remote-Collector-Status.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Write-CollectorError 'CimSession' $_
    throw
}

try {
    Get-CimInstance Win32_OperatingSystem -CimSession $cim |
        Select-Object CSName, Caption, Version, BuildNumber, LastBootUpTime,
            @{n='TotalMemoryGB';e={[math]::Round($_.TotalVisibleMemorySize/1MB,2)}},
            @{n='FreeMemoryGB';e={[math]::Round($_.FreePhysicalMemory/1MB,2)}} |
        Export-Csv (Join-Path $OutputPath 'OS.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'OS' $_ }

try {
    Get-CimInstance Win32_Processor -CimSession $cim |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, LoadPercentage |
        Export-Csv (Join-Path $OutputPath 'CPU.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'CPU' $_ }

try {
    Get-CimInstance Win32_LogicalDisk -CimSession $cim -Filter "DriveType=3" |
        Select-Object DeviceID, VolumeName, FileSystem,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},
            @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,2)}},
            @{n='FreePercent';e={if ($_.Size) {[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}} |
        Export-Csv (Join-Path $OutputPath 'Disks.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Disks' $_ }

try {
    Get-CimInstance Win32_Process -CimSession $cim -Filter "Name='sqlservr.exe'" |
        Select-Object ProcessId, Name, CreationDate, WorkingSetSize, PageFileUsage, HandleCount, ThreadCount, CommandLine |
        Export-Csv (Join-Path $OutputPath 'SqlServerProcesses.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'SqlServerProcesses' $_ }

try {
    Get-CimInstance Win32_PageFileUsage -CimSession $cim |
        Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage |
        Export-Csv (Join-Path $OutputPath 'PageFile.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'PageFile' $_ }

try {
    Get-CimInstance Win32_Service -CimSession $cim |
        Where-Object { $_.Name -match '^MSSQL|^SQLAgent|SQLBrowser|ClusSvc' } |
        Select-Object Name, DisplayName, State, StartMode, StartName, ProcessId |
        Export-Csv (Join-Path $OutputPath 'Services.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Services' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -CimSession $cim -Filter "Name='_Total'" |
        Select-Object Name, PercentProcessorTime, PercentPrivilegedTime, PercentUserTime |
        Export-Csv (Join-Path $OutputPath 'Perf-CPU.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Perf-CPU' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -CimSession $cim |
        Select-Object AvailableMBytes, PagesPersec, PageReadsPersec, PageWritesPersec |
        Export-Csv (Join-Path $OutputPath 'Perf-Memory.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Perf-Memory' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -CimSession $cim |
        Select-Object Name, AvgDisksecPerRead, AvgDisksecPerWrite, AvgDiskQueueLength, DiskReadsPersec, DiskWritesPersec |
        Export-Csv (Join-Path $OutputPath 'Perf-Disk.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Perf-Disk' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -CimSession $cim |
        Where-Object { $_.Name -notin @('_Total','Idle') } |
        Sort-Object PercentProcessorTime -Descending |
        Select-Object -First 25 Name, IDProcess, PercentProcessorTime, WorkingSetPrivate, ThreadCount, HandleCount |
        Export-Csv (Join-Path $OutputPath 'TopProcessesByCPU.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'TopProcessesByCPU' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -CimSession $cim |
        Where-Object { $_.Name -notin @('_Total','Idle') } |
        Sort-Object WorkingSetPrivate -Descending |
        Select-Object -First 25 Name, IDProcess, PercentProcessorTime, WorkingSetPrivate, ThreadCount, HandleCount |
        Export-Csv (Join-Path $OutputPath 'TopProcessesByMemory.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'TopProcessesByMemory' $_ }

try {
    Get-WinEvent -ComputerName $ComputerName -LogName System -MaxEvents 500 |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv (Join-Path $OutputPath 'System-EventLog.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'System-EventLog' $_ }

try {
    Get-WinEvent -ComputerName $ComputerName -LogName Application -MaxEvents 500 |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv (Join-Path $OutputPath 'Application-EventLog.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Application-EventLog' $_ }

if ($cim) { Remove-CimSession $cim }
Write-Host "Remote OS snapshot written to: $OutputPath"
