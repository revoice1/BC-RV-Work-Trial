<#
.SYNOPSIS
    Reports which active Okta users have a managed device vs. not.

.DESCRIPTION
    Pulls active users and registered devices (Okta Verify) from the Okta API and
    classifies each user:

      Managed               - at least one desktop device Okta sees as MANAGED
                              (device management certificate delivered via Iru)
      Registered-NotManaged - Okta Verify registered on a desktop, but no managed
                              signal (cert missing, or a personal device)
      NoDevice              - no desktop device registered in Okta Verify

    Used to measure coverage before enforcing managed-device policies
    (see ../docs/okta-tenant-setup.md, "Iru + Okta device management integration").

    Built on the Okta-Functions.ps1 library (Invoke-OktaAPI handles auth, paging,
    and rate limits; this script uses Get-OktaUsers and Get-OktaDevices):
    https://github.com/revoice1/Things-and-stuff/blob/master/Function-Libraries/Okta-Functions.ps1

    Read-only. Use an API token from an account with a read-only admin role.
    [verify] Device API response shape (_embedded.users[].managementStatus with
    expand=user) against current Okta docs before relying on results.

.PARAMETER SubDomain
    Okta org subdomain, e.g. "ailense" for ailense.okta.com.

.PARAMETER Environment
    Production (okta.com) or Preview (oktapreview.com).

.PARAMETER Token
    Okta API token, as a SecureString or string. Defaults to $OktaToken (the
    library's convention); prompts securely if neither is set.

.PARAMETER FunctionLibraryPath
    Path to Okta-Functions.ps1. Defaults to the same folder as this script.

.PARAMETER Platforms
    Device platforms that count. Defaults to desktops managed by Iru.

.PARAMETER OutputPath
    Per-user CSV report. Defaults to .\okta-managed-device-report-<date>.csv

.PARAMETER DevicePath
    Optional per-device CSV for investigating gaps.

.PARAMETER Demo
    Run against built-in sample data. No Okta connection or library needed.

.EXAMPLE
    ./Get-OktaManagedDeviceReport.ps1 -Demo

.EXAMPLE
    $OktaToken = Read-Host -AsSecureString 'Okta API token'
    ./Get-OktaManagedDeviceReport.ps1 -SubDomain ailense -DevicePath .\devices.csv

.EXAMPLE
    ./Get-OktaManagedDeviceReport.ps1 -SubDomain ailense -Environment Preview
#>
#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Okta')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Okta')]
    [string] $SubDomain,

    [Parameter(ParameterSetName = 'Okta')]
    [ValidateSet('Production', 'Preview')]
    [string] $Environment = 'Production',

    [Parameter(ParameterSetName = 'Okta')]
    $Token = $OktaToken,

    [Parameter(ParameterSetName = 'Okta')]
    [string] $FunctionLibraryPath = (Join-Path $PSScriptRoot 'Okta-Functions.ps1'),

    [string[]] $Platforms = @('MACOS', 'WINDOWS'),

    [string] $OutputPath = (Join-Path (Get-Location) "okta-managed-device-report-$(Get-Date -Format yyyy-MM-dd).csv"),

    [string] $DevicePath,

    [Parameter(Mandatory, ParameterSetName = 'Demo')]
    [switch] $Demo
)

$ErrorActionPreference = 'Stop'

function Get-DemoData {
    <# Small, deliberately mixed sample: managed, personal device only, no device, multiple devices. #>
    $u = {
        param($id, $login, $first, $last, $dept)
        [pscustomobject]@{ id = $id; status = 'ACTIVE'; profile = [pscustomobject]@{
                login = $login; email = $login; firstName = $first; lastName = $last; department = $dept } }
    }
    $users = @(
        & $u '00u1' 'avery.chen@ailense.com'   'Avery'  'Chen'   'Engineering'
        & $u '00u2' 'blake.diaz@ailense.com'   'Blake'  'Diaz'   'Engineering'
        & $u '00u3' 'casey.ng@ailense.com'     'Casey'  'Ng'     'Sales'
        & $u '00u4' 'devon.patel@ailense.com'  'Devon'  'Patel'  'Sales'
        & $u '00u5' 'emery.ross@ailense.com'   'Emery'  'Ross'   'Customer Success'
        & $u '00u6' 'finley.kim@ailense.com'   'Finley' 'Kim'    'IT'
    )
    $d = {
        param($id, $platform, $name, $serial, $userId, $mgmt)
        [pscustomobject]@{
            id = $id; status = 'ACTIVE'; lastUpdated = '2027-01-12T15:04:00.000Z'
            profile = [pscustomobject]@{ displayName = $name; platform = $platform; serialNumber = $serial }
            _embedded = [pscustomobject]@{ users = @([pscustomobject]@{
                        managementStatus = $mgmt
                        user = ($users | Where-Object id -eq $userId) }) }
        }
    }
    $devices = @(
        & $d 'guo1' 'MACOS'   "Avery's MacBook Pro"  'C02AAA111' '00u1' 'MANAGED'
        & $d 'guo2' 'IOS'     "Avery's iPhone"       ''          '00u1' 'NOT_MANAGED'
        & $d 'guo3' 'MACOS'   "Blake's MacBook Air"  'C02BBB222' '00u2' 'NOT_MANAGED'
        & $d 'guo4' 'WINDOWS' 'AIL-WIN-0042'         'PF0CCC33'  '00u3' 'MANAGED'
        & $d 'guo5' 'MACOS'   "Casey's home iMac"    'C02DDD444' '00u3' 'NOT_MANAGED'
        & $d 'guo6' 'ANDROID' "Devon's Pixel"        ''          '00u4' 'NOT_MANAGED'
        & $d 'guo7' 'MACOS'   "Finley's MacBook Pro" 'C02EEE555' '00u6' 'MANAGED'
    )
    return @{ Users = $users; Devices = $devices }
}

