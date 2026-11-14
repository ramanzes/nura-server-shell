#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 ramanzes — https://github.com/ramanzes/nura-server-shell
# nura-server-shell — установка серверной оболочки для телефона на Nura (postmarketOS).
#
#   wget -qO- https://raw.githubusercontent.com/ramanzes/nura-server-shell/main/install.sh | sudo sh
#   wget -qO- .../install.sh | sudo sh -s -- --headless    # отключить графику (Phosh и т. п.)
#
# Из клона репозитория: sudo ./install.sh [--headless]
# Повторный запуск обновляет оболочку до последней версии. Работает с systemd и OpenRC.
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
command -v apk >/dev/null || die "Нужен apk (Nura / postmarketOS / Alpine)"
if [ -d /run/systemd/system ]; then
  INIT=systemd
elif command -v openrc >/dev/null && command -v rc-update >/dev/null; then
  INIT=openrc
else
  die "Нужен systemd или OpenRC"
fi
[ -e /dev/fb0 ] || warn "Нет /dev/fb0 — экран, возможно, не поддерживается"

# --- источник файлов: клон репозитория или архив с GitHub ---
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /nonexistent)
if [ -f "$HERE/bin/nura-keys" ] && [ -f "$HERE/openrc/nura-keys" ]; then
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
say "nura-server-shell $VERSION, система инициализации: $INIT"

# --- работает ли графика ---
GUI_SVC=""
for s in greetd tinydm lightdm sddm gdm; do
  if [ $INIT = systemd ]; then
    systemctl is-enabled -q "$s.service" 2>/dev/null && GUI_SVC="$GUI_SVC $s"
  else
    rc-update show default 2>/dev/null | grep -qw "$s" && GUI_SVC="$GUI_SVC $s"
  fi
done
GUI_RUNNING=0
for p in phoc phosh gnome-shell plasmashell kwin_wayland sway Xorg; do
  pgrep -x "$p" >/dev/null 2>&1 && GUI_RUNNING=1
done
START=1
if [ -n "$GUI_SVC" ] || [ $GUI_RUNNING = 1 ]; then
  if [ $HEADLESS = 1 ]; then
    say "Графика будет отключена:${GUI_SVC:- (запущенный сеанс)}"
  else
    START=0
    warn "Работает графический интерфейс${GUI_SVC:+ (${GUI_SVC# })}."
    warn "Оболочка будет установлена, но НЕ запущена: она мешала бы графике (кнопки, экран)."
    warn "Чтобы отключить графику и запустить оболочку: повторите установку с --headless."
  fi
fi

# --- зависимости (все есть в репозиториях Alpine) ---
say "Пакеты: python3 iw htop buffyboard kbd font-terminus networkmanager-cli"
apk add -q python3 iw htop buffyboard kbd font-terminus networkmanager-cli \
  || warn "apk add завершился с ошибкой — проверьте зеркала (apk update)"

# --- старая версия (скрипты bacon-*) ---
if [ $INIT = systemd ]; then
  for s in bacon-keys bacon-status; do
    if [ -e "/etc/systemd/system/$s.service" ]; then
      say "Удаление старой версии: $s"
      systemctl disable --now "$s.service" 2>/dev/null || true
      rm -f "/etc/systemd/system/$s.service"
    fi
  done
fi
rm -f /usr/local/bin/bacon-keys /usr/local/bin/bacon-status /usr/local/bin/bacon-wifi-join \
      /usr/local/bin/bacon-brightness /etc/systemd/logind.conf.d/50-bacon-powerkey.conf

# --- файлы ---
say "Установка файлов"
install -m 755 "$SRC/bin/nura-status" "$SRC/bin/nura-keys" "$SRC/bin/nura-wifi-join" \
  "$SRC/bin/nura-ctl" /usr/local/bin/
install -d -m 700 /root/.config/htop
install -m 644 "$SRC/config/htoprc" /root/.config/htop/htoprc
install -d /etc/sysctl.d /etc/modules-load.d /usr/local/share
echo "$VERSION" > /usr/local/share/nura-server-shell.version
if [ $INIT = systemd ]; then
  install -m 644 "$SRC/systemd/nura-status.service" "$SRC/systemd/nura-keys.service" /etc/systemd/system/
else
  install -m 755 "$SRC/openrc/nura-status" "$SRC/openrc/nura-keys" /etc/init.d/
fi
# мигание светодиода (триггер pattern)
if modprobe ledtrig-pattern 2>/dev/null; then
  echo ledtrig-pattern > /etc/modules-load.d/ledtrig-pattern.conf
fi

if [ $START = 0 ]; then
  say "Файлы установлены (версия $VERSION). Службы не включены — см. предупреждение выше."
  exit 0
fi

# --- кнопка питания: коротко — ничего, 5 с — перезагрузка ---
# Без этого logind/elogind по короткому нажатию выключит телефон, когда графика
# (которая перехватывала кнопку) отключена.
if [ $INIT = systemd ]; then
  install -d /etc/systemd/logind.conf.d
  install -m 644 "$SRC/config/50-nura-powerkey.conf" /etc/systemd/logind.conf.d/
else
  install -d /etc/elogind/logind.conf.d
  install -m 644 "$SRC/config/50-nura-powerkey.conf" /etc/elogind/logind.conf.d/
fi
echo 'kernel.printk = 3 4 1 3' > /etc/sysctl.d/50-console-quiet.conf
sysctl -q -p /etc/sysctl.d/50-console-quiet.conf || true

# --- графика ---
if [ -n "$GUI_SVC" ]; then
  for s in $GUI_SVC; do
    say "Отключение графики: $s"
    if [ $INIT = systemd ]; then
      systemctl disable --now "$s.service" 2>/dev/null || true
    else
      rc-update del "$s" default >/dev/null 2>&1 || true
      rc-service "$s" stop >/dev/null 2>&1 || true
    fi
  done
  [ $INIT = systemd ] && systemctl set-default -q multi-user.target
  warn "Вернуть графику: sudo ./uninstall.sh --restore-gui (или включить${GUI_SVC} вручную)"
fi

# --- tty1..tty5: табло, htop, консоль, меню, ввод пароля Wi-Fi — без обычного входа ---
if [ $INIT = systemd ]; then
  systemctl mask -q getty@tty2.service autovt@tty2.service autovt@tty3.service \
    autovt@tty4.service getty@tty5.service autovt@tty5.service
else
  # busybox init: getty на tty1..tty5 закомментировать (tty6 остаётся для входа)
  if grep -qE '^tty[1-5]::respawn:.*getty' /etc/inittab; then
    [ -e /etc/inittab.nura-orig ] || cp /etc/inittab /etc/inittab.nura-orig
    sed -i -E 's/^(tty[1-5]::respawn:.*getty.*)$/#nura# \1/' /etc/inittab
    kill -HUP 1                                    # init перечитывает inittab
    pkill -f 'getty 38400 tty[1-5]$' 2>/dev/null || true
  fi
fi

# --- запуск ---
if [ $INIT = systemd ]; then
  systemctl daemon-reload
  systemctl kill -s HUP systemd-logind 2>/dev/null || true
  systemctl enable -q nura-status.service nura-keys.service
  systemctl restart nura-status.service nura-keys.service
else
  pkill -HUP -x elogind-daemon 2>/dev/null || pkill -HUP -x elogind 2>/dev/null || true
  rc-update add nura-status default >/dev/null
  rc-update add nura-keys default >/dev/null
  rc-service nura-status restart >/dev/null 2>&1 || rc-service nura-status start
  rc-service nura-keys restart >/dev/null 2>&1 || rc-service nura-keys start
fi
sleep 2
for s in nura-status nura-keys; do
  if [ $INIT = systemd ]; then systemctl is-active -q "$s"; else rc-service "$s" status >/dev/null 2>&1; fi \
    && say "$s: работает" || warn "$s: не запустился (journalctl -u $s / /var/log/nura-keys.log)"
done
say "Готово ($VERSION). VOL+ дважды — меню, VOL+ и VOL- вместе — htop, VOL- дважды — консоль."
