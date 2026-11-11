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

    Read-only. Use a token from an account or service app with a read-only admin
    role. [verify] Device API response shape (_embedded.users[].managementStatus)
    against current Okta docs before relying on results.

.PARAMETER OktaDomain
    Okta org domain, e.g. ailense.okta.com (or the custom domain).

.PARAMETER ApiToken
    Okta API token (SSWS). Read from $env:OKTA_API_TOKEN if not supplied.

.PARAMETER AccessToken
    OAuth 2.0 bearer token from an Okta service app (preferred over an API token).
    Needs okta.users.read and okta.devices.read scopes.

.PARAMETER Platforms
    Device platforms that count. Defaults to desktops managed by Iru.

.PARAMETER OutputPath
    Per-user CSV report. Defaults to .\okta-managed-device-report-<date>.csv

.PARAMETER DevicePath
    Optional per-device CSV for investigating gaps.

.PARAMETER Demo
    Run against built-in sample data. No Okta connection needed.

.EXAMPLE
    ./Get-OktaManagedDeviceReport.ps1 -Demo

.EXAMPLE
    $env:OKTA_API_TOKEN = '<token>'
    ./Get-OktaManagedDeviceReport.ps1 -OktaDomain ailense.okta.com -DevicePath .\devices.csv
#>
#Requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'ApiToken')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ApiToken')]
    [Parameter(Mandatory, ParameterSetName = 'AccessToken')]
    [string] $OktaDomain,

    [Parameter(ParameterSetName = 'ApiToken')]
    [string] $ApiToken = $env:OKTA_API_TOKEN,

    [Parameter(Mandatory, ParameterSetName = 'AccessToken')]
    [string] $AccessToken,

    [string[]] $Platforms = @('MACOS', 'WINDOWS'),

    [string] $OutputPath = (Join-Path (Get-Location) "okta-managed-device-report-$(Get-Date -Format yyyy-MM-dd).csv"),

    [string] $DevicePath,

    [Parameter(Mandatory, ParameterSetName = 'Demo')]
    [switch] $Demo
)

$ErrorActionPreference = 'Stop'

function Invoke-OktaPagedGet {
    <# GETs every page of an Okta collection, following Link rel="next" and backing off on 429. #>
    param([string] $Uri, [hashtable] $Headers)

    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        try {
            $response = Invoke-WebRequest -Uri $next -Headers $Headers -Method Get
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -eq 429) {
                $reset = [int64]($_.Exception.Response.Headers.GetValues('X-Rate-Limit-Reset') | Select-Object -First 1)
                $wait = [Math]::Max(1, $reset - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1)
                Write-Warning "Rate limited by Okta. Waiting $wait s."
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }

        $page = $response.Content | ConvertFrom-Json -Depth 20
        foreach ($item in $page) { $results.Add($item) }

        $next = $null
        foreach ($link in @($response.Headers['Link'])) {
            if ($link -match '<([^>]+)>;\s*rel="next"') { $next = $Matches[1] }
        }
    }
    return $results
}

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
    if ($PSCmdlet.ParameterSetName -eq 'ApiToken' -and -not $ApiToken) {
        throw 'No Okta credential. Pass -ApiToken, set $env:OKTA_API_TOKEN, or use -AccessToken.'
    }
    $auth = if ($AccessToken) { "Bearer $AccessToken" } else { "SSWS $ApiToken" }
    $headers = @{ Authorization = $auth; Accept = 'application/json' }
    $base = "https://$($OktaDomain.TrimEnd('/') -replace '^https?://', '')"

    Write-Host "Fetching active users from $base ..."
    $filter = [uri]::EscapeDataString('status eq "ACTIVE"')
    $users = Invoke-OktaPagedGet -Uri "$base/api/v1/users?filter=$filter&limit=200" -Headers $headers

    Write-Host 'Fetching devices ...'
    $devices = Invoke-OktaPagedGet -Uri "$base/api/v1/devices?expand=user&limit=200" -Headers $headers
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
