<#
.SYNOPSIS
    Prepares an offline Microsoft symbol cache for SQL Server / Procmon analysis.

.DESCRIPTION
    Standard workstation layout:

        C:\SQLSymbols\Targets\<SERVER>\...
        C:\SQLSymbols\Symbols\...
        C:\SQLSymbols\Logs\...

    Mode CollectTargets:
        Optional local collection mode. It collects selected Windows and SQL Server
        binaries into C:\SQLSymbols\Targets\<COMPUTERNAME>.

    Mode DownloadSymbols:
        Run on a workstation with Internet access and Debugging Tools for Windows.
        It recursively scans all files under C:\SQLSymbols\Targets and uses symchk.exe
        with Microsoft Symbol Server. Matching PDB files are cached in
        C:\SQLSymbols\Symbols.

.NOTES
    Designed for Windows PowerShell 5.1 and PowerShell 7+.
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

foreach ($dir in @($WorkingDirectory,$TargetsDirectory,$SymbolsDirectory,$LogsDirectory)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Copy-SymbolTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            if (-not (Test-Path -LiteralPath $Destination)) {
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            }
            Copy-Item -LiteralPath $Path -Destination $Destination -Force
            Write-Host "[OK] $Path"
        }
        catch {
            Write-Warning "Could not copy: $Path"
            Write-Warning $_.Exception.Message
        }
    }
    else {
        Write-Warning "File not found: $Path"
    }
}

function Find-SymChk {
    $Candidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe',
        'C:\Program Files\Windows Kits\10\Debuggers\x64\symchk.exe'
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) { return $Candidate }
    }

    return $null
}

if ($Mode -eq 'CollectTargets') {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host " SQL Server Offline Symbol Target Collector"
    Write-Host "=============================================="
    Write-Host ""

    $ServerTarget  = Join-Path $TargetsDirectory $env:COMPUTERNAME
    $WindowsTarget = Join-Path $ServerTarget 'Windows'
    $DriversTarget = Join-Path $ServerTarget 'Drivers'
    $SqlTarget     = Join-Path $ServerTarget 'SQLServer\Instance-1'

    $WindowsFiles = @('ntdll.dll','kernel32.dll','KernelBase.dll','advapi32.dll','rpcrt4.dll')
    foreach ($File in $WindowsFiles) {
        Copy-SymbolTarget -Path (Join-Path $env:SystemRoot "System32\$File") -Destination $WindowsTarget
    }

    Copy-SymbolTarget -Path (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe') -Destination $WindowsTarget

    $DriverFiles = @(
        'ntfs.sys','fltmgr.sys','disk.sys','volmgr.sys','volsnap.sys',
        'storport.sys','stornvme.sys','spaceport.sys','classpnp.sys',
        'partmgr.sys','volume.sys','mountmgr.sys'
    )

    foreach ($File in $DriverFiles) {
        Copy-SymbolTarget -Path (Join-Path $env:SystemRoot "System32\drivers\$File") -Destination $DriversTarget
    }

    if (-not [string]::IsNullOrWhiteSpace($SqlBinnPath)) {
        if (Test-Path -LiteralPath $SqlBinnPath) {
            $SqlFiles = @('sqlservr.exe','sqllang.dll','sqlmin.dll','sqlos.dll','sqltses.dll','sqlmanager.dll')
            foreach ($File in $SqlFiles) {
                Copy-SymbolTarget -Path (Join-Path $SqlBinnPath $File) -Destination $SqlTarget
            }
        }
        else {
            Write-Warning "SQL Server BINN directory not found: $SqlBinnPath"
        }
    }
    else {
        Write-Warning 'SqlBinnPath was not specified. SQL Server binaries were not collected.'
    }

    $Inventory = Get-ChildItem -LiteralPath $ServerTarget -Recurse -File |
        Select-Object Name, DirectoryName, Length,
            @{Name='FileVersion';Expression={$_.VersionInfo.FileVersion}},
            @{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}

    $Inventory | Export-Csv -Path (Join-Path $ServerTarget 'SymbolTargets.csv') -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host "Collected into: $ServerTarget"
    Write-Host ""
    Write-Host 'Next step on the Internet-connected workstation:'
    Write-Host '    .\PowerShell\Prepare-OfflineSymbols.ps1 -Mode DownloadSymbols -WorkingDirectory "C:\SQLSymbols"'
    Write-Host ""
    return
}

if ($Mode -eq 'DownloadSymbols') {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host " Microsoft Symbol Cache Downloader"
    Write-Host "=============================================="
    Write-Host ""

    $targetFiles = @(Get-ChildItem -LiteralPath $TargetsDirectory -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension -in '.exe','.dll','.sys' })

    if ($targetFiles.Count -eq 0) {
        throw "No EXE/DLL/SYS target files found under: $TargetsDirectory"
    }

    if ([string]::IsNullOrWhiteSpace($SymChkPath)) {
        $SymChkPath = Find-SymChk
    }

    if ([string]::IsNullOrWhiteSpace($SymChkPath)) {
        throw @"
symchk.exe was not found.

Install Debugging Tools for Windows or specify:
-SymChkPath "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\symchk.exe"
"@
    }

    if (-not (Test-Path -LiteralPath $SymChkPath)) {
        throw "symchk.exe not found: $SymChkPath"
    }

    $SymbolPath = "srv*$SymbolsDirectory*https://msdl.microsoft.com/download/symbols"
    $timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $LogFile    = Join-Path $LogsDirectory "SymChk-$timestamp.log"
    $ResultCsv  = Join-Path $LogsDirectory "SymChk-$timestamp.csv"

    Write-Host "symchk:      $SymChkPath"
    Write-Host "Targets:     $TargetsDirectory"
    Write-Host "Files:       $($targetFiles.Count)"
    Write-Host "Symbol cache:$SymbolsDirectory"
    Write-Host ""

    $results = @()

    foreach ($file in $targetFiles) {
        Write-Host "[CHECK] $($file.FullName)"
        $output = & $SymChkPath $file.FullName /s $SymbolPath /v 2>&1
        $exitCode = $LASTEXITCODE

        $output | Out-File -FilePath $LogFile -Append -Encoding utf8

        $results += [pscustomobject]@{
            File       = $file.Name
            TargetPath = $file.FullName
            ExitCode   = $exitCode
            Status     = if ($exitCode -eq 0) { 'OK' } else { 'CheckLog' }
        }
    }

    $results | Export-Csv -Path $ResultCsv -NoTypeInformation -Encoding UTF8

    $failed = @($results | Where-Object ExitCode -ne 0)

    Write-Host ""
    Write-Host "=============================================="
    Write-Host " Symbol download completed"
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "Target files : $($results.Count)"
    Write-Host "Non-zero     : $($failed.Count)"
    Write-Host "Symbol cache : $SymbolsDirectory"
    Write-Host "Log          : $LogFile"
    Write-Host "Results CSV  : $ResultCsv"
    Write-Host ""
    Write-Host 'Copy only the Symbols directory back to the offline SQL Server, for example:'
    Write-Host '    D:\DBATools\Symbols'
    Write-Host ""
}
