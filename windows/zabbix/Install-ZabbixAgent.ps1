#requires -version 5.1

<#
================================================================================
 Zabbix Agent 2 deploy/update script for Windows Server 2016/2019/2022

 Назначение:
   Скрипт приводит Windows-сервер к нужному состоянию:
     - установлен Zabbix Agent 2 нужной версии;
     - установлен пакет Zabbix Agent2 Plugins нужной версии;
     - удалены старые Zabbix Agent 1 / Agent 2 неправильных версий;
     - Hostname прописан как FQDN в нижнем регистре: server.domain.local;
     - Server и ServerActive прописаны по заданным IP;
     - если всё уже правильно — ничего не переустанавливает, не переписывает
       конфиг и не перезапускает службу.

 Что менять завтра:

   CHANGE-01: версия агента и плагинов
      Сейчас:
        [string]$Version = '6.4.21'

      Для смены версии, например на 6.4.22:
        [string]$Version = '6.4.22'

      ВАЖНО:
        Версия Zabbix Agent должна соответствовать ветке Zabbix Server/Proxy.
        Если сервер Zabbix 6.4.x — ставим agent 6.4.x.
        Если сервер Zabbix 7.0.x — ставим agent 7.0.x.

   CHANGE-02: папка установки агента
      Сейчас:
        [string]$InstallFolder = 'C:\Zabbix'

      Если хочешь ставить в Program Files:
        [string]$InstallFolder = 'C:\Program Files\Zabbix Agent 2'

      ВАЖНО:
        По умолчанию ForceInstallFolder=false, поэтому если правильный Agent2
        уже стоит в другой папке, скрипт не будет его переносить.

   CHANGE-03: passive checks, параметр Server
      Сейчас:
        [string]$Server = '212.109.13.41,185.90.103.203,192.168.1.53'

      Это список Zabbix Server / Proxy, которым разрешено опрашивать агент.

   CHANGE-04: active checks, параметр ServerActive
      Сейчас:
        [string]$ServerActive = '192.168.1.53,212.109.13.41'

      Обычно первым ставим локальный proxy клиента: 192.168.1.53.
      Вторым можно оставить основной Zabbix server: 212.109.13.41.

   CHANGE-05: HostMetadata для авторегистрации
      Сейчас:
        [string]$HostMetadata = 'Windows auto'

      Если в Zabbix есть разные действия авторегистрации, можно поменять:
        Windows server
        Windows SQL
        Windows 1C

   CHANGE-06: ставить ли плагины Agent2
      Сейчас:
        [bool]$InstallPlugins = $true

      Если плагины не нужны:
        [bool]$InstallPlugins = $false

   CHANGE-07: принудительно переустановить плагины
      Сейчас:
        [bool]$ReinstallPlugins = $false

      Если плагины сломались или обновляешь версию:
        [bool]$ReinstallPlugins = $true

   CHANGE-08: принудительно переносить Agent2 в папку InstallFolder
      Сейчас:
        [bool]$ForceInstallFolder = $false

      false:
        если Agent2 нужной версии уже стоит где угодно — не переносим.

      true:
        если Agent2 стоит не в InstallFolder — удаляем и ставим заново туда.

   CHANGE-09: ничего не трогать, если всё уже правильно
      Сейчас:
        [bool]$SkipIfAlreadyCorrect = $true

      true:
        если всё совпадает — нет backup, нет rewrite, нет restart.

      false:
        даже если всё правильно — перепишет конфиг и проверит службу.

 Примеры запуска:

   Проверка без изменений:
     powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1

   Боевой запуск:
     powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1 -Install

   Запуск без плагинов:
     powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1 -Install -InstallPlugins:$false

   Принудительная переустановка плагинов:
     powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1 -Install -ReinstallPlugins:$true

   Принудительно перенести агент в C:\Zabbix:
     powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1 -Install -ForceInstallFolder:$true

 Логи:
   Основной лог:
     C:\ProgramData\Zabbix\deploy\deploy-Agent2-<version>-<date>.log

   MSI-логи:
     C:\ProgramData\Zabbix\deploy\install-Agent2-...
     C:\ProgramData\Zabbix\deploy\install-Agent2-Plugins-...
     C:\ProgramData\Zabbix\deploy\uninstall-...

 Бэкапы конфигов:
     C:\ProgramData\Zabbix\backup\

================================================================================
#>

[CmdletBinding()]
param(
    # CHANGE-03:
    # Список Zabbix Server / Proxy для passive checks.
    # Через запятую, без пробелов.
    [string]$Server = '212.109.13.41,185.90.103.203,192.168.1.53',

    # CHANGE-04:
    # Список Zabbix Server / Proxy для active checks.
    # Обычно первым ставим локальный proxy клиента.
    [string]$ServerActive = '192.168.1.53,212.109.13.41',

    # Оставлено для совместимости со старыми командами.
    # Скрипт всегда приводит систему к Agent2.
    [ValidateSet('Auto','Agent1','Agent2')]
    [string]$TargetAgent = 'Agent2',

    # CHANGE-01:
    # Версия Zabbix Agent 2 и Agent2 Plugins.
    # Для обновления версии обычно достаточно поменять только эту строку.
    [string]$Version = '6.4.21',

    # CHANGE-02:
    # Папка установки нового Agent2, если его нет или версия неправильная.
    [string]$InstallFolder = 'C:\Zabbix',

    # Если пусто — скрипт сам сделает hostname.domain.local в нижнем регистре.
    # Например: app01.barenz.group
    # Если надо задать вручную:
    #   -Hostname "app01.barenz.group"
    [string]$Hostname = '',

    # Порт агента для passive checks.
    [int]$ListenPort = 10050,

    # Timeout в конфиге агента.
    [int]$Timeout = 30,

    # CHANGE-05:
    # Метаданные для авторегистрации в Zabbix.
    [string]$HostMetadata = 'Windows auto',

    # Без этого ключа скрипт работает в режиме проверки.
    [switch]$Install,

    # Не создавать/не проверять firewall rule.
    [switch]$SkipFirewallRule,

    # CHANGE-06:
    # Устанавливать ли пакет zabbix_agent2_plugins.
    [bool]$InstallPlugins = $true,

    # CHANGE-07:
    # Принудительно переустановить plugins MSI.
    [bool]$ReinstallPlugins = $false,

    # CHANGE-08:
    # false = если Agent2 нужной версии уже стоит где угодно, не переносим.
    # true  = если Agent2 стоит не в InstallFolder, удаляем и ставим заново.
    [bool]$ForceInstallFolder = $false,

    # CHANGE-09:
    # true = если всё уже правильно, ничего не трогаем.
    # false = переписать конфиг/проверить/перезапустить даже если всё правильно.
    [bool]$SkipIfAlreadyCorrect = $true
)

$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$workDir = 'C:\ProgramData\Zabbix\deploy'
$backupDir = 'C:\ProgramData\Zabbix\backup'

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$deployLog = Join-Path $workDir ("deploy-Agent2-$Version-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

try {
    Start-Transcript -Path $deployLog -Append | Out-Null
} catch {}

function Write-Step {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message"
}

function Normalize-Version {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    if ($Value -match '(\d+\.\d+\.\d+)') {
        return $Matches[1]
    }

    return $Value
}

function Normalize-FolderPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\')
    } catch {
        return $Path.TrimEnd('\')
    }
}

