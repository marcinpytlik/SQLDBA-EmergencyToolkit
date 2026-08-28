<#
.SYNOPSIS
    Copies binaries required for preparing an offline symbol cache for
    SQL Server / Procmon analysis from a production SQL Server host
    to a transfer location on a DBA workstation.

.DESCRIPTION
    The script:
      - collects selected Windows user-mode binaries,
      - collects kernel and storage/file-system drivers,
      - detects running sqlservr.exe processes and copies selected SQL Server binaries,
      - preserves files in separate Windows / Drivers / SQLServer folders,
      - writes an inventory with file versions, source paths and SHA256 hashes,
      - does NOT modify SQL Server, Windows configuration, services or registry.

    Recommended usage:
      Run on the SQL Server as an account that can read the files and write
      to the destination share.

    Example destination:
      \\DBAWORKSTATION\SQLSymbols$\Targets-SQLPROD01

.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeOptionalDrivers,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAllSqlBinnFiles,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[ OK ] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FileInventoryRecord {
    param(
        [string]$SourcePath,
        [string]$DestinationFile,
        [string]$Category
    )

    $item = Get-Item -LiteralPath $SourcePath -ErrorAction Stop
    $hash = Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256 -ErrorAction Stop

    [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        Category        = $Category
        FileName        = $item.Name
        SourcePath      = $item.FullName
        DestinationPath = $DestinationFile
        LengthBytes     = $item.Length
        FileVersion     = $item.VersionInfo.FileVersion
        ProductVersion  = $item.VersionInfo.ProductVersion
        SHA256          = $hash.Hash
        CopiedAt        = Get-Date
    }
}

function Copy-SymbolTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Category
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-Warn "File not found: $SourcePath"
        return
    }

    Ensure-Directory -Path $DestinationDirectory

    $destinationFile = Join-Path $DestinationDirectory (Split-Path $SourcePath -Leaf)

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $destinationFile -Force:$Force -ErrorAction Stop
        $script:Inventory += Get-FileInventoryRecord `
            -SourcePath $SourcePath `
            -DestinationFile $destinationFile `
            -Category $Category

        Write-Ok "$SourcePath"
    }
    catch {
        Write-Warn ("Copy failed: {0}`n{1}" -f $SourcePath, $_.Exception.Message)
        $script:Errors += [pscustomobject]@{
            SourcePath = $SourcePath
            Error      = $_.Exception.Message
            CapturedAt = Get-Date
        }
    }
}

