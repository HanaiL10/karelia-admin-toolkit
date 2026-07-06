# Karelia Admin Toolkit

Набор админских скриптов для Linux/Windows инфраструктуры.

## v0.2.0

Что уже есть:

- единая команда `kat`;
- интерактивное меню `kat menu`;
- Linux-модуль обновления Zabbix Agent2;
- `--dry-run`;
- бэкап `/etc/zabbix/zabbix_agent2.conf` и `/etc/zabbix/zabbix_agent2.d`;
- добавление `UserParameter` для `service.zabbix_agent2.status`;
- добавление `copyfail.*` проверок;
- smoke-тесты;
- GitHub Actions с `bash -n` и `shellcheck`.

## Быстрый старт с сервера

```bash
git clone https://github.com/HanaiL10/karelia-admin-toolkit.git
cd karelia-admin-toolkit
bash tests/smoke.sh
sudo ./install.sh
kat --help
```

## Меню

```bash
sudo kat menu
```

## Проверка без изменений

```bash
sudo kat zabbix-update --major 6.4 --dry-run
```

## Реальное обновление Zabbix Agent2

```bash
sudo kat zabbix-update --major 6.4
```

## Проверка после обновления

```bash
kat zabbix-test
```

или вручную:

```bash
systemctl status zabbix-agent2 --no-pager
zabbix_agent2 -t service.zabbix_agent2.status
zabbix_agent2 -t copyfail.kernel.running
zabbix_agent2 -t copyfail.algif_aead.loaded
zabbix_agent2 -t copyfail.algif_aead.blocked
zabbix_agent2 -t copyfail.reboot.required
zabbix_agent2 -t copyfail.pkg.kernel
```

## Структура

```text
bin/kat
linux/common/functions.sh
linux/zabbix/update_agent2.sh
docs/zabbix-agent2.md
tests/smoke.sh
.github/workflows/shell.yml
```