function Test-SameFolder {
    param(
        [string]$Path1,
        [string]$Path2
    )

    if ([string]::IsNullOrWhiteSpace($Path1) -or [string]::IsNullOrWhiteSpace($Path2)) {
        return $false
    }

    $a = Normalize-FolderPath $Path1
    $b = Normalize-FolderPath $Path2

    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-LowerFqdnHostname {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

        $dnsHostName = $cs.DNSHostName
        $domain = $cs.Domain
        $partOfDomain = $cs.PartOfDomain

        if ([string]::IsNullOrWhiteSpace($dnsHostName)) {
            $dnsHostName = $env:COMPUTERNAME
        }

        if (
            $partOfDomain -eq $true -and
            -not [string]::IsNullOrWhiteSpace($domain) -and
            $domain -notmatch '^(WORKGROUP)$'
        ) {
            return ("$dnsHostName.$domain").ToLowerInvariant()
        }

        try {
            $dnsFqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName

            if (-not [string]::IsNullOrWhiteSpace($dnsFqdn) -and $dnsFqdn -match '\.') {
                return $dnsFqdn.ToLowerInvariant()
            }
        } catch {}

        return $dnsHostName.ToLowerInvariant()
    }
    catch {
        return $env:COMPUTERNAME.ToLowerInvariant()
    }
}

function Get-ExeFromPathName {
    param([string]$PathName)

    if ([string]::IsNullOrWhiteSpace($PathName)) {
        return $null
    }

    if ($PathName -match '^\s*"([^"]+\.exe)"') {
        return $Matches[1]
    }

    if ($PathName -match '^\s*([A-Za-z]:\\.*?\.exe)') {
        return $Matches[1]
    }

    return $null
}

function Get-ConfFromPathName {
    param([string]$PathName)

    if ([string]::IsNullOrWhiteSpace($PathName)) {
        return $null
    }

    if ($PathName -match '-c\s+"([^"]+\.conf)"') {
        return $Matches[1]
    }

    if ($PathName -match '-c\s+([^\s]+\.conf)') {
        return $Matches[1]
    }

    return $null
}

function Get-ZabbixServices {
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like 'Zabbix Agent*' -or
            $_.DisplayName -like 'Zabbix Agent*'
        } |
        Select-Object Name, DisplayName, State, StartMode, PathName
}

function Get-ZabbixServiceInfo {
    $items = foreach ($svc in Get-ZabbixServices) {
        $exe = Get-ExeFromPathName $svc.PathName
        $conf = Get-ConfFromPathName $svc.PathName
        $versionDetected = $null
        $exeFolder = $null

        if ($exe) {
            $exeFolder = Split-Path $exe -Parent
        }

        if ($exe -and (Test-Path $exe)) {
            try {
                $out = & $exe -V 2>&1 | Out-String
                if ($out -match '(\d+\.\d+\.\d+)') {
                    $versionDetected = $Matches[1]
                }
            } catch {}

            if (-not $versionDetected) {
                try {
                    $versionDetected = Normalize-Version ((Get-Item $exe).VersionInfo.ProductVersion)
                } catch {}
            }
        }

        $kind = if (
            $svc.DisplayName -match 'Agent 2' -or
            $svc.Name -match 'Agent 2' -or
            $exe -match 'agent2'
        ) {
            'Agent2'
        } else {
            'Agent1'
        }

        [pscustomobject]@{
            Kind        = $kind
            Version     = $versionDetected
            ServiceName = $svc.Name
            DisplayName = $svc.DisplayName
            State       = $svc.State
            StartMode   = $svc.StartMode
            Exe         = $exe
            ExeFolder   = $exeFolder
            Conf        = $conf
            PathName    = $svc.PathName
        }
    }

    return @($items)
}

function Get-ZabbixCandidateFolders {
    $folders = @(
        $script:InstallFolderNormalized,
        'C:\Zabbix',
        'C:\zabbix',
        'C:\zabbix_agent',
        'C:\Zabbix Agent',
        'C:\Zabbix Agent 2',
        'C:\Program Files\Zabbix Agent',
        'C:\Program Files\Zabbix Agent 2',
        'C:\Program Files (x86)\Zabbix Agent',
        'C:\Program Files (x86)\Zabbix Agent 2'
    )

    $svcInfo = @(Get-ZabbixServiceInfo)

    foreach ($svc in $svcInfo) {
        if ($svc.Exe) {
            $folders += (Split-Path $svc.Exe -Parent)
        }

        if ($svc.Conf) {
            $folders += (Split-Path $svc.Conf -Parent)
        }
    }

    $folders |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Normalize-FolderPath $_ } |
        Select-Object -Unique
}

function Get-MsiGuidFromRegistryItem {
    param([object]$Item)

    $guid = $null

    if ($Item.PSChildName -match '^\{[0-9A-Fa-f\-]+\}$') {
        $guid = $Item.PSChildName
    } elseif ($Item.UninstallString -match '\{[0-9A-Fa-f\-]+\}') {
        $guid = $Matches[0]
    }

    return $guid
}

function Get-ZabbixInstalledPrograms {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like 'Zabbix Agent*' -and
            $_.DisplayName -notlike '*Plugin*' -and
            $_.DisplayName -notlike '*plugin*'
        } |
        ForEach-Object {
            $kind = if ($_.DisplayName -like 'Zabbix Agent 2*') {
                'Agent2'
            } else {
                'Agent1'
            }

            [pscustomobject]@{
                Kind            = $kind
                DisplayName     = $_.DisplayName
                DisplayVersion  = Normalize-Version $_.DisplayVersion
                RawVersion      = $_.DisplayVersion
                Guid            = Get-MsiGuidFromRegistryItem $_
                InstallLocation = Normalize-FolderPath $_.InstallLocation
                UninstallString = $_.UninstallString
                RegistryKey     = $_.PSPath
            }
        }
}

function Get-ZabbixAgent2PluginsPackage {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object {
            (
                $_.DisplayName -like '*Zabbix Agent 2*Plugin*' -or
                $_.DisplayName -like '*Zabbix Agent2*Plugin*' -or
                $_.DisplayName -like '*zabbix_agent2_plugins*'
            )
        } |
        ForEach-Object {
            [pscustomobject]@{
                DisplayName     = $_.DisplayName
                DisplayVersion  = Normalize-Version $_.DisplayVersion
                RawVersion      = $_.DisplayVersion
                Guid            = Get-MsiGuidFromRegistryItem $_
                InstallLocation = Normalize-FolderPath $_.InstallLocation
                UninstallString = $_.UninstallString
                RegistryKey     = $_.PSPath
            }
        }
}

function Get-ActiveConfigValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $escaped = [regex]::Escape($Name)
    $lines = @(Get-Content $Path -ErrorAction SilentlyContinue)
    $value = $null

    foreach ($line in $lines) {
        if ($line -match "^\s*$escaped\s*=\s*(.*)\s*$") {
            $value = $Matches[1].Trim()
        }
    }

    return $value
}

function Test-ActiveExeFilePlaceholders {
    param(
        [string[]]$Folders
    )

    foreach ($folder in $Folders) {
        if (-not (Test-Path $folder)) {
            continue
        }

        $hits = @(
            Get-ChildItem $folder -Recurse -Filter "*.conf" -ErrorAction SilentlyContinue |
                Select-String '^\s*[^#;].*\[ExeFile\]' -ErrorAction SilentlyContinue
        )

        if ($hits.Count -gt 0) {
            return $true
        }
    }

    return $false
}

function Test-ZabbixFirewallRule {
    param(
        [string]$RuleName,
        [int]$Port
    )

    if ($SkipFirewallRule) {
        return $true
    }

    try {
        $rule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue |
            Where-Object { $_.Enabled -eq 'True' } |
            Select-Object -First 1

        if (-not $rule) {
            return $false
        }

        $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue

        if (-not $portFilter) {
            return $false
        }

        return @($portFilter | Where-Object { $_.Protocol -eq 'TCP' -and $_.LocalPort -eq "$Port" }).Count -gt 0
    } catch {
        return $false
    }
}

