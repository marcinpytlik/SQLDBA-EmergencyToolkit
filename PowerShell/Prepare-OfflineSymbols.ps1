<#
.SYNOPSIS
    Prepares an offline Microsoft symbol cache for SQL Server / Procmon analysis.

.DESCRIPTION
    Mode CollectTargets:
        Run on the SQL Server that has no Internet access.
        Copies selected Windows and SQL Server binaries to a transport directory.

    Mode DownloadSymbols:
        Run on a workstation with Internet access and Debugging Tools for Windows.
        Uses symchk.exe and Microsoft Symbol Server to download matching symbols.

.NOTES
    Designed for PowerShell 5.1 and PowerShell 7.
    Does not modify SQL Server or Windows configuration.
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateSet('CollectTargets','DownloadSymbols')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = 'C:\SQLSymbols',

    [Parameter(Mandatory = $false)]
    [string]$SqlBinnPath,

    [Parameter(Mandatory = $false)]
    [string]$SymChkPath
)

$ErrorActionPreference = 'Stop'

$TargetsDirectory = Join-Path $WorkingDirectory 'Targets'
$SymbolsDirectory = Join-Path $WorkingDirectory 'Symbols'
$LogsDirectory    = Join-Path $WorkingDirectory 'Logs'

New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $TargetsDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $LogsDirectory -Force | Out-Null

function Copy-SymbolTarget
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (Test-Path $Path)
    {
        try
        {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            Copy-Item -Path $Path -Destination $Destination -Force
            Write-Host "[OK] $Path"
        }
        catch
        {
            Write-Warning "Could not copy: $Path"
            Write-Warning $_.Exception.Message
        }
    }
    else
    {
        Write-Warning "File not found: $Path"
    }
}

function Find-SymChk
{
    $Candidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe',
        'C:\Program Files\Windows Kits\10\Debuggers\x64\symchk.exe'
    )

    foreach ($Candidate in $Candidates)
    {
        if (Test-Path $Candidate)
        {
            return $Candidate
        }
    }

    return $null
}

if ($Mode -eq 'CollectTargets')
{
    Write-Host ""
    Write-Host "=============================================="
    Write-Host " SQL Server Offline Symbol Target Collector"
    Write-Host "=============================================="
    Write-Host ""

    $WindowsTarget = Join-Path $TargetsDirectory 'Windows'
    $DriversTarget = Join-Path $TargetsDirectory 'Drivers'
    $SqlTarget     = Join-Path $TargetsDirectory 'SQLServer'

    $WindowsFiles = @(
        'ntdll.dll',
        'kernel32.dll',
        'KernelBase.dll',
        'advapi32.dll',
        'rpcrt4.dll'
    )

    foreach ($File in $WindowsFiles)
    {
        Copy-SymbolTarget -Path (Join-Path $env:SystemRoot "System32\$File") -Destination $WindowsTarget
    }

    Copy-SymbolTarget -Path (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe') -Destination $WindowsTarget

    $DriverFiles = @(
        'ntfs.sys',
        'fltmgr.sys',
        'disk.sys',
        'volmgr.sys',
        'volsnap.sys',
        'storport.sys',
        'stornvme.sys',
        'spaceport.sys',
        'classpnp.sys'
    )

    foreach ($File in $DriverFiles)
    {
        Copy-SymbolTarget -Path (Join-Path $env:SystemRoot "System32\drivers\$File") -Destination $DriversTarget
    }

    if (-not [string]::IsNullOrWhiteSpace($SqlBinnPath))
    {
        if (Test-Path $SqlBinnPath)
        {
            Write-Host ""
            Write-Host "Collecting SQL Server binaries from:"
            Write-Host $SqlBinnPath
            Write-Host ""

            $SqlFiles = @(
                'sqlservr.exe',
                'sqllang.dll',
                'sqlmin.dll',
                'sqlos.dll',
                'sqltses.dll',
                'sqlmanager.dll'
            )

            foreach ($File in $SqlFiles)
            {
                Copy-SymbolTarget -Path (Join-Path $SqlBinnPath $File) -Destination $SqlTarget
            }
        }
        else
        {
            Write-Warning "SQL Server BINN directory not found: $SqlBinnPath"
        }
    }
    else
    {
        Write-Warning ""
        Write-Warning "SqlBinnPath was not specified."
        Write-Warning "Windows binaries will be collected, but SQL Server binaries will not."
    }

    $Inventory = Get-ChildItem -Path $TargetsDirectory -Recurse -File |
        Select-Object Name, DirectoryName, Length,
            @{Name='FileVersion';Expression={$_.VersionInfo.FileVersion}},
            @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}

    $Inventory | Export-Csv -Path (Join-Path $WorkingDirectory 'SymbolTargets.csv') -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "=============================================="
    Write-Host " Collection completed"
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "Copy this directory to a computer with Internet:"
    Write-Host ""
    Write-Host "    $WorkingDirectory"
    Write-Host ""
    Write-Host "Then run:"
    Write-Host ""
    Write-Host ".\Prepare-OfflineSymbols.ps1 -Mode DownloadSymbols -WorkingDirectory `"$WorkingDirectory`""
    Write-Host ""

    return
}

if ($Mode -eq 'DownloadSymbols')
{
    Write-Host ""
    Write-Host "=============================================="
    Write-Host " Microsoft Symbol Cache Downloader"
    Write-Host "=============================================="
    Write-Host ""

    if (-not (Test-Path $TargetsDirectory))
    {
        throw "Targets directory not found: $TargetsDirectory"
    }

    if ([string]::IsNullOrWhiteSpace($SymChkPath))
    {
        $SymChkPath = Find-SymChk
    }

    if ([string]::IsNullOrWhiteSpace($SymChkPath))
    {
        throw @"
symchk.exe was not found.

Install Debugging Tools for Windows or specify:

-SymChkPath "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe"
"@
    }

    if (-not (Test-Path $SymChkPath))
    {
        throw "symchk.exe not found: $SymChkPath"
    }

    New-Item -ItemType Directory -Path $SymbolsDirectory -Force | Out-Null

    $SymbolPath = "srv*$SymbolsDirectory*https://msdl.microsoft.com/download/symbols"
    $LogFile = Join-Path $LogsDirectory ('SymChk-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Host "symchk:"
    Write-Host "    $SymChkPath"
    Write-Host ""
    Write-Host "Targets:"
    Write-Host "    $TargetsDirectory"
    Write-Host ""
    Write-Host "Symbol cache:"
    Write-Host "    $SymbolsDirectory"
    Write-Host ""

    & $SymChkPath $TargetsDirectory /r /s $SymbolPath /v *>&1 |
        Tee-Object -FilePath $LogFile

    $ExitCode = $LASTEXITCODE

    Write-Host ""
    Write-Host "=============================================="
    Write-Host " Symbol download completed"
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "symchk exit code:"
    Write-Host "    $ExitCode"
    Write-Host ""
    Write-Host "Offline symbol cache:"
    Write-Host ""
    Write-Host "    $SymbolsDirectory"
    Write-Host ""
    Write-Host "Log:"
    Write-Host ""
    Write-Host "    $LogFile"
    Write-Host ""
    Write-Host "Copy the Symbols directory back to the SQL Server."
    Write-Host ""
    Write-Host "Example Procmon symbol path:"
    Write-Host ""
    Write-Host "    D:\Tools\Symbols"
    Write-Host ""
}
