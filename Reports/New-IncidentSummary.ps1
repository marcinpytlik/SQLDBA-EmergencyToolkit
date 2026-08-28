param([Parameter(Mandatory=$true)][string]$IncidentPath)

function Import-CsvSafe([string]$Path) {
    if (Test-Path $Path) {
        try { return @(Import-Csv $Path) } catch { return @() }
    }
    return @()
}

$findings = @()
function Add-Finding([string]$Severity,[string]$Area,[string]$Message,[string]$Evidence) {
    $script:findings += [pscustomobject]@{Severity=$Severity;Area=$Area;Message=$Message;Evidence=$Evidence}
}

$meta = Import-CsvSafe (Join-Path $IncidentPath 'incident-metadata.csv')
$server = if ($meta.Count) {$meta[0].ServerInstance} else {'Unknown'}
$computer = if ($meta.Count) {$meta[0].ComputerName} else {'Unknown'}

$blocking = Import-CsvSafe (Join-Path $IncidentPath 'SQL\Blocking.csv')
if ($blocking.Count) { Add-Finding 'Critical' 'Blocking' "Detected $($blocking.Count) blocking rows." 'SQL/Blocking.csv' }
else { Add-Finding 'OK' 'Blocking' 'No blocking rows captured.' 'SQL/Blocking.csv' }

$io = Import-CsvSafe (Join-Path $IncidentPath 'SQL\StorageIO.csv')
foreach ($r in $io) {
    $read=0.0;$write=0.0
    [void][double]::TryParse([string]$r.ReadLatencyMs,[ref]$read)
    [void][double]::TryParse([string]$r.WriteLatencyMs,[ref]$write)
    $m=[math]::Max($read,$write)
    if ($m -ge 50) { Add-Finding 'Critical' 'StorageIO' ("High file latency {0:N1} ms for {1}." -f $m,$r.PhysicalName) 'SQL/StorageIO.csv' }
    elseif ($m -ge 20) { Add-Finding 'Warning' 'StorageIO' ("Elevated file latency {0:N1} ms for {1}." -f $m,$r.PhysicalName) 'SQL/StorageIO.csv' }
}
if ($io.Count -and -not ($findings | Where-Object Area -eq 'StorageIO')) { Add-Finding 'OK' 'StorageIO' 'No file latency above warning threshold.' 'SQL/StorageIO.csv' }

$volumes = Import-CsvSafe (Join-Path $IncidentPath 'Storage\Volumes.csv')
foreach ($r in $volumes) {
    $pct=0.0
    if ([double]::TryParse([string]$r.FreePercent,[ref]$pct)) {
        if ($pct -lt 10) { Add-Finding 'Critical' 'FreeSpace' ("Low free space: {0} has {1:N1}% free." -f $r.DriveLetter,$pct) 'Storage/Volumes.csv' }
        elseif ($pct -lt 20) { Add-Finding 'Warning' 'FreeSpace' ("Free space warning: {0} has {1:N1}% free." -f $r.DriveLetter,$pct) 'Storage/Volumes.csv' }
    }
}

$nodes = Import-CsvSafe (Join-Path $IncidentPath 'Cluster\Nodes.csv')
$bad=@($nodes | Where-Object {$_.State -and $_.State -ne 'Up'})
if ($bad.Count) { Add-Finding 'Critical' 'Cluster' "Detected $($bad.Count) cluster node(s) not Up." 'Cluster/Nodes.csv' }
elseif ($nodes.Count) { Add-Finding 'OK' 'Cluster' 'All captured cluster nodes are Up.' 'Cluster/Nodes.csv' }

$errors=@(Get-ChildItem $IncidentPath -Recurse -Filter '*-error.txt' -ErrorAction SilentlyContinue)
if ($errors.Count) { Add-Finding 'Warning' 'Collector' "$($errors.Count) collector error file(s) were generated." 'See *-error.txt files' }
else { Add-Finding 'OK' 'Collector' 'No collector error files found.' 'Incident package' }

$critical=@($findings | Where-Object Severity -eq 'Critical')
$warning=@($findings | Where-Object Severity -eq 'Warning')
$ok=@($findings | Where-Object Severity -eq 'OK')

$lines=@('# Incident Summary','',"- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')","- SQL Server: $server","- Windows host: $computer",'', '> Automated triage is heuristic. Treat it as a starting point, not a final root-cause determination.','')
foreach ($s in @(@{T='Critical';I=$critical},@{T='Warning';I=$warning},@{T='OK';I=$ok})) {
    $lines += "## $($s.T)",''
    if (-not $s.I.Count) {$lines += '- None'} else { foreach ($f in $s.I) {$lines += "- **$($f.Area):** $($f.Message)","  Evidence: $($f.Evidence)"} }
    $lines += ''
}
$lines += '## Counts','',"- Critical: $($critical.Count)","- Warning: $($warning.Count)","- OK: $($ok.Count)"
$lines | Out-File (Join-Path $IncidentPath 'Incident-Summary.md') -Encoding utf8
$findings | Export-Csv (Join-Path $IncidentPath 'Incident-Findings.csv') -NoTypeInformation -Encoding UTF8
Write-Host "Incident report generated: $(Join-Path $IncidentPath 'Incident-Summary.md')"