function Test-Agent2ConfigCorrect {
    param(
        [string]$ConfFile,
        [string]$ExpectedLogFile,
        [string]$ExpectedServer,
        [string]$ExpectedServerActive,
        [string]$ExpectedHostname,
        [int]$ExpectedListenPort,
        [int]$ExpectedTimeout,
        [string]$ExpectedHostMetadata,
        [string]$ExpectedInclude,
        [bool]$NeedPlugins
    )

    $result = [ordered]@{
        IsOk = $true
        Reason = @()
    }

    if (-not (Test-Path $ConfFile)) {
        $result.IsOk = $false
        $result.Reason += "Config file not found: $ConfFile"
        return [pscustomobject]$result
    }

    $checks = @(
        @{ Name = 'LogType';       Expected = 'file' },
        @{ Name = 'LogFile';       Expected = $ExpectedLogFile },
        @{ Name = 'Server';        Expected = $ExpectedServer },
        @{ Name = 'ListenPort';    Expected = "$ExpectedListenPort" },
        @{ Name = 'ServerActive';  Expected = $ExpectedServerActive },
        @{ Name = 'Hostname';      Expected = $ExpectedHostname },
        @{ Name = 'HostMetadata';  Expected = $ExpectedHostMetadata },
        @{ Name = 'Timeout';       Expected = "$ExpectedTimeout" }
    )

    if ($NeedPlugins) {
        $checks += @{ Name = 'Include'; Expected = $ExpectedInclude }
    }

    foreach ($check in $checks) {
        $current = Get-ActiveConfigValue -Path $ConfFile -Name $check.Name

        if ($current -ne $check.Expected) {
            $result.IsOk = $false
            $result.Reason += "$($check.Name) is '$current', expected '$($check.Expected)'"
        }
    }

    foreach ($badParam in @('EnablePersistentBuffer','PersistentBufferPeriod','PersistentBufferFile')) {
        $currentBad = Get-ActiveConfigValue -Path $ConfFile -Name $badParam

        if ($null -ne $currentBad) {
            $result.IsOk = $false
            $result.Reason += "$badParam exists and should be removed"
        }
    }

    return [pscustomobject]$result
}

function Test-DesiredAgent2AlreadyInstalled {
    param(
        [string]$DesiredVersion,
        [string]$DesiredInstallFolder,
        [bool]$RequireTargetFolder
    )

    $result = [ordered]@{
        IsOk    = $false
        Reason  = @()
        Service = $null
        Exe     = $null
        Conf    = $null
        Folder  = $null
        State   = $null
    }

    $agent2 = @(Get-ZabbixServiceInfo) |
        Where-Object { $_.Kind -eq 'Agent2' } |
        Select-Object -First 1

    if (-not $agent2) {
        $result.Reason += "Agent2 service not found"
        return [pscustomobject]$result
    }

    $result.Service = $agent2.ServiceName
    $result.Exe = $agent2.Exe
    $result.Conf = $agent2.Conf
    $result.Folder = $agent2.ExeFolder
    $result.State = $agent2.State

    if ($agent2.Version -ne $DesiredVersion) {
        $result.Reason += "Agent2 version is $($agent2.Version), expected $DesiredVersion"
        return [pscustomobject]$result
    }

    if (-not $agent2.Exe -or -not (Test-Path $agent2.Exe)) {
        $result.Reason += "Agent2 exe not found: $($agent2.Exe)"
        return [pscustomobject]$result
    }

    if ($RequireTargetFolder) {
        if (-not (Test-SameFolder $agent2.ExeFolder $DesiredInstallFolder)) {
            $result.Reason += "Agent2 folder is '$($agent2.ExeFolder)', expected '$DesiredInstallFolder'"
            return [pscustomobject]$result
        }
    }

    $agent1 = @(Get-ZabbixServiceInfo) |
        Where-Object { $_.Kind -eq 'Agent1' }

    if ($agent1) {
        $result.Reason += "Old Agent1 service still exists"
        return [pscustomobject]$result
    }

    $result.IsOk = $true
    $result.Reason += "Agent2 $DesiredVersion is already installed"
    return [pscustomobject]$result
}

function Test-PluginsCorrect {
    param(
        [string]$DesiredVersion,
        [string]$AgentFolder
    )

    $result = [ordered]@{
        IsOk = $true
        Reason = @()
    }

    if (-not $InstallPlugins) {
        $result.IsOk = $true
        $result.Reason += "InstallPlugins=false"
        return [pscustomobject]$result
    }

    if ($ReinstallPlugins) {
        $result.IsOk = $false
        $result.Reason += "ReinstallPlugins=true"
        return [pscustomobject]$result
    }

    $pluginPkg = @(Get-ZabbixAgent2PluginsPackage) |
        Where-Object { $_.DisplayVersion -eq $DesiredVersion } |
        Select-Object -First 1

    if (-not $pluginPkg) {
        $result.IsOk = $false
        $result.Reason += "Agent2 plugins package $DesiredVersion not found"
    }

    $pluginDir = Join-Path $AgentFolder 'zabbix_agent2.d\plugins.d'

    if (-not (Test-Path $pluginDir)) {
        $result.IsOk = $false
        $result.Reason += "Plugin directory not found: $pluginDir"
    }

    if (Test-Path $pluginDir) {
        $pluginConfs = @(Get-ChildItem $pluginDir -Filter "*.conf" -ErrorAction SilentlyContinue)

        if ($pluginConfs.Count -eq 0) {
            $result.IsOk = $false
            $result.Reason += "Plugin directory exists but no .conf files found: $pluginDir"
        }
    }

    return [pscustomobject]$result
}

function Backup-ZabbixFiles {
    Write-Step "Creating backup of existing Zabbix configs..."

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $paths = @(
        'C:\Program Files\Zabbix Agent\zabbix_agentd.conf',
        'C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf',
        'C:\Program Files (x86)\Zabbix Agent\zabbix_agentd.conf',
        'C:\Program Files (x86)\Zabbix Agent 2\zabbix_agent2.conf',
        'C:\Zabbix\zabbix_agentd.conf',
        'C:\Zabbix\zabbix_agent2.conf',
        'C:\zabbix\zabbix_agentd.conf',
        'C:\zabbix\zabbix_agent2.conf',
        'C:\zabbix_agent\zabbix_agentd.conf',
        'C:\zabbix_agent\zabbix_agent2.conf'
    )

    foreach ($svc in @(Get-ZabbixServiceInfo)) {
        if ($svc.Conf) {
            $paths += $svc.Conf
        }
    }

    foreach ($p in ($paths | Select-Object -Unique)) {
        if (Test-Path $p) {
            try {
                $safeName = ($p -replace '[:\\ ]', '_').Trim('_')
                $dest = Join-Path $backupDir "$safeName-$timestamp.bak"
                Copy-Item $p $dest -Force -ErrorAction SilentlyContinue
                Write-Step "Backup created: $dest"
            } catch {
                Write-Warning "Backup failed for $p : $($_.Exception.Message)"
            }
        }
    }
}

function Set-ConfigValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Value
    )

    if (-not (Test-Path $Path)) {
        throw "Config not found: $Path"
    }

    $escaped = [regex]::Escape($Name)
    $line = "$Name=$Value"

    $content = @(Get-Content $Path -ErrorAction Stop)
    $newContent = @()

    foreach ($c in $content) {
        if ($c -notmatch "^\s*#?\s*$escaped\s*=") {
            $newContent += $c
        }
    }

    $newContent += $line

    Set-Content -Path $Path -Value $newContent -Encoding ASCII
}

