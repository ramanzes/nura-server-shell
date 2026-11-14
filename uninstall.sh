#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR GPL-3.0-only
# Copyright (c) 2026 ramanzes — https://github.com/ramanzes/nura-server-shell
# nura-server-shell — удаление. Пакеты (python3, htop, ...) не удаляются.
#   sudo ./uninstall.sh [--restore-gui]
set -eu
[ "$(id -u)" = 0 ] || { echo "Запустите через sudo" >&2; exit 1; }
RESTORE_GUI=0
[ "${1:-}" = "--restore-gui" ] && RESTORE_GUI=1

systemctl disable --now nura-keys.service nura-status.service 2>/dev/null || true
pkill -x buffyboard 2>/dev/null || true
rm -f /etc/systemd/system/nura-status.service /etc/systemd/system/nura-keys.service \
      /usr/local/bin/nura-status /usr/local/bin/nura-keys /usr/local/bin/nura-wifi-join \
      /etc/systemd/logind.conf.d/50-nura-powerkey.conf /etc/sysctl.d/50-console-quiet.conf \
      /etc/modules-load.d/ledtrig-pattern.conf /usr/local/share/nura-server-shell.version \
      /run/nura-wifi-join.log
systemctl unmask -q getty@tty2.service autovt@tty2.service autovt@tty3.service \
  autovt@tty4.service getty@tty5.service autovt@tty5.service || true
systemctl daemon-reload
systemctl kill -s HUP systemd-logind 2>/dev/null || true
systemctl start getty@tty1.service 2>/dev/null || true
if [ "$RESTORE_GUI" = 1 ] && systemctl cat greetd.service >/dev/null 2>&1; then
  systemctl enable greetd.service
  systemctl set-default graphical.target
  echo "Графика включится после перезагрузки"
fi
echo "nura-server-shell удалён"
