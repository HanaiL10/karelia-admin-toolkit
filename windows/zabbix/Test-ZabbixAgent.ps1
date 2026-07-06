# Karelia Admin Toolkit - Windows Zabbix Agent test

$ErrorActionPreference = 'Continue'

$agent2 = @(
    'C:\Zabbix\zabbix_agent2.exe',
    'C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$agent1 = @(
    'C:\Zabbix\zabbix_agentd.exe',
    'C:\Program Files\Zabbix Agent\zabbix_agentd.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$agent = if ($agent2) { $agent2 } else { $agent1 }

if (-not $agent) {
    Write-Error 'Zabbix agent executable not found'
    exit 1
}

Write-Host "Agent executable: $agent"

$keys = @(
    'agent.version',
    'system.hostname',
    'system.uptime'
)

$failed = 0
foreach ($key in $keys) {
    Write-Host "Testing $key"
    & $agent -t $key
    if ($LASTEXITCODE -ne 0) { $failed++ }
}

$svc = Get-Service -Name 'Zabbix Agent 2','Zabbix Agent' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) {
    Write-Error 'Zabbix service not found'
    exit 1
}

if ($svc.Status -ne 'Running') {
    Write-Error "Zabbix service is not running: $($svc.Status)"
    exit 1
}

if ($failed -gt 0) {
    Write-Error "Failed checks: $failed"
    exit 1
}

Write-Host 'All checks passed'