function Get-RunningSqlServerBinnPaths {
    $paths = @()

    try {
        $processes = Get-CimInstance Win32_Process `
            -Filter "Name='sqlservr.exe'" `
            -ErrorAction Stop
    }
    catch {
        Write-Warn "Could not query running sqlservr.exe processes: $($_.Exception.Message)"
        return @()
    }

    foreach ($process in $processes) {
        $exePath = $process.ExecutablePath

        if ([string]::IsNullOrWhiteSpace($exePath)) {
            try {
                $exePath = (Get-Process -Id $process.ProcessId -ErrorAction Stop).Path
            }
            catch {
                Write-Warn "Could not resolve sqlservr.exe path for PID $($process.ProcessId)."
                continue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($exePath)) {
            $binn = Split-Path -Parent $exePath
            if ($paths -notcontains $binn) {
                $paths += $binn
            }
        }
    }

    return $paths
}

$serverRoot = Join-Path $DestinationPath $env:COMPUTERNAME
$windowsTarget = Join-Path $serverRoot 'Windows'
$driversTarget = Join-Path $serverRoot 'Drivers'
$sqlRoot       = Join-Path $serverRoot 'SQLServer'
$logsTarget    = Join-Path $serverRoot 'Logs'

Ensure-Directory -Path $serverRoot
Ensure-Directory -Path $windowsTarget
Ensure-Directory -Path $driversTarget
Ensure-Directory -Path $sqlRoot
Ensure-Directory -Path $logsTarget

$Inventory = @()
$Errors    = @()

Write-Host ""
Write-Host "=========================================================="
Write-Host " SQL Server / Procmon Offline Symbol Target Collector"
Write-Host "=========================================================="
Write-Host ""
Write-Info "Source server : $env:COMPUTERNAME"
Write-Info "Destination   : $serverRoot"
Write-Host ""

# Core Windows user-mode binaries that commonly appear in file I/O stacks.
$windowsFiles = @(
    'ntdll.dll',
    'kernel32.dll',
    'KernelBase.dll',
    'advapi32.dll',
    'rpcrt4.dll'
)

foreach ($file in $windowsFiles) {
    Copy-SymbolTarget `
        -SourcePath (Join-Path $env:SystemRoot "System32\$file") `
        -DestinationDirectory $windowsTarget `
        -Category 'Windows'
}

# Windows kernel.
Copy-SymbolTarget `
    -SourcePath (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe') `
    -DestinationDirectory $windowsTarget `
    -Category 'WindowsKernel'

# Core file-system and storage drivers.
$driverFiles = @(
    'ntfs.sys',
    'fltmgr.sys',
    'disk.sys',
    'volmgr.sys',
    'volsnap.sys',
    'storport.sys',
    'classpnp.sys'
)

if ($IncludeOptionalDrivers) {
    $driverFiles += @(
        'stornvme.sys',
        'spaceport.sys',
        'partmgr.sys',
        'volume.sys',
        'mountmgr.sys'
    )
}

foreach ($file in ($driverFiles | Select-Object -Unique)) {
    Copy-SymbolTarget `
        -SourcePath (Join-Path $env:SystemRoot "System32\drivers\$file") `
        -DestinationDirectory $driversTarget `
        -Category 'Driver'
}

# Detect all currently running SQL Server Engine binaries.
$sqlBinnPaths = @(Get-RunningSqlServerBinnPaths)

if ($sqlBinnPaths.Count -eq 0) {
    Write-Warn "No running sqlservr.exe instance was detected."
}
else {
    Write-Info "Detected SQL Server BINN directories:"
    foreach ($binn in $sqlBinnPaths) {
        Write-Host "       $binn"
    }

    $instanceNo = 0

    foreach ($binn in $sqlBinnPaths) {
        $instanceNo++

        $sqlTarget = Join-Path $sqlRoot ("Instance-{0}" -f $instanceNo)
        Ensure-Directory -Path $sqlTarget

        if ($IncludeAllSqlBinnFiles) {
            Write-Info "Copying all EXE/DLL files from: $binn"

            Get-ChildItem -LiteralPath $binn -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.exe', '.dll' } |
                ForEach-Object {
                    Copy-SymbolTarget `
                        -SourcePath $_.FullName `
                        -DestinationDirectory $sqlTarget `
                        -Category ("SQLServer-Instance-{0}" -f $instanceNo)
                }
        }
        else {
            $sqlFiles = @(
                'sqlservr.exe',
                'sqllang.dll',
                'sqlmin.dll',
                'sqlos.dll',
                'sqltses.dll',
                'sqlmanager.dll'
            )

            foreach ($file in $sqlFiles) {
                Copy-SymbolTarget `
                    -SourcePath (Join-Path $binn $file) `
                    -DestinationDirectory $sqlTarget `
                    -Category ("SQLServer-Instance-{0}" -f $instanceNo)
            }
        }

        [pscustomobject]@{
            InstanceNumber = $instanceNo
            BinnPath       = $binn
        } |
        Export-Csv `
            -Path (Join-Path $sqlTarget 'SqlBinnPath.csv') `
            -NoTypeInformation `
            -Encoding UTF8
    }
}

$inventoryPath = Join-Path $serverRoot 'SymbolTargets.csv'
$Inventory |
    Sort-Object Category, FileName |
    Export-Csv `
        -Path $inventoryPath `
        -NoTypeInformation `
        -Encoding UTF8

$errorPath = Join-Path $logsTarget 'CopyErrors.csv'
if ($Errors.Count -gt 0) {
    $Errors |
        Export-Csv `
            -Path $errorPath `
            -NoTypeInformation `
            -Encoding UTF8
}

$summary = [pscustomobject]@{
    SourceComputer         = $env:COMPUTERNAME
    DestinationRoot        = $serverRoot
    FilesCopied            = $Inventory.Count
    Errors                 = $Errors.Count
    SqlBinnDirectories     = $sqlBinnPaths.Count
    IncludeOptionalDrivers = [bool]$IncludeOptionalDrivers
    IncludeAllSqlBinnFiles = [bool]$IncludeAllSqlBinnFiles
    CompletedAt            = Get-Date
}

$summary |
    Export-Csv `
        -Path (Join-Path $serverRoot 'CopySummary.csv') `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "=========================================================="
Write-Host " Collection completed"
Write-Host "=========================================================="
Write-Host ""
Write-Host "Copied files : $($Inventory.Count)"
Write-Host "Errors       : $($Errors.Count)"
Write-Host ""
Write-Host "Destination:"
Write-Host "    $serverRoot"
Write-Host ""
Write-Host "Inventory:"
Write-Host "    $inventoryPath"
Write-Host ""

if ($Errors.Count -gt 0) {
    Write-Host "Errors:"
    Write-Host "    $errorPath"
    Write-Host ""
}

Write-Host "Next step on the Internet-connected workstation:"
Write-Host ""
Write-Host "    .\Prepare-OfflineSymbols.ps1 -Mode DownloadSymbols -WorkingDirectory `"<path containing Targets>`""
Write-Host ""
Write-Host "This script does not stop services or change SQL Server / Windows configuration."
