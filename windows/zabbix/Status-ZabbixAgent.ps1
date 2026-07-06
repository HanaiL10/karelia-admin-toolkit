# Karelia Admin Toolkit - Windows Zabbix Agent status

$ErrorActionPreference = 'SilentlyContinue'

function Get-InstalledZabbixProduct {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $paths) {
        Get-ItemProperty $path |
            Where-Object { $_.DisplayName -match '^Zabbix Agent' } |
            Select-Object DisplayName, DisplayVersion, InstallLocation, Publisher, UninstallString
    }
}

function Get-ServiceInfo {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $svc = Get-Service -Name $name
        if ($svc) { return $svc }
    }
    return $null
}

function Get-ZabbixConfPath {
    $candidates = @(
        'C:\Zabbix\zabbix_agent2.conf',
        'C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf',
        'C:\Program Files\Zabbix Agent\zabbix_agentd.conf'
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$product = Get-InstalledZabbixProduct | Select-Object -First 1
$svc = Get-ServiceInfo -Names @('Zabbix Agent 2','Zabbix Agent')
$conf = Get-ZabbixConfPath

Write-Host 'Karelia Admin Toolkit - Windows Zabbix Agent status'
Write-Host ''
Write-Host 'Host:'
Write-Host ('  ComputerName : {0}' -f $env:COMPUTERNAME)
Write-Host ('  OS           : {0}' -f (Get-CimInstance Win32_OperatingSystem).Caption)
Write-Host ('  Version      : {0}' -f (Get-CimInstance Win32_OperatingSystem).Version)
Write-Host ''
Write-Host 'Agent:'
Write-Host ('  Installed    : {0}' -f ($(if ($product) { 'YES' } else { 'NO' })))
Write-Host ('  Product      : {0}' -f ($(if ($product) { $product.DisplayName } else { 'not installed' })))
Write-Host ('  Version      : {0}' -f ($(if ($product) { $product.DisplayVersion } else { 'not installed' })))
Write-Host ('  Location     : {0}' -f ($(if ($product) { $product.InstallLocation } else { '' })))
Write-Host ''
Write-Host 'Service:'
Write-Host ('  Exists       : {0}' -f ($(if ($svc) { 'YES' } else { 'NO' })))
Write-Host ('  Name         : {0}' -f ($(if ($svc) { $svc.Name } else { '' })))
Write-Host ('  Status       : {0}' -f ($(if ($svc) { $svc.Status } else { '' })))
Write-Host ''
Write-Host 'Configuration:'
Write-Host ('  Config       : {0}' -f ($(if ($conf) { $conf } else { 'MISSING' })))

if ($conf) {
    $server = Select-String -Path $conf -Pattern '^Server=' | Select-Object -First 1
    $serverActive = Select-String -Path $conf -Pattern '^ServerActive=' | Select-Object -First 1
    Write-Host ('  Server       : {0}' -f ($(if ($server) { ($server.Line -replace '^Server=','') } else { '' })))
    Write-Host ('  ServerActive : {0}' -f ($(if ($serverActive) { ($serverActive.Line -replace '^ServerActive=','') } else { '' })))
}