# ---- Collect --------------------------------------------------------------
if ($Demo) {
    Write-Host 'Demo mode: using built-in sample data.' -ForegroundColor Yellow
    $data = Get-DemoData
    $users = $data.Users
    $devices = $data.Devices
}
else {
    if (-not (Test-Path $FunctionLibraryPath)) {
        throw "Okta-Functions.ps1 not found at '$FunctionLibraryPath'. Download it from https://github.com/revoice1/Things-and-stuff/blob/master/Function-Libraries/Okta-Functions.ps1 or pass -FunctionLibraryPath."
    }
    . $FunctionLibraryPath

    if (-not $Token) { $Token = Read-Host -AsSecureString 'Okta API token' }
    $okta = @{ SubDomain = $SubDomain; Environment = $Environment; Token = $Token }

    Write-Host "Fetching active users from $SubDomain ($Environment) ..."
    $users = @(Get-OktaUsers @okta -Filter 'status eq "ACTIVE"' -limit 200)

    Write-Host 'Fetching devices ...'
    # expand=user (not the library default userSummary) so the user's department is included
    $devices = @(Get-OktaDevices @okta -expand 'user' -limit 200)
}

# ---- Classify -------------------------------------------------------------
# One device can be linked to more than one user; managementStatus lives on that user-device link.
$deviceRows = foreach ($device in $devices) {
    foreach ($link in @($device._embedded.users)) {
        if (-not $link.user) { continue }
        [pscustomobject]@{
            UserId           = $link.user.id
            Login            = $link.user.profile.login
            DeviceName       = $device.profile.displayName
            Platform         = $device.profile.platform
            SerialNumber     = $device.profile.serialNumber
            DeviceStatus     = $device.status
            ManagementStatus = $link.managementStatus
            CountsToward     = $Platforms -contains $device.profile.platform
            LastUpdated      = $device.lastUpdated
        }
    }
}

$byUser = @{}
foreach ($row in $deviceRows | Where-Object { $_.CountsToward -and $_.DeviceStatus -eq 'ACTIVE' }) {
    if (-not $byUser.ContainsKey($row.UserId)) { $byUser[$row.UserId] = [System.Collections.Generic.List[object]]::new() }
    $byUser[$row.UserId].Add($row)
}

$report = foreach ($user in $users) {
    $owned = if ($byUser.ContainsKey($user.id)) { $byUser[$user.id] } else { @() }
    $managed = @($owned | Where-Object ManagementStatus -eq 'MANAGED')

    $state = if ($managed.Count -gt 0) { 'Managed' }
             elseif ($owned.Count -gt 0) { 'Registered-NotManaged' }
             else { 'NoDevice' }

    [pscustomobject]@{
        Login                 = $user.profile.login
        Name                  = "$($user.profile.firstName) $($user.profile.lastName)"
        Department            = $user.profile.department
        State                 = $state
        DesktopDevices        = $owned.Count
        ManagedDesktopDevices = $managed.Count
        UnmanagedDeviceNames  = (@($owned | Where-Object ManagementStatus -ne 'MANAGED').DeviceName -join '; ')
        LastDeviceUpdate      = ($owned.LastUpdated | Sort-Object -Descending | Select-Object -First 1)
    }
}

# ---- Output ---------------------------------------------------------------
$report | Sort-Object State, Department, Login | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8
if ($DevicePath) { $deviceRows | Export-Csv -Path $DevicePath -NoTypeInformation -Encoding utf8 }

$total = @($report).Count
$counts = $report | Group-Object State -NoElement
$managedCount = ($counts | Where-Object Name -eq 'Managed').Count
$pct = if ($total) { [Math]::Round(100 * $managedCount / $total, 1) } else { 0 }

Write-Host ''
Write-Host "Managed device coverage: $managedCount of $total active users ($pct%)" -ForegroundColor Cyan
$counts | Sort-Object Name | Format-Table @{ n = 'State'; e = 'Name' }, Count -AutoSize | Out-Host

Write-Host 'By department:'
$report | Group-Object Department | ForEach-Object {
    $m = @($_.Group | Where-Object State -eq 'Managed').Count
    [pscustomobject]@{
        Department = $_.Name
        Users      = $_.Count
        Managed    = $m
        Percent    = [Math]::Round(100 * $m / $_.Count, 1)
    }
} | Sort-Object Percent | Format-Table -AutoSize | Out-Host

Write-Host "Report: $OutputPath"
if ($DevicePath) { Write-Host "Devices: $DevicePath" }
