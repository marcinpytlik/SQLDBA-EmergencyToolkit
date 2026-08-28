param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\StorageSnapshot"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$target = if ([string]::IsNullOrWhiteSpace($ComputerName)) { $env:COMPUTERNAME } else { $ComputerName }

function Write-CollectorError {
    param([string]$Name,[object]$ErrorRecord)
    $ErrorRecord | Out-String | Out-File (Join-Path $OutputPath "$Name-error.txt") -Encoding utf8
}

try {
    Get-CimInstance Win32_LogicalDisk -ComputerName $target -Filter "DriveType=3" |
        Select-Object PSComputerName, DeviceID, VolumeName, FileSystem,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}},
            @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,2)}},
            @{n='FreePercent';e={if ($_.Size) {[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}} |
        Export-Csv (Join-Path $OutputPath 'Volumes.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'Volumes' $_ }

try {
    Get-CimInstance Win32_DiskDrive -ComputerName $target |
        Select-Object PSComputerName, Index, Model, InterfaceType, MediaType, SerialNumber,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,2)}} |
        Export-Csv (Join-Path $OutputPath 'PhysicalDisks.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'PhysicalDisks' $_ }

try {
    Get-CimInstance Win32_Volume -ComputerName $target |
        Where-Object { $_.DriveType -eq 3 } |
        Select-Object PSComputerName, DriveLetter, Label, FileSystem, DeviceID,
            @{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,2)}},
            @{n='FreeGB';e={[math]::Round($_.FreeSpace/1GB,2)}} |
        Export-Csv (Join-Path $OutputPath 'VolumeDetails.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'VolumeDetails' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ComputerName $target |
        Select-Object PSComputerName, Name, AvgDisksecPerRead, AvgDisksecPerWrite,
            AvgDiskQueueLength, CurrentDiskQueueLength, DiskReadsPersec, DiskWritesPersec,
            DiskReadBytesPersec, DiskWriteBytesPersec, PercentDiskTime |
        Export-Csv (Join-Path $OutputPath 'PhysicalDiskPerf.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'PhysicalDiskPerf' $_ }

try {
    Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -ComputerName $target |
        Where-Object { $_.Name -ne '_Total' } |
        Select-Object PSComputerName, Name, AvgDisksecPerRead, AvgDisksecPerWrite,
            AvgDiskQueueLength, CurrentDiskQueueLength, DiskReadsPersec, DiskWritesPersec,
            DiskReadBytesPersec, DiskWriteBytesPersec, PercentFreeSpace |
        Export-Csv (Join-Path $OutputPath 'LogicalDiskPerf.csv') -NoTypeInformation -Encoding UTF8
} catch { Write-CollectorError 'LogicalDiskPerf' $_ }

Write-Host "Storage snapshot written to: $OutputPath for $target"
