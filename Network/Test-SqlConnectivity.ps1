param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\NetworkDiagnostics"
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

$server = $ServerInstance
$port = $null
if ($ServerInstance -match '^(?<server>[^,]+),(?<port>\d+)$') {
    $server = $Matches.server
    $port = [int]$Matches.port
}

$summary = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Test,[string]$Status,[string]$Details)
    $summary.Add([pscustomobject]@{ Test=$Test; Status=$Status; Details=$Details })
}

try {
    $dns = Resolve-DnsName -Name $server -ErrorAction Stop
    $dns | Export-Csv (Join-Path $OutputPath 'DNS.csv') -NoTypeInformation -Encoding UTF8
    Add-Result 'DNS' 'OK' (($dns | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress) -join ', ')
}
catch {
    $_ | Out-File (Join-Path $OutputPath 'DNS-error.txt') -Encoding utf8
    Add-Result 'DNS' 'ERROR' $_.Exception.Message
}

try {
    $ping = Test-Connection -ComputerName $server -Count 4 -ErrorAction Stop
    $ping | Export-Csv (Join-Path $OutputPath 'Ping.csv') -NoTypeInformation -Encoding UTF8
    Add-Result 'ICMP' 'OK' 'Ping completed'
}
catch {
    $_ | Out-File (Join-Path $OutputPath 'Ping-error.txt') -Encoding utf8
    Add-Result 'ICMP' 'ERROR' $_.Exception.Message
}

if ($port) {
    try {
        $tnc = Test-NetConnection -ComputerName $server -Port $port -InformationLevel Detailed
        $tnc | Format-List * | Out-File (Join-Path $OutputPath 'Test-NetConnection.txt') -Encoding utf8
        Add-Result 'TCP Port' ($(if ($tnc.TcpTestSucceeded) {'OK'} else {'FAILED'})) "${server}:$port"
    }
    catch {
        $_ | Out-File (Join-Path $OutputPath 'Test-NetConnection-error.txt') -Encoding utf8
        Add-Result 'TCP Port' 'ERROR' $_.Exception.Message
    }
}
else {
    Add-Result 'TCP Port' 'SKIPPED' 'No explicit port supplied. Use Server,Port for deterministic testing.'
}

try {
    ipconfig /all | Out-File (Join-Path $OutputPath 'ipconfig-all.txt') -Encoding utf8
    route print | Out-File (Join-Path $OutputPath 'route-print.txt') -Encoding utf8
    netstat -ano | Out-File (Join-Path $OutputPath 'netstat-ano.txt') -Encoding utf8
    Add-Result 'Local network state' 'OK' 'ipconfig, route and netstat collected'
}
catch {
    Add-Result 'Local network state' 'ERROR' $_.Exception.Message
}

try {
    klist | Out-File (Join-Path $OutputPath 'klist.txt') -Encoding utf8
    Add-Result 'Kerberos tickets' 'OK' 'klist output collected'
}
catch {
    Add-Result 'Kerberos tickets' 'ERROR' $_.Exception.Message
}

try {
    setspn -Q "MSSQLSvc/$server*" | Out-File (Join-Path $OutputPath 'SPN-query.txt') -Encoding utf8
    Add-Result 'SPN query' 'OK' "Queried MSSQLSvc/$server*"
}
catch {
    Add-Result 'SPN query' 'ERROR' $_.Exception.Message
}

$summary | Export-Csv (Join-Path $OutputPath 'Network-Summary.csv') -NoTypeInformation -Encoding UTF8
$summary | Format-Table -AutoSize
