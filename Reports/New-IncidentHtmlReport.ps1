param([Parameter(Mandatory=$true)][string]$IncidentPath)

function Import-CsvSafe([string]$Path) {
    if (Test-Path $Path) {
        try { return @(Import-Csv $Path) } catch { return @() }
    }
    return @()
}

function HtmlEncode([string]$Text) {
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

$findings = Import-CsvSafe (Join-Path $IncidentPath 'Incident-Findings.csv')
if (-not $findings.Count) {
    throw "Incident-Findings.csv not found or empty. Run New-IncidentSummary.ps1 first."
}

$meta = Import-CsvSafe (Join-Path $IncidentPath 'incident-metadata.csv')
$server = if ($meta.Count) { $meta[0].ServerInstance } else { 'Unknown' }
$computer = if ($meta.Count) { $meta[0].ComputerName } else { 'Unknown' }
$collectedAt = if ($meta.Count) { $meta[0].CollectedAt } else { '' }

$critical = @($findings | Where-Object Severity -eq 'Critical')
$warning = @($findings | Where-Object Severity -eq 'Warning')
$ok = @($findings | Where-Object Severity -eq 'OK')

$score = 100 - ($critical.Count * 20) - ($warning.Count * 7)
if ($score -lt 0) { $score = 0 }
if ($score -gt 100) { $score = 100 }

$status = if ($score -ge 90) { 'Healthy' } elseif ($score -ge 70) { 'Degraded' } elseif ($score -ge 50) { 'Warning' } else { 'Critical' }

$areas = @('Blocking','StorageIO','FreeSpace','Cluster','Collector')
$areaRows = foreach ($area in $areas) {
    $items = @($findings | Where-Object Area -eq $area)
    if (-not $items.Count) { continue }
    $worst = if ($items.Severity -contains 'Critical') { 'Critical' } elseif ($items.Severity -contains 'Warning') { 'Warning' } else { 'OK' }
    [pscustomobject]@{Area=$area;Status=$worst;Count=$items.Count}
}

function New-FindingRows($items) {
    if (-not $items.Count) { return '<tr><td colspan="3">None</td></tr>' }
    return (($items | ForEach-Object {
        '<tr><td>' + (HtmlEncode $_.Area) + '</td><td>' + (HtmlEncode $_.Message) + '</td><td><code>' + (HtmlEncode $_.Evidence) + '</code></td></tr>'
    }) -join "`n")
}

$areaHtml = (($areaRows | ForEach-Object {
    '<tr><td>' + (HtmlEncode $_.Area) + '</td><td>' + (HtmlEncode $_.Status) + '</td><td>' + $_.Count + '</td></tr>'
}) -join "`n")

$executive = if ($critical.Count -gt 0) {
    "Detected $($critical.Count) critical and $($warning.Count) warning finding(s). Immediate DBA review is recommended."
} elseif ($warning.Count -gt 0) {
    "No critical findings were detected, but $($warning.Count) warning finding(s) require review."
} else {
    "No critical or warning findings were detected by the automated triage rules."
}

$html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>SQLDBA Incident Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:32px;background:#f6f7f9;color:#1f2937}
.card{background:#fff;border:1px solid #d1d5db;border-radius:10px;padding:18px;margin-bottom:18px}
h1,h2{margin-top:0}.score{font-size:46px;font-weight:700}.muted{color:#6b7280}
table{width:100%;border-collapse:collapse}th,td{border-bottom:1px solid #e5e7eb;padding:9px;text-align:left;vertical-align:top}
.badge{display:inline-block;padding:4px 9px;border-radius:999px;background:#e5e7eb;font-weight:600}
code{white-space:pre-wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}
</style>
</head>
<body>
<div class="card">
<h1>SQLDBA Incident Report</h1>
<div class="grid">
<div><div class="muted">Health Score</div><div class="score">$score/100</div><span class="badge">$status</span></div>
<div><div class="muted">SQL Server</div><strong>$(HtmlEncode $server)</strong></div>
<div><div class="muted">Windows Host</div><strong>$(HtmlEncode $computer)</strong></div>
<div><div class="muted">Collected</div><strong>$(HtmlEncode $collectedAt)</strong></div>
</div>
</div>
<div class="card"><h2>Executive Summary</h2><p>$(HtmlEncode $executive)</p><p class="muted">Automated triage is heuristic and does not replace root-cause analysis.</p></div>
<div class="card"><h2>Area Status</h2><table><thead><tr><th>Area</th><th>Status</th><th>Findings</th></tr></thead><tbody>$areaHtml</tbody></table></div>
<div class="card"><h2>Critical</h2><table><thead><tr><th>Area</th><th>Finding</th><th>Evidence</th></tr></thead><tbody>$(New-FindingRows $critical)</tbody></table></div>
<div class="card"><h2>Warnings</h2><table><thead><tr><th>Area</th><th>Finding</th><th>Evidence</th></tr></thead><tbody>$(New-FindingRows $warning)</tbody></table></div>
<div class="card"><h2>OK</h2><table><thead><tr><th>Area</th><th>Finding</th><th>Evidence</th></tr></thead><tbody>$(New-FindingRows $ok)</tbody></table></div>
<div class="card"><h2>Scoring</h2><p>Start: 100 points. Critical finding: -20. Warning finding: -7. Minimum: 0.</p></div>
</body>
</html>
"@

$out = Join-Path $IncidentPath 'Incident-Report.html'
$html | Out-File $out -Encoding utf8
[pscustomobject]@{HealthScore=$score;Status=$status;Critical=$critical.Count;Warning=$warning.Count;OK=$ok.Count} |
    Export-Csv (Join-Path $IncidentPath 'Incident-HealthScore.csv') -NoTypeInformation -Encoding UTF8
Write-Host "HTML incident report generated: $out"
