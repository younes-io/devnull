#!/usr/bin/env bash
# Records the PROMO output through a private screen-share portal until DIR/recorder.pid gets SIGINT.
# Hyprland's shared-memory screencopy tops out near 30 fps on NVIDIA; the portal hands over GPU buffers.
# A scripted picker answers PROMO, and the private D-Bus session keeps your own portal untouched.
#   record.sh DIR OUT.mkv
set -euo pipefail

dir=${1:?usage: record.sh DIR OUT.mkv}
out=${2:?usage: record.sh DIR OUT.mkv}

if [ -z "${PROMO_PORTAL:-}" ]; then
  mkdir -p "$dir/portal/hypr"
  printf '#!/bin/sh\necho "[SELECTION]/screen:PROMO"\n' >"$dir/portal/pick"
  chmod +x "$dir/portal/pick"
  printf 'screencopy {\n    max_fps = 60\n    custom_picker_binary = %s\n}\n' "$dir/portal/pick" >"$dir/portal/hypr/xdph.conf"
  exec env PROMO_PORTAL=1 XDG_CONFIG_HOME="$dir/portal" dbus-run-session -- "$0" "$@"
fi

/usr/lib/xdg-desktop-portal-hyprland >/dev/null 2>&1 &
portals=$!
sleep 0.5
/usr/lib/xdg-desktop-portal -r >/dev/null 2>&1 &
portals="$portals $!"
# The portal segfaults when its bus goes away, and the desktop toasts every core dump; SIGKILL leaves none.
trap 'kill -KILL $portals' EXIT
sleep 1
gpu-screen-recorder -w portal -f 60 -fm content -k hevc -bm qp -q ultra -tune quality -cr full -cursor no -o "$out" &
echo $! >"$dir/recorder.pid"
wait $!
