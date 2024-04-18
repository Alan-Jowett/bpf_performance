# Copyright (c) Microsoft Corporation
# SPDX-License-Identifier: MIT

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release",

    [Parameter(Mandatory = $false)]
    [ValidateSet("x64")]
    [string]$Arch = "x64",

    [Parameter(Mandatory = $false)]
    [string]$PeerName = "netperf-peer",

    [Parameter(Mandatory = $false)]
    [string]$RemotePSConfiguration = "PowerShell.7",

    [Parameter(Mandatory = $false)]
    [string]$RemoteDir = "C:\_work",

    [Parameter(Mandatory = $false)]
    [string]$Duration = "60000"

)

# Function to test with N clients
function Test-CtsTraffic {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Clients
    )

    $options = "-target:$RemoteAddress -protocol:udp -bitspersecond:10000000 -framerate:60 -StreamLength:60 -bufferdepth:1 -consoleverbosity:1 -iterations:1 -statusfilename:client_%.csv -connectionfilename:client_conn_%.csv -jitterfilename:jitter_%.csv "
    $jobs = @()
    for ($i = 1; $i -le $Clients; $i++) {
        $client_args = $options.Replace("%", $i)

        $jobs = Start-Process -FilePath ".\ctstraffic.exe" -ArgumentList $client_args -PassThru -WindowStyle Hidden
    }

    $jobs | ForEach-Object {
        Wait-Process -InputObject $_
    }

    # Gather drop rate
    for ($i = 1; $i -le $clients; $i++) {
        Get-Content -Path "client_$i.csv" | ConvertFrom-Csv | ForEach-Object { $drops += $_.Dropped; $completed += $_.Completed }
    }

    $percent_packet_loss = [Math]::Round(($drops * 100) / $completed)
    return $percent_packet_loss
}

$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# Set up the connection to the peer over remote powershell.
Write-Output "Connecting to $PeerName..."
$Username = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultUserName
$Password = (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon').DefaultPassword | ConvertTo-SecureString -AsPlainText -Force
$Creds = New-Object System.Management.Automation.PSCredential ($Username, $Password)
$Session = New-PSSession -ComputerName $PeerName -Credential $Creds -ConfigurationName $RemotePSConfiguration
if ($null -eq $Session) {
    Write-Error "Failed to create remote session"
}

# Find all the local and remote IP and MAC addresses.
$RemoteAddress = [System.Net.Dns]::GetHostAddresses($Session.ComputerName)[0].IPAddressToString
Write-Output "Successfully connected to peer: $RemoteAddress"

Write-Output "Copying the tests to the remote machine"
Copy-Item -ToSession $Session . -Destination $RemoteDir\cts-traffic -Recurse -Force

$Job = Invoke-Command -Session $Session -ScriptBlock {
    param($RemoteDir, $Duration)
    $CtsTraffic = "$RemoteDir\cts-traffic\ctsTraffic.exe"
    &$CtsTraffic -listen:* -protocol:udp -bitspersecond:10000000 -framerate:60 -streamlength:60 -consoleverbosity:1 -bufferdepth:1
} -ArgumentList $RemoteDir, $Duration -AsJob


$MaximumClients = 100
$packet_rate = 0

# Use a binary search to find the largest number of clients that can be sustained before packet loss exceeds 1%
# using Test-CtsTraffic to test with N clients
$low = 1
$high = $MaximumClients

while ($low -lt $high) {
    $mid = [Math]::Ceiling(($low + $high) / 2)
    if ($mid -le 0) {
        Write-Error "Error: mid is less than 0"
        break
    }
    Write-Output "Testing with $mid clients..."
    $percent_packet_loss = Test-CtsTraffic -Clients $mid

    Write-Output "Testing with $mid clients resulted in $percent_packet_loss% packet loss"

    if ($percent_packet_loss -gt 1) {
        $high = $mid - 1
    } else {
        $low = $mid
    }
}

Write-Output "Maximum clients: $low"

# Stop ctstraffic on remote machine
Invoke-Command -Session $Session -ScriptBlock {
    Stop-Process -Name ctsTraffic
}

exit 0