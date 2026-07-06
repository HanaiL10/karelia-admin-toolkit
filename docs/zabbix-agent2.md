# Zabbix Agent2

## Dry-run

```bash
sudo ./linux/zabbix/update_agent2.sh --major 6.4 --dry-run
```

или после установки:

```bash
sudo kat zabbix-update --major 6.4 --dry-run
```

## Реальное обновление

```bash
sudo kat zabbix-update --major 6.4
```

## Проверка

```bash
kat zabbix-test
```

## UserParameter

Файл создается здесь:

```text
/etc/zabbix/zabbix_agent2.d/karelia-admin-toolkit.conf
```

Ключи:

```text
service.zabbix_agent2.status
copyfail.kernel.running
copyfail.algif_aead.loaded
copyfail.algif_aead.blocked
copyfail.reboot.required
copyfail.pkg.kernel
```

## Бэкапы

Перед изменениями сохраняются:

```text
/etc/zabbix/zabbix_agent2.conf
/etc/zabbix/zabbix_agent2.d
```

Каталог бэкапов:

```text
/var/backups/karelia-admin-toolkit/
```
