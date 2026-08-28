param(
    [Parameter(Mandatory = $false)]
    [int]$Top = 25,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\OSSnapshot"
)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Get-Process |
    Sort-Object CPU -Descending |
    Select-Object -First $Top Id, ProcessName,
        @{n='CPUSeconds';e={[math]::Round($_.CPU,2)}},
        @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,2)}},
        @{n='PrivateMemoryMB';e={[math]::Round($_.PrivateMemorySize64/1MB,2)}},
        Handles |
    Export-Csv (Join-Path $OutputPath 'TopProcessesByCPU.csv') -NoTypeInformation -Encoding UTF8

Get-Process |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First $Top Id, ProcessName,
        @{n='CPUSeconds';e={[math]::Round($_.CPU,2)}},
        @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB,2)}},
        @{n='PrivateMemoryMB';e={[math]::Round($_.PrivateMemorySize64/1MB,2)}},
        Handles |
    Export-Csv (Join-Path $OutputPath 'TopProcessesByMemory.csv') -NoTypeInformation -Encoding UTF8