function Remove-ConfigValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $escaped = [regex]::Escape($Name)
    $content = @(Get-Content $Path -ErrorAction Stop)
    $newContent = @()

    foreach ($c in $content) {
        if ($c -notmatch "^\s*#?\s*$escaped\s*=") {
            $newContent += $c
        }
    }

    Set-Content -Path $Path -Value $newContent -Encoding ASCII
}

function Remove-ZabbixServiceAndEventLogLeftovers {
    param(
        [string[]]$ServiceNames = @('Zabbix Agent 2','Zabbix Agent'),
        [string[]]$EventLogNames = @('Zabbix Agent 2','Zabbix Agent')
    )

    Write-Step "Cleaning service/EventLog leftovers..."

    foreach ($svcName in $ServiceNames) {
        try {
            Stop-Service $svcName -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    try {
        Get-Process '*zabbix*' -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    } catch {}

    Start-Sleep -Seconds 2

    foreach ($svcName in $ServiceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue

        if ($svc) {
            Write-Step "Deleting leftover service: $svcName"
            sc.exe delete "$svcName" | Out-Null
            Start-Sleep -Seconds 1
        }
    }

    foreach ($eventName in $EventLogNames) {
        $eventKey = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\$eventName"

        if (Test-Path $eventKey) {
            Write-Step "Deleting leftover EventLog registry key: $eventKey"
            Remove-Item $eventKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Seconds 2
}

function Remove-BrokenZabbixAgentManually {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Package
    )

    Write-Warning "MSI uninstall failed. Starting manual cleanup for: $($Package.DisplayName) $($Package.RawVersion)"

    $serviceNames = if ($Package.Kind -eq 'Agent2') {
        @('Zabbix Agent 2')
    } else {
        @('Zabbix Agent')
    }

    $serviceInfo = @(Get-ZabbixServiceInfo) |
        Where-Object { $_.Kind -eq $Package.Kind }

    foreach ($svc in $serviceInfo) {
        Write-Step "Manual cleanup service: $($svc.ServiceName)"

        try {
            Stop-Service $svc.ServiceName -Force -ErrorAction SilentlyContinue
        } catch {}

        if ($svc.Exe -and (Test-Path $svc.Exe)) {
            Write-Step "Trying binary uninstall: $($svc.Exe)"

            try {
                if ($svc.Conf -and (Test-Path $svc.Conf)) {
                    & $svc.Exe --config $svc.Conf --uninstall 2>&1 | Write-Host
                } else {
                    & $svc.Exe --uninstall 2>&1 | Write-Host
                }
            } catch {}

            try {
                if ($svc.Conf -and (Test-Path $svc.Conf)) {
                    & $svc.Exe -c $svc.Conf -d 2>&1 | Write-Host
                } else {
                    & $svc.Exe -d 2>&1 | Write-Host
                }
            } catch {}
        }

        try {
            sc.exe delete "$($svc.ServiceName)" | Out-Null
        } catch {}
    }

    Remove-ZabbixServiceAndEventLogLeftovers `
        -ServiceNames $serviceNames `
        -EventLogNames $serviceNames

    foreach ($svc in $serviceInfo) {
        if ($svc.ExeFolder -and (Test-Path $svc.ExeFolder)) {
            try {
                $newName = "$($svc.ExeFolder).old-$(Get-Date -Format yyyyMMdd-HHmmss)"
                Write-Step "Renaming old Zabbix folder: $($svc.ExeFolder) -> $newName"
                Rename-Item -Path $svc.ExeFolder -NewName (Split-Path $newName -Leaf) -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Could not rename old folder $($svc.ExeFolder): $($_.Exception.Message)"
            }
        }
    }

    if ($Package.RegistryKey) {
        try {
            Write-Step "Removing broken uninstall registry entry: $($Package.RegistryKey)"
            Remove-Item -Path $Package.RegistryKey -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not remove registry uninstall entry: $($_.Exception.Message)"
        }
    }

    Write-Warning "Manual cleanup finished for: $($Package.DisplayName) $($Package.RawVersion)"
}

function Uninstall-MsiByGuid {
    param(
        [string]$Guid,
        [string]$NameForLog,
        [bool]$AllowFail = $false
    )

    if (-not $Guid) {
        if ($AllowFail) {
            Write-Warning "MSI GUID is empty for $NameForLog"
            return $false
        }

        throw "MSI GUID is empty for $NameForLog"
    }

    $safeName = ($NameForLog -replace '[^\w\.-]', '_')
    $uninstallLog = Join-Path $workDir ("uninstall-$safeName-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Step "Uninstalling MSI package: $NameForLog, GUID: $Guid"

    $args = @(
        '/x', $Guid,
        '/qn',
        '/norestart',
        'REBOOT=ReallySuppress',
        'MSIRESTARTMANAGERCONTROL=Disable',
        '/l*v', "`"$uninstallLog`""
    )

    $p = Start-Process msiexec.exe `
        -ArgumentList $args `
        -Wait `
        -PassThru

    Write-Step "Uninstall exit code: $($p.ExitCode)"

    if ($p.ExitCode -in @(0,3010,1605)) {
        if ($p.ExitCode -eq 3010) {
            Write-Warning "Uninstall returned 3010. Reboot may be required."
        }

        Write-Step "Uninstall completed. Log: $uninstallLog"
        return $true
    }

    Write-Warning "Uninstall failed with exit code $($p.ExitCode). Log: $uninstallLog"

    if ($AllowFail) {
        return $false
    }

    throw "Uninstall failed with exit code $($p.ExitCode). Log: $uninstallLog"
}

function Uninstall-ZabbixPackage {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Package
    )

    Write-Step "Preparing uninstall: $($Package.DisplayName) $($Package.RawVersion)"

    $svcName = if ($Package.Kind -eq 'Agent2') {
        'Zabbix Agent 2'
    } else {
        'Zabbix Agent'
    }

    try {
        Stop-Service $svcName -Force -ErrorAction SilentlyContinue
    } catch {}

    if (-not $Package.Guid) {
        Write-Warning "MSI GUID not found for $($Package.DisplayName). Trying manual cleanup."
        Remove-BrokenZabbixAgentManually -Package $Package
        return
    }

    $ok = Uninstall-MsiByGuid `
        -Guid $Package.Guid `
        -NameForLog "$($Package.Kind)-$($Package.DisplayVersion)" `
        -AllowFail $true

    Start-Sleep -Seconds 3

    if ($ok) {
        Remove-ZabbixServiceAndEventLogLeftovers `
            -ServiceNames @($svcName) `
            -EventLogNames @($svcName)

        return
    }

    Write-Warning "MSI uninstall failed for $($Package.DisplayName). Falling back to manual cleanup."

    Remove-BrokenZabbixAgentManually -Package $Package
}

function Remove-UnwantedZabbixAgents {
    param(
        [string]$DesiredVersion
    )

    $programs = @(Get-ZabbixInstalledPrograms)

    if ($programs.Count -eq 0) {
        Write-Step "No installed Zabbix MSI packages found."
    } else {
        Write-Step "Installed Zabbix MSI packages:"
        $programs |
            Select-Object Kind, DisplayName, RawVersion, InstallLocation, Guid |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    }

    foreach ($pkg in $programs) {
        $remove = $false
        $reason = ''

        if ($pkg.Kind -eq 'Agent1') {
            $remove = $true
            $reason = 'Agent1 is not allowed. Target is Agent2 only.'
        } elseif ($pkg.Kind -eq 'Agent2' -and $pkg.DisplayVersion -ne $DesiredVersion) {
            $remove = $true
            $reason = "Agent2 version $($pkg.DisplayVersion) is not target version $DesiredVersion."
        } else {
            $remove = $false
            $reason = 'Correct Agent2 version detected. MSI uninstall/reinstall is not required.'
        }

        if ($remove) {
            Write-Step "Will remove $($pkg.DisplayName) $($pkg.RawVersion). Reason: $reason"

            if ($Install) {
                Uninstall-ZabbixPackage -Package $pkg
            }
        } else {
            Write-Step "Keeping package: $($pkg.DisplayName) $($pkg.RawVersion). Reason: $reason"
        }
    }
}

function Install-ZabbixAgent2Msi {
    param(
        [string]$MsiUrl,
        [string]$MsiPath,
        [string]$InstallFolder,
        [string]$AgentLogFile
    )

    if (-not (Test-Path $MsiPath)) {
        Write-Step "Downloading MSI: $MsiUrl"
        Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
    } else {
        Write-Step "MSI already exists: $MsiPath"
    }

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $msiLog = Join-Path $workDir ("install-Agent2-$Version-attempt$attempt-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

        $args = @(
            '/i', "`"$MsiPath`"",
            '/qn',
            '/norestart',
            '/l*v', "`"$msiLog`"",
            "SERVER=$Server",
            "SERVERACTIVE=$ServerActive",
            "HOSTNAME=$Hostname",
            "LISTENPORT=$ListenPort",
            'LOGTYPE=file',
            "LOGFILE=`"$AgentLogFile`"",
            "INSTALLFOLDER=`"$InstallFolder`"",
            'ENABLEPATH=1'
        )

        Write-Step "Running MSI installer for Zabbix Agent 2 $Version. Attempt: $attempt"
        Write-Step "Target install folder: $InstallFolder"

        $p = Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -PassThru

        Write-Step "Install exit code: $($p.ExitCode)"

        if ($p.ExitCode -in @(0,3010)) {
            if ($p.ExitCode -eq 3010) {
                Write-Warning "Install returned 3010. Reboot may be required."
            }

            Write-Step "Install completed. Log: $msiLog"
            return
        }

        if ($p.ExitCode -eq 1603 -and $attempt -eq 1) {
            Write-Warning "Install failed with 1603. Cleaning EventLog/service leftovers and retrying once."
            Write-Warning "MSI log: $msiLog"

            Remove-ZabbixServiceAndEventLogLeftovers `
                -ServiceNames @('Zabbix Agent 2','Zabbix Agent') `
                -EventLogNames @('Zabbix Agent 2','Zabbix Agent')

            continue
        }

        throw "msiexec install failed with exit code $($p.ExitCode). MSI log: $msiLog"
    }
}

function Install-ZabbixAgent2PluginsMsi {
    param(
        [string]$PluginMsiUrl,
        [string]$PluginMsiPath,
        [string]$InstallFolder
    )

    if (-not $InstallPlugins) {
        Write-Step "Agent2 plugins installation skipped. InstallPlugins=false."
        return
    }

    $plugins = @(Get-ZabbixAgent2PluginsPackage)
    $pluginTargetDir = Join-Path $InstallFolder 'zabbix_agent2.d\plugins.d'
    $pluginTargetExists = Test-Path $pluginTargetDir

    if ($plugins.Count -gt 0) {
        Write-Step "Installed Zabbix Agent2 plugin packages:"
        $plugins |
            Select-Object DisplayName, RawVersion, InstallLocation, Guid |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    } else {
        Write-Step "No installed Zabbix Agent2 plugin package found."
    }

    $samePlugin = $plugins |
        Where-Object { $_.DisplayVersion -eq $Version } |
        Select-Object -First 1

    if ($samePlugin -and -not $ReinstallPlugins -and $pluginTargetExists) {
        Write-Step "Zabbix Agent2 plugins $Version already installed and plugin folder exists. Plugin MSI install will be skipped."
        return
    }

    foreach ($pkg in $plugins) {
        $needRemove = $false
        $reason = ''

        if ($pkg.DisplayVersion -ne $Version) {
            $needRemove = $true
            $reason = "Plugin version $($pkg.DisplayVersion) is not target $Version."
        }

        if ($ReinstallPlugins) {
            $needRemove = $true
            $reason = "ReinstallPlugins=true."
        }

        if (-not $pluginTargetExists) {
            $needRemove = $true
            $reason = "Plugin target directory not found in $pluginTargetDir."
        }

        if ($needRemove) {
            Write-Step "Will remove Agent2 plugins: $($pkg.DisplayName) $($pkg.RawVersion). Reason: $reason"

            if ($Install) {
                if ($pkg.Guid) {
                    Uninstall-MsiByGuid `
                        -Guid $pkg.Guid `
                        -NameForLog "Agent2-Plugins-$($pkg.DisplayVersion)" `
                        -AllowFail $true | Out-Null
                } else {
                    Write-Warning "Plugins package GUID not found. Cannot uninstall via MSI: $($pkg.DisplayName)"
                }
            }
        }
    }

    $pluginsAfterCleanup = @(Get-ZabbixAgent2PluginsPackage)
    $samePluginAfterCleanup = $pluginsAfterCleanup |
        Where-Object { $_.DisplayVersion -eq $Version } |
        Select-Object -First 1

    $pluginTargetExists = Test-Path $pluginTargetDir

    if ($samePluginAfterCleanup -and -not $ReinstallPlugins -and $pluginTargetExists) {
        Write-Step "Zabbix Agent2 plugins $Version are already present in target folder. Plugin MSI install will be skipped."
        return
    }

    if (-not (Test-Path $PluginMsiPath)) {
        Write-Step "Downloading Agent2 plugins MSI: $PluginMsiUrl"
        Invoke-WebRequest -Uri $PluginMsiUrl -OutFile $PluginMsiPath -UseBasicParsing
    } else {
        Write-Step "Agent2 plugins MSI already exists: $PluginMsiPath"
    }

    $pluginsInstallLog = Join-Path $workDir ("install-Agent2-Plugins-$Version-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    Write-Step "Installing Zabbix Agent2 plugins $Version"
    Write-Step "Plugin target install folder: $InstallFolder"

    $p = Start-Process msiexec.exe `
        -ArgumentList "/i `"$PluginMsiPath`" /qn /norestart /l*v `"$pluginsInstallLog`" INSTALLFOLDER=`"$InstallFolder`"" `
        -Wait `
        -PassThru

    Write-Step "Plugins install exit code: $($p.ExitCode)"

    if ($p.ExitCode -notin @(0,3010)) {
        throw "Agent2 plugins install failed with exit code $($p.ExitCode). Log: $pluginsInstallLog"
    }

    if ($p.ExitCode -eq 3010) {
        Write-Warning "Plugins installer returned 3010. Reboot may be required."
    }

    Write-Step "Agent2 plugins installed. Log: $pluginsInstallLog"
}

function Repair-ZabbixAgent2PluginConfigs {
    param(
        [string]$InstallFolder
    )

    if (-not $InstallPlugins) {
        Write-Step "Plugin config repair skipped. InstallPlugins=false."
        return
    }

    Write-Step "Checking all Agent2 config files for unresolved [ExeFile] placeholders..."

    $folders = @(Get-ZabbixCandidateFolders)
    $folders += $InstallFolder
    $folders = $folders |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
        ForEach-Object { Normalize-FolderPath $_ } |
        Select-Object -Unique

    if ($folders.Count -eq 0) {
        Write-Step "No Zabbix folders found for plugin config repair."
        return
    }

    $exeFiles = @()

    foreach ($folder in $folders) {
        $exeFiles += Get-ChildItem $folder -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notmatch '^zabbix_agent2\.exe$' -and
                $_.Name -match 'plugin|mssql|mysql|postgres|pgsql|mongo|redis|oracle|mqtt|ceph|docker|elastic|zabbix'
            }
    }

    $confFiles = @()

    foreach ($folder in $folders) {
        $confFiles += Get-ChildItem $folder -Recurse -Filter "*.conf" -ErrorAction SilentlyContinue
    }

    $confFiles = $confFiles | Select-Object -Unique FullName

    if ($confFiles.Count -eq 0) {
        Write-Step "No .conf files found for plugin repair."
        return
    }

    $foundAny = $false

    foreach ($conf in $confFiles) {
        $content = @(Get-Content $conf.FullName -ErrorAction SilentlyContinue)

        $problemLines = @(
            $content |
                Where-Object {
                    $_ -match '\[ExeFile\]' -and
                    $_ -notmatch '^\s*[#;]'
                }
        )

        if ($problemLines.Count -eq 0) {
            continue
        }

        $foundAny = $true

        Write-Warning "Found unresolved active [ExeFile] in: $($conf.FullName)"

        if ($Install) {
            $backup = "$($conf.FullName).bak-exefile-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $conf.FullName $backup -Force

            $newContent = @()

            foreach ($line in $content) {
                if ($line -match '^\s*[#;]') {
                    $newContent += $line
                    continue
                }

                if ($line -match '^\s*(Plugins\.([^.]+)\.System\.Path\s*=\s*)\[ExeFile\]\s*$') {
                    $prefix = $Matches[1]
                    $pluginName = $Matches[2].ToLowerInvariant()

                    $patterns = @($pluginName)

                    switch -Regex ($pluginName) {
                        'mssql|sqlserver' {
                            $patterns += @('mssql','sqlserver','sql')
                        }
                        'postgres|postgresql|pgsql' {
                            $patterns += @('postgres','postgresql','pgsql')
                        }
                        'mysql' {
                            $patterns += @('mysql')
                        }
                        'mongo|mongodb' {
                            $patterns += @('mongo','mongodb')
                        }
                        'redis' {
                            $patterns += @('redis')
                        }
                        'oracle' {
                            $patterns += @('oracle')
                        }
                        'mqtt' {
                            $patterns += @('mqtt')
                        }
                        'ceph' {
                            $patterns += @('ceph')
                        }
                        'docker' {
                            $patterns += @('docker')
                        }
                        'elastic|elasticsearch' {
                            $patterns += @('elastic','elasticsearch')
                        }
                    }

                    $matchedExe = $null

                    foreach ($pat in ($patterns | Select-Object -Unique)) {
                        $matchedExe = $exeFiles |
                            Where-Object {
                                $_.Name.ToLowerInvariant() -like "*$pat*"
                            } |
                            Select-Object -First 1

                        if ($matchedExe) {
                            break
                        }
                    }

                    if ($matchedExe) {
                        Write-Step "Resolved plugin $pluginName path: $($matchedExe.FullName)"
                        $newContent += "$prefix$($matchedExe.FullName)"
                    } else {
                        Write-Warning "Could not resolve executable for plugin $pluginName. Commenting line."
                        $newContent += "# Disabled by deploy script: unresolved [ExeFile]"
                        $newContent += "# $line"
                    }
                } elseif ($line -match '\[ExeFile\]') {
                    Write-Warning "Commenting unresolved [ExeFile] line: $line"
                    $newContent += "# Disabled by deploy script: unresolved [ExeFile]"
                    $newContent += "# $line"
                } else {
                    $newContent += $line
                }
            }

            Set-Content -Path $conf.FullName -Value $newContent -Encoding ASCII

            Write-Step "Plugin config repaired: $($conf.FullName)"
            Write-Step "Backup: $backup"
        }
    }

    if (-not $foundAny) {
        Write-Step "No active unresolved [ExeFile] placeholders found."
    }
}

function Add-ZabbixFirewallRule {
    param(
        [int]$Port,
        [string]$RuleName
    )

    if ($SkipFirewallRule) {
        Write-Step "Firewall rule skipped by parameter."
        return
    }

    try {
        $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

        if ($existing) {
            Write-Step "Firewall rule already exists: $RuleName"
            return
        }

        Write-Step "Creating firewall rule: TCP $Port"

        New-NetFirewallRule `
            -DisplayName $RuleName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $Port `
            -Profile Any | Out-Null
    } catch {
        Write-Warning "Could not create firewall rule: $($_.Exception.Message)"
    }
}

function Start-ZabbixAgent2 {
    param(
        [string]$ConfFile,
        [string]$ExeFile,
        [bool]$ConfigChanged
    )

    $serviceName = 'Zabbix Agent 2'

    if (-not (Test-Path $ExeFile)) {
        throw "Agent2 executable not found: $ExeFile"
    }

    if (-not (Test-Path $ConfFile)) {
        throw "Agent2 config not found: $ConfFile"
    }

    $installFolderForRepair = Split-Path $ExeFile -Parent
    Repair-ZabbixAgent2PluginConfigs -InstallFolder $installFolderForRepair

    Write-Step "Testing config with agent.version..."

    $testOutput = & $ExeFile -c $ConfFile -t agent.version 2>&1
    $testCode = $LASTEXITCODE

    $testOutput | Write-Host

    if ($testCode -ne 0) {
        Write-Step "Agent2 config test failed. Searching for active unresolved [ExeFile] placeholders..."

        try {
            Get-ChildItem (Split-Path $ConfFile -Parent) -Recurse -Filter "*.conf" -ErrorAction SilentlyContinue |
                Select-String '^\s*[^#;].*\[ExeFile\]' |
                Select-Object Path, LineNumber, Line |
                Format-Table -AutoSize |
                Out-String |
                Write-Host
        } catch {}

        throw "Agent2 config test failed. ExitCode: $testCode"
    }

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if (-not $svc) {
        Write-Step "Service not found. Trying to register service manually."

        Remove-ZabbixServiceAndEventLogLeftovers `
            -ServiceNames @($serviceName) `
            -EventLogNames @($serviceName)

        $installOut = & $ExeFile -c $ConfFile --install 2>&1
        $installCode = $LASTEXITCODE

        $installOut | Write-Host

        if ($installCode -ne 0) {
            throw "Manual service registration failed. ExitCode: $installCode"
        }

        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    }

    if ($svc -and $svc.Status -eq 'Running' -and -not $ConfigChanged) {
        Write-Step "Service is already running and config was not changed. Restart skipped."
        return
    }

    Write-Step "Starting/restarting service: $serviceName"

    Set-Service -Name $serviceName -StartupType Automatic -ErrorAction SilentlyContinue

    try {
        Restart-Service -Name $serviceName -Force -ErrorAction Stop
    } catch {
        Start-Service -Name $serviceName -ErrorAction Stop
    }

    Start-Sleep -Seconds 3

    $svc = Get-Service -Name $serviceName -ErrorAction Stop

    if ($svc.Status -ne 'Running') {
        throw "Service is not running: $serviceName. Current status: $($svc.Status)"
    }
}

try {
    $script:InstallFolderNormalized = Normalize-FolderPath $InstallFolder
    $InstallFolder = $script:InstallFolderNormalized

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        $Hostname = Get-LowerFqdnHostname
    } else {
        $Hostname = $Hostname.ToLowerInvariant()
    }

    $os = Get-CimInstance Win32_OperatingSystem
    $osVersion = [version]$os.Version

    Write-Step "OS: $($os.Caption) $($os.Version)"
    Write-Step "Hostname: $Hostname"
    Write-Step "Target: Zabbix Agent 2 $Version"
    Write-Step "Default InstallFolder: $InstallFolder"
    Write-Step "Server: $Server"
    Write-Step "ServerActive: $ServerActive"
    Write-Step "HostMetadata: $HostMetadata"
    Write-Step "InstallPlugins: $InstallPlugins"
    Write-Step "ReinstallPlugins: $ReinstallPlugins"
    Write-Step "ForceInstallFolder: $ForceInstallFolder"
    Write-Step "SkipIfAlreadyCorrect: $SkipIfAlreadyCorrect"

    if ($TargetAgent -ne 'Agent2') {
        Write-Warning "Parameter TargetAgent=$TargetAgent is accepted for compatibility, but ignored. This script always installs Agent2 $Version."
    }

    if ($osVersion.Major -lt 10) {
        throw "This script is intended for Windows Server 2016/2019/2022 or newer. Current OS: $($os.Caption) $($os.Version)"
    }

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "This script expects 64-bit Windows."
    }

    $arch = 'amd64'

    $confFile = Join-Path $InstallFolder 'zabbix_agent2.conf'
    $agentLogFile = Join-Path $InstallFolder 'zabbix_agent2.log'
    $agentExeFile = Join-Path $InstallFolder 'zabbix_agent2.exe'
    $pluginInclude = Join-Path $InstallFolder 'zabbix_agent2.d\plugins.d\*.conf'

    $msiName = "zabbix_agent2-$Version-windows-$arch-openssl.msi"
    $msiUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/6.4/$Version/$msiName"
    $msiPath = Join-Path $workDir $msiName

    $pluginMsiName = "zabbix_agent2_plugins-$Version-windows-$arch.msi"
    $pluginMsiUrl = "https://cdn.zabbix.com/zabbix/binaries/stable/6.4/$Version/$pluginMsiName"
    $pluginMsiPath = Join-Path $workDir $pluginMsiName

    $currentServices = @(Get-ZabbixServiceInfo)

    if ($currentServices.Count -eq 0) {
        Write-Step "No Zabbix services currently found."
    } else {
        Write-Step "Current Zabbix services:"
        $currentServices |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    }

    $agent2Check = Test-DesiredAgent2AlreadyInstalled `
        -DesiredVersion $Version `
        -DesiredInstallFolder $InstallFolder `
        -RequireTargetFolder $ForceInstallFolder

    Write-Step "Agent2 pre-check result: $($agent2Check.IsOk)"

    foreach ($r in $agent2Check.Reason) {
        Write-Step "Agent2 pre-check: $r"
    }

    if ($agent2Check.IsOk) {
        if ($agent2Check.Folder) {
            $InstallFolder = Normalize-FolderPath $agent2Check.Folder
            $confFile = if ($agent2Check.Conf) { $agent2Check.Conf } else { Join-Path $InstallFolder 'zabbix_agent2.conf' }
            $agentLogFile = Join-Path $InstallFolder 'zabbix_agent2.log'
            $agentExeFile = if ($agent2Check.Exe) { $agent2Check.Exe } else { Join-Path $InstallFolder 'zabbix_agent2.exe' }
            $pluginInclude = Join-Path $InstallFolder 'zabbix_agent2.d\plugins.d\*.conf'

            Write-Step "Using existing Agent2 folder: $InstallFolder"
            Write-Step "Using existing Agent2 config: $confFile"
        }
    }

    $pluginsCheck = Test-PluginsCorrect `
        -DesiredVersion $Version `
        -AgentFolder $InstallFolder

    Write-Step "Plugins pre-check result: $($pluginsCheck.IsOk)"
    foreach ($r in $pluginsCheck.Reason) {
        Write-Step "Plugins pre-check: $r"
    }

    $configCheck = Test-Agent2ConfigCorrect `
        -ConfFile $confFile `
        -ExpectedLogFile $agentLogFile `
        -ExpectedServer $Server `
        -ExpectedServerActive $ServerActive `
        -ExpectedHostname $Hostname `
        -ExpectedListenPort $ListenPort `
        -ExpectedTimeout $Timeout `
        -ExpectedHostMetadata $HostMetadata `
        -ExpectedInclude $pluginInclude `
        -NeedPlugins $InstallPlugins

    Write-Step "Config pre-check result: $($configCheck.IsOk)"
    foreach ($r in $configCheck.Reason) {
        Write-Step "Config pre-check: $r"
    }

    $firewallOk = Test-ZabbixFirewallRule -RuleName 'Zabbix Agent TCP 10050' -Port $ListenPort
    Write-Step "Firewall pre-check result: $firewallOk"

    $foldersForPlaceholderCheck = @(Get-ZabbixCandidateFolders)
    $foldersForPlaceholderCheck += $InstallFolder
    $foldersForPlaceholderCheck = $foldersForPlaceholderCheck |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    $hasActiveExeFilePlaceholders = Test-ActiveExeFilePlaceholders -Folders $foldersForPlaceholderCheck
    Write-Step "Active [ExeFile] placeholder pre-check result: $hasActiveExeFilePlaceholders"

    $serviceRunning = $false
    if ($agent2Check.State -eq 'Running') {
        $serviceRunning = $true
    }
    Write-Step "Service running pre-check result: $serviceRunning"

    $everythingAlreadyCorrect = (
        $agent2Check.IsOk -and
        $pluginsCheck.IsOk -and
        $configCheck.IsOk -and
        $firewallOk -and
        (-not $hasActiveExeFilePlaceholders) -and
        $serviceRunning
    )

    if ($everythingAlreadyCorrect -and $SkipIfAlreadyCorrect) {
        Write-Step "Everything already correct. Nothing to change."
        Write-Step "DONE. No install, no plugin reinstall, no config rewrite, no service restart."
        return
    }

    if (-not $Install) {
        Write-Host ""
        Write-Host "CHECK MODE ONLY. Nothing was changed."
        Write-Host "To apply changes, run again with: -Install"
        Write-Host ""
        Write-Host "Example:"
        Write-Host "powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Install-ZabbixAgent.ps1 -Install"
        return
    }

    Backup-ZabbixFiles

    Remove-UnwantedZabbixAgents -DesiredVersion $Version

    $agent2CheckAfterCleanup = Test-DesiredAgent2AlreadyInstalled `
        -DesiredVersion $Version `
        -DesiredInstallFolder $InstallFolder `
        -RequireTargetFolder $ForceInstallFolder

    $needInstall = -not $agent2CheckAfterCleanup.IsOk

    if ($needInstall) {
        Remove-ZabbixServiceAndEventLogLeftovers `
            -ServiceNames @('Zabbix Agent 2','Zabbix Agent') `
            -EventLogNames @('Zabbix Agent 2','Zabbix Agent')

        Install-ZabbixAgent2Msi `
            -MsiUrl $msiUrl `
            -MsiPath $msiPath `
            -InstallFolder $InstallFolder `
            -AgentLogFile $agentLogFile
    } else {
        Write-Step "Zabbix Agent 2 $Version is already installed in the target state. MSI reinstall is not required."

        if ($agent2CheckAfterCleanup.Folder) {
            $InstallFolder = Normalize-FolderPath $agent2CheckAfterCleanup.Folder
            $confFile = if ($agent2CheckAfterCleanup.Conf) { $agent2CheckAfterCleanup.Conf } else { Join-Path $InstallFolder 'zabbix_agent2.conf' }
            $agentLogFile = Join-Path $InstallFolder 'zabbix_agent2.log'
            $agentExeFile = if ($agent2CheckAfterCleanup.Exe) { $agent2CheckAfterCleanup.Exe } else { Join-Path $InstallFolder 'zabbix_agent2.exe' }
            $pluginInclude = Join-Path $InstallFolder 'zabbix_agent2.d\plugins.d\*.conf'
        }
    }

    $pluginsCheckAfterAgent = Test-PluginsCorrect `
        -DesiredVersion $Version `
        -AgentFolder $InstallFolder

    if (-not $pluginsCheckAfterAgent.IsOk -or $ReinstallPlugins) {
        Install-ZabbixAgent2PluginsMsi `
            -PluginMsiUrl $pluginMsiUrl `
            -PluginMsiPath $pluginMsiPath `
            -InstallFolder $InstallFolder
    } else {
        Write-Step "Agent2 plugins are already correct. Plugin MSI install will be skipped."
    }

    Repair-ZabbixAgent2PluginConfigs -InstallFolder $InstallFolder

    Start-Sleep -Seconds 3

    if (-not (Test-Path $confFile)) {
        throw "Config file not found: $confFile"
    }

    $configCheckBeforeWrite = Test-Agent2ConfigCorrect `
        -ConfFile $confFile `
        -ExpectedLogFile $agentLogFile `
        -ExpectedServer $Server `
        -ExpectedServerActive $ServerActive `
        -ExpectedHostname $Hostname `
        -ExpectedListenPort $ListenPort `
        -ExpectedTimeout $Timeout `
        -ExpectedHostMetadata $HostMetadata `
        -ExpectedInclude $pluginInclude `
        -NeedPlugins $InstallPlugins

    $configChanged = $false

    if (-not $configCheckBeforeWrite.IsOk) {
        $confBackup = "$confFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item $confFile $confBackup -Force
        Write-Step "Config backup created: $confBackup"

        Write-Step "Writing config..."

        Set-ConfigValue $confFile 'LogType' 'file'
        Set-ConfigValue $confFile 'LogFile' $agentLogFile
        Set-ConfigValue $confFile 'Server' $Server
        Set-ConfigValue $confFile 'ListenPort' $ListenPort
        Set-ConfigValue $confFile 'ServerActive' $ServerActive
        Set-ConfigValue $confFile 'Hostname' $Hostname
        Set-ConfigValue $confFile 'HostMetadata' $HostMetadata
        Set-ConfigValue $confFile 'Timeout' $Timeout

        if ($InstallPlugins) {
            New-Item -ItemType Directory -Force -Path (Join-Path $InstallFolder 'zabbix_agent2.d\plugins.d') | Out-Null
            Set-ConfigValue $confFile 'Include' $pluginInclude
        }

        Remove-ConfigValue $confFile 'EnablePersistentBuffer'
        Remove-ConfigValue $confFile 'PersistentBufferPeriod'
        Remove-ConfigValue $confFile 'PersistentBufferFile'

        $configChanged = $true
    } else {
        Write-Step "Config is already correct. Config rewrite skipped."
    }

    Repair-ZabbixAgent2PluginConfigs -InstallFolder $InstallFolder

    $firewallOkAfter = Test-ZabbixFirewallRule -RuleName 'Zabbix Agent TCP 10050' -Port $ListenPort

    if (-not $firewallOkAfter) {
        Add-ZabbixFirewallRule -Port $ListenPort -RuleName 'Zabbix Agent TCP 10050'
    } else {
        Write-Step "Firewall rule is already correct. Firewall change skipped."
    }

    Start-ZabbixAgent2 `
        -ConfFile $confFile `
        -ExeFile $agentExeFile `
        -ConfigChanged $configChanged

    $finalServices = @(Get-ZabbixServiceInfo)
    $finalPrograms = @(Get-ZabbixInstalledPrograms)
    $finalPlugins = @(Get-ZabbixAgent2PluginsPackage)

    Write-Step "Final installed Zabbix MSI packages:"
    $finalPrograms |
        Select-Object Kind, DisplayName, RawVersion, InstallLocation, Guid |
        Format-Table -AutoSize |
        Out-String |
        Write-Host

    Write-Step "Final installed Zabbix Agent2 plugins packages:"
    if ($finalPlugins.Count -gt 0) {
        $finalPlugins |
            Select-Object DisplayName, RawVersion, InstallLocation, Guid |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    } else {
        Write-Host "No Agent2 plugins package found."
    }

    Write-Step "Final Zabbix services:"
    $finalServices |
        Format-Table -AutoSize |
        Out-String |
        Write-Host

    $finalAgent2 = $finalServices |
        Where-Object { $_.Kind -eq 'Agent2' } |
        Select-Object -First 1

    if (-not $finalAgent2) {
        throw "Final check failed: Zabbix Agent 2 service not found."
    }

    if ($finalAgent2.Version -ne $Version) {
        throw "Final check failed: expected Agent2 $Version, got $($finalAgent2.Version)"
    }

    if ($finalAgent2.State -ne 'Running') {
        throw "Final check failed: Agent2 service is not running."
    }

    if ($ForceInstallFolder -and $finalAgent2.ExeFolder -and -not (Test-SameFolder $finalAgent2.ExeFolder $InstallFolder)) {
        throw "Final check failed: Agent2 service path is '$($finalAgent2.ExeFolder)', expected '$InstallFolder'"
    }

    $leftAgent1 = $finalServices |
        Where-Object { $_.Kind -eq 'Agent1' }

    if ($leftAgent1) {
        throw "Final check failed: old Zabbix Agent 1 service still exists."
    }

    if ($InstallPlugins) {
        $pluginOk = $finalPlugins |
            Where-Object { $_.DisplayVersion -eq $Version } |
            Select-Object -First 1

        if (-not $pluginOk) {
            Write-Warning "Agent2 plugins package $Version was not detected in installed programs. Check MSI log in $workDir."
        }
    }

    Write-Step "Important config lines:"
    Get-Content $confFile |
        Select-String '^(LogType|LogFile|Server|ListenPort|ServerActive|Hostname|HostMetadata|Timeout|Include)=' |
        ForEach-Object { $_.Line } |
        Write-Host

    Write-Step "Checking active unresolved [ExeFile] placeholders after repair..."

    $leftExeFilePlaceholders = @()

    foreach ($folder in @(Get-ZabbixCandidateFolders)) {
        if (Test-Path $folder) {
            $leftExeFilePlaceholders += Get-ChildItem $folder -Recurse -Filter "*.conf" -ErrorAction SilentlyContinue |
                Select-String '^\s*[^#;].*\[ExeFile\]' -ErrorAction SilentlyContinue
        }
    }

    if ($leftExeFilePlaceholders.Count -gt 0) {
        Write-Warning "Active unresolved [ExeFile] placeholders still found:"
        $leftExeFilePlaceholders |
            Select-Object Path, LineNumber, Line |
            Format-Table -AutoSize |
            Out-String |
            Write-Host
    } else {
        Write-Step "No active unresolved [ExeFile] placeholders found."
    }

    Write-Step "Testing TCP connection to first ServerActive address on port 10051..."

    try {
        $firstActive = $ServerActive.Split(',')[0].Trim()
        $firstActiveHost = $firstActive.Split(':')[0].Trim()

        Test-NetConnection -ComputerName $firstActiveHost -Port 10051 |
            Select-Object ComputerName, RemotePort, TcpTestSucceeded |
            Format-List |
            Out-String |
            Write-Host
    } catch {
        Write-Warning "TCP test failed: $($_.Exception.Message)"
    }

    Write-Step "DONE. Only Zabbix Agent 2 $Version should remain. Current Agent2 folder: $($finalAgent2.ExeFolder)"
    Write-Step "Deploy log: $deployLog"
}
catch {
    Write-Error $_
    throw
}
finally {
    try {
        Stop-Transcript | Out-Null
    } catch {}
}
