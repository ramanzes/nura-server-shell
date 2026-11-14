#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 ramanzes — https://github.com/ramanzes/nura-server-shell
# nura-server-shell — установка серверной оболочки для телефона на Nura (postmarketOS).
#
#   wget -qO- https://raw.githubusercontent.com/ramanzes/nura-server-shell/main/install.sh | sudo sh
#   wget -qO- .../install.sh | sudo sh -s -- --headless    # заодно отключить графику (Phosh и т. п.)
#
# Из клона репозитория: sudo ./install.sh [--headless]
# Повторный запуск обновляет оболочку до последней версии.
set -eu

REPO=ramanzes/nura-server-shell
BRANCH=${NSS_BRANCH:-main}
HEADLESS=0
for a in "$@"; do
  case $a in
    --headless) HEADLESS=1 ;;
    -h|--help) sed -n '4,11p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Неизвестный параметр: $a" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m  %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "Нужны права root: запустите через sudo"
command -v systemctl >/dev/null || die "Нужен systemd (Nura / postmarketOS с systemd)"
command -v apk >/dev/null || die "Нужен apk (Nura / postmarketOS / Alpine)"
[ -e /dev/fb0 ] || warn "Нет /dev/fb0 — экран, возможно, не поддерживается"

# --- источник файлов: клон репозитория или архив с GitHub ---
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /nonexistent)
if [ -f "$HERE/bin/nura-keys" ] && [ -f "$HERE/systemd/nura-keys.service" ]; then
  SRC=$HERE
else
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
  say "Загрузка $REPO ($BRANCH)"
  if command -v curl >/dev/null; then curl -fsSL "$URL"; else wget -qO- "$URL"; fi | tar -xz -C "$TMP" \
    || die "Не удалось скачать $URL"
  SRC=$(echo "$TMP"/*)
fi
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo dev)

# --- зависимости (все есть в репозиториях Alpine) ---
say "Пакеты: python3 iw htop buffyboard kbd font-terminus networkmanager-cli"
apk add -q python3 iw htop buffyboard kbd font-terminus networkmanager-cli \
  || warn "apk add завершился с ошибкой — проверьте зеркала (apk update)"

# --- старая версия (скрипты bacon-*) ---
for s in bacon-keys bacon-status; do
  if [ -e "/etc/systemd/system/$s.service" ]; then
    say "Удаление старой версии: $s"
    systemctl disable --now "$s.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/$s.service"
  fi
  rm -f "/usr/local/bin/$s"
done
rm -f /usr/local/bin/bacon-wifi-join /usr/local/bin/bacon-brightness \
      /etc/systemd/logind.conf.d/50-bacon-powerkey.conf

# --- файлы ---
say "Установка версии $VERSION"
install -m 755 "$SRC/bin/nura-status" "$SRC/bin/nura-keys" "$SRC/bin/nura-wifi-join" /usr/local/bin/
install -m 644 "$SRC/systemd/nura-status.service" "$SRC/systemd/nura-keys.service" /etc/systemd/system/
install -d -m 700 /root/.config/htop
install -m 644 "$SRC/config/htoprc" /root/.config/htop/htoprc
install -d /etc/systemd/logind.conf.d
install -m 644 "$SRC/config/50-nura-powerkey.conf" /etc/systemd/logind.conf.d/
echo 'kernel.printk = 3 4 1 3' > /etc/sysctl.d/50-console-quiet.conf
sysctl -q -p /etc/sysctl.d/50-console-quiet.conf || true
# мигание светодиода (триггер pattern)
if modprobe ledtrig-pattern 2>/dev/null; then
  echo ledtrig-pattern > /etc/modules-load.d/ledtrig-pattern.conf
fi
echo "$VERSION" > /usr/local/share/nura-server-shell.version 2>/dev/null \
  || { install -d /usr/local/share && echo "$VERSION" > /usr/local/share/nura-server-shell.version; }

# tty2..tty5 — htop, консоль, меню, ввод пароля Wi-Fi: обычный вход там не нужен
systemctl mask -q getty@tty2.service autovt@tty2.service autovt@tty3.service \
  autovt@tty4.service getty@tty5.service autovt@tty5.service

# --- графический интерфейс ---
if systemctl is-enabled -q greetd.service 2>/dev/null; then
  if [ "$HEADLESS" = 1 ]; then
    say "Отключение графики: greetd выключен, загрузка в multi-user.target"
    systemctl disable greetd.service
    systemctl set-default multi-user.target
    warn "Графика отключится после перезагрузки (вернуть: systemctl enable greetd; systemctl set-default graphical.target)"
  else
    warn "Включён графический интерфейс (greetd). Табло займёт tty1 только после --headless."
  fi
fi

# --- запуск ---
systemctl daemon-reload
systemctl kill -s HUP systemd-logind 2>/dev/null || true
systemctl enable -q nura-status.service nura-keys.service
systemctl restart nura-status.service nura-keys.service
sleep 2
for s in nura-status nura-keys; do
  systemctl is-active -q "$s" && say "$s: работает" || warn "$s: не запустился — journalctl -u $s"
done
say "Готово. VOL+ дважды — меню, VOL+ и VOL- вместе — htop, VOL- дважды — консоль."
