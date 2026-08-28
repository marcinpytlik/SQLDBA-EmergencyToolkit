param(
    [Parameter(Mandatory = $true)]
    [string]$SqlNetworkName,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = 'Stop'
Import-Module FailoverClusters -ErrorAction Stop

$clusterParams = @{}
if ($ClusterName) { $clusterParams.Cluster = $ClusterName }

$networkResource = Get-ClusterResource @clusterParams |
    Where-Object { $_.ResourceType -eq 'Network Name' } |
    Where-Object {
        $_.Name -ieq $SqlNetworkName -or
        ((Get-ClusterParameter -InputObject $_ -Name Name -ErrorAction SilentlyContinue).Value -ieq $SqlNetworkName) -or
        ((Get-ClusterParameter -InputObject $_ -Name DnsName -ErrorAction SilentlyContinue).Value -ieq $SqlNetworkName)
    } |
    Select-Object -First 1

if (-not $networkResource) {
    throw "Could not find a cluster Network Name resource matching '$SqlNetworkName'."
}

$group = Get-ClusterGroup -Name $networkResource.OwnerGroup @clusterParams

[pscustomobject]@{
    SqlNetworkName = $SqlNetworkName
    ClusterGroup   = $group.Name
    GroupState     = $group.State
    ActiveNode     = [string]$group.OwnerNode
    ResourceName   = $networkResource.Name
}
