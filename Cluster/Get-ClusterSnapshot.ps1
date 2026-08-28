param(
    [Parameter(Mandatory = $false)]
    [string]$ClusterName,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\ClusterSnapshot"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

function Write-CollectorError {
    param([string]$Name,[object]$ErrorRecord)
    $ErrorRecord | Out-String | Out-File (Join-Path $OutputPath "$Name-error.txt") -Encoding utf8
}

try {
    Import-Module FailoverClusters -ErrorAction Stop
}
catch {
    Write-CollectorError 'FailoverClustersModule' $_
    return
}

$clusterParams = @{}
if ($ClusterName) { $clusterParams.Cluster = $ClusterName }

try {
    Get-Cluster @clusterParams |
        Select-Object Name, Domain, QuarantineDuration, QuarantineThreshold, DynamicQuorum, WitnessDynamicWeight |
        Export-Csv (Join-Path $OutputPath 'Cluster.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'Cluster' $_ }

try {
    Get-ClusterNode @clusterParams |
        Select-Object Name, State, NodeWeight, DynamicWeight, DrainStatus |
        Export-Csv (Join-Path $OutputPath 'Nodes.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'Nodes' $_ }

try {
    Get-ClusterGroup @clusterParams |
        Select-Object Name, State, OwnerNode, IsCoreGroup, Priority |
        Export-Csv (Join-Path $OutputPath 'Groups.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'Groups' $_ }

try {
    Get-ClusterResource @clusterParams |
        Select-Object Name, ResourceType, State, OwnerGroup, OwnerNode |
        Export-Csv (Join-Path $OutputPath 'Resources.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'Resources' $_ }

try {
    $networkNames = Get-ClusterResource @clusterParams |
        Where-Object { $_.ResourceType -eq 'Network Name' }

    $result = foreach ($r in $networkNames) {
        $params = @{}
        foreach ($p in (Get-ClusterParameter -InputObject $r -ErrorAction SilentlyContinue)) {
            $params[$p.Name] = $p.Value
        }
        [pscustomobject]@{
            ResourceName = $r.Name
            State        = $r.State
            OwnerGroup   = $r.OwnerGroup
            OwnerNode    = $r.OwnerNode
            Name         = $params['Name']
            DnsName      = $params['DnsName']
        }
    }
    $result | Export-Csv (Join-Path $OutputPath 'NetworkNames.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'NetworkNames' $_ }

try {
    $ipResources = Get-ClusterResource @clusterParams |
        Where-Object { $_.ResourceType -in @('IP Address','IPv6 Address') }

    $result = foreach ($r in $ipResources) {
        $params = @{}
        foreach ($p in (Get-ClusterParameter -InputObject $r -ErrorAction SilentlyContinue)) {
            $params[$p.Name] = $p.Value
        }
        [pscustomobject]@{
            ResourceName = $r.Name
            State        = $r.State
            OwnerGroup   = $r.OwnerGroup
            OwnerNode    = $r.OwnerNode
            Address      = $params['Address']
            Network      = $params['Network']
            SubnetMask   = $params['SubnetMask']
            EnableDhcp   = $params['EnableDhcp']
        }
    }
    $result | Export-Csv (Join-Path $OutputPath 'IPAddresses.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'IPAddresses' $_ }

try {
    Get-ClusterQuorum @clusterParams |
        Select-Object QuorumResource, QuorumType |
        Export-Csv (Join-Path $OutputPath 'Quorum.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'Quorum' $_ }

try {
    $sqlResources = Get-ClusterResource @clusterParams |
        Where-Object { $_.ResourceType -match 'SQL Server|SQL Server Agent' }

    $sqlResources |
        Select-Object Name, ResourceType, State, OwnerGroup, OwnerNode |
        Export-Csv (Join-Path $OutputPath 'SqlClusterResources.csv') -NoTypeInformation -Encoding UTF8

    $sqlGroups = $sqlResources |
        Where-Object { $_.ResourceType -eq 'SQL Server' } |
        Select-Object -ExpandProperty OwnerGroup -Unique

    $map = foreach ($groupName in $sqlGroups) {
        $group = Get-ClusterGroup -Name $groupName @clusterParams
        $resources = Get-ClusterResource @clusterParams | Where-Object OwnerGroup -eq $group.Name
        $networkName = $resources | Where-Object ResourceType -eq 'Network Name' | Select-Object -First 1
        [pscustomobject]@{
            SqlGroupName = $group.Name
            GroupState   = $group.State
            ActiveNode   = $group.OwnerNode
            NetworkName  = if ($networkName) { $networkName.Name } else { $null }
        }
    }
    $map | Export-Csv (Join-Path $OutputPath 'SqlFciMap.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-CollectorError 'SqlFciMap' $_ }

Write-Host "Cluster snapshot written to: $OutputPath"
