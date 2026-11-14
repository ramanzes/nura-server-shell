#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 ramanzes — https://github.com/ramanzes/nura-server-shell
# nura-server-shell — удаление. Пакеты (python3, htop, ...) не удаляются.
#   sudo ./uninstall.sh [--restore-gui]
set -eu
[ "$(id -u)" = 0 ] || { echo "Запустите через sudo" >&2; exit 1; }
RESTORE_GUI=0
[ "${1:-}" = "--restore-gui" ] && RESTORE_GUI=1
if [ -d /run/systemd/system ]; then INIT=systemd; else INIT=openrc; fi

if [ $INIT = systemd ]; then
  systemctl disable --now nura-keys.service nura-status.service 2>/dev/null || true
else
  for s in nura-keys nura-status; do
    rc-service "$s" stop >/dev/null 2>&1 || true
    rc-update del "$s" default >/dev/null 2>&1 || true
  done
fi
pkill -x buffyboard 2>/dev/null || true
# снять запрет переключения консолей, если служба остановлена в режиме блокировки
python3 -c 'import os, fcntl; fd = os.open("/dev/tty0", os.O_RDWR); fcntl.ioctl(fd, 0x560C); os.close(fd)' 2>/dev/null || true
rm -f /etc/systemd/system/nura-status.service /etc/systemd/system/nura-keys.service \
      /etc/init.d/nura-status /etc/init.d/nura-keys \
      /usr/local/bin/nura-status /usr/local/bin/nura-keys /usr/local/bin/nura-wifi-join \
      /usr/local/bin/nura-ctl \
      /etc/systemd/logind.conf.d/50-nura-powerkey.conf /etc/elogind/logind.conf.d/50-nura-powerkey.conf \
      /etc/sysctl.d/50-console-quiet.conf /etc/sysctl.d/50-nura-sysrq.conf \
      /etc/modules-load.d/ledtrig-pattern.conf /var/lib/nura-server-shell/lock-fails \
      /usr/local/share/nura-server-shell.version /run/nura-wifi-join.log

if [ $INIT = systemd ]; then
  systemctl unmask -q getty@tty2.service autovt@tty2.service autovt@tty3.service \
    autovt@tty4.service getty@tty5.service autovt@tty5.service || true
  systemctl daemon-reload
  systemctl kill -s HUP systemd-logind 2>/dev/null || true
  systemctl start getty@tty1.service 2>/dev/null || true
else
  sed -i -E 's/^#nura# //' /etc/inittab     # вернуть getty на tty1..tty5
  kill -HUP 1
  pkill -HUP -x elogind-daemon 2>/dev/null || pkill -HUP -x elogind 2>/dev/null || true
fi

if [ "$RESTORE_GUI" = 1 ]; then
  for s in greetd tinydm; do
    if [ $INIT = systemd ]; then
      systemctl cat "$s.service" >/dev/null 2>&1 || continue
      systemctl enable "$s.service"
      systemctl set-default graphical.target
      systemctl start "$s.service"
    else
      [ -e "/etc/init.d/$s" ] || continue
      rc-update add "$s" default
      rc-service "$s" start
    fi
    echo "Графика ($s) включена"
    break
  done
fi
echo "nura-server-shell удалён"
