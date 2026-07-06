# Karelia Admin Toolkit

Набор админских скриптов для Linux/Windows инфраструктуры.

## v0.1.1

Сейчас готов первый Linux-модуль:

- обновление Zabbix Agent2 для Debian/Ubuntu;
- `--dry-run`;
- бэкап `/etc/zabbix/zabbix_agent2.conf` и `/etc/zabbix/zabbix_agent2.d`;
- добавление `UserParameter` для `service.zabbix_agent2.status`;
- добавление `copyfail.*` проверок;
- логирование в `/var/log/karelia-admin-toolkit/`;
- smoke-тесты.

## Быстрый старт с сервера

```bash
git clone https://github.com/HanaiL10/karelia-admin-toolkit.git
cd karelia-admin-toolkit
bash tests/smoke.sh
sudo ./install.sh
kat-zabbix-agent2-update --help
```

## Проверка без изменений

```bash
sudo ./linux/zabbix/update_agent2.sh --major 6.4 --dry-run
```

## Реальное обновление Zabbix Agent2

```bash
sudo ./linux/zabbix/update_agent2.sh --major 6.4
```

## Проверка после обновления

```bash
systemctl status zabbix-agent2 --no-pager
zabbix_agent2 -t service.zabbix_agent2.status
zabbix_agent2 -t copyfail.kernel.running
zabbix_agent2 -t copyfail.algif_aead.loaded
zabbix_agent2 -t copyfail.algif_aead.blocked
zabbix_agent2 -t copyfail.reboot.required
zabbix_agent2 -t copyfail.pkg.kernel
```
