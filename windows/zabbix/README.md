# Windows Zabbix Agent2

В этом разделе хранится Windows-часть Karelia Admin Toolkit.

Основной рабочий скрипт:

```powershell
Install-ZabbixAgent.ps1
```

Он предназначен для Windows Server 2016/2019/2022 и устанавливает Zabbix Agent2.

## Режим проверки

Без параметра `-Install` скрипт работает в режиме проверки и ничего не меняет:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-ZabbixAgent.ps1
```

## Реальная установка

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-ZabbixAgent.ps1 -Install
```

## Основные параметры

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Install-ZabbixAgent.ps1 `
  -Install `
  -Version 6.4.21 `
  -InstallFolder C:\Zabbix `
  -Server "212.109.13.41,185.90.103.203,192.168.1.53" `
  -ServerActive "192.168.1.53,212.109.13.41"
```

## Что делает скрипт

- определяет текущий Zabbix Agent/Agent2;
- удаляет старый Agent1;
- переустанавливает Agent2 при неправильной версии или пути;
- ставит Agent2 MSI;
- может ставить Agent2 plugins MSI;
- делает backup конфигов;
- пишет `zabbix_agent2.conf`;
- добавляет firewall rule TCP 10050;
- чинит plugin-конфиги с `[ExeFile]`;
- запускает службу `Zabbix Agent 2`;
- пишет лог в `C:\ProgramData\Zabbix\deploy`.

## TODO

- добавить `Status-ZabbixAgent.ps1`;
- добавить `Test-ZabbixAgent.ps1`;
- добавить Windows fleet-режим через PowerShell Remoting или PsExec/SSH;
- унифицировать параметры с Linux-модулем `kat`.
