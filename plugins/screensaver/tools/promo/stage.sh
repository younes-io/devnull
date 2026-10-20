#!/usr/bin/env bash
# Builds the promo stage on a headless 4K output named PROMO, far above the real monitors.
# Workspace 3 holds Claude Code (typed into through driver.py) beside nvim; workspace 4 holds dev-null.sh.
#   stage.sh DIR
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
dir=${1:?usage: stage.sh DIR}
mkdir -p "$dir/chromium"
[ -p "$dir/ctl" ] || mkfifo "$dir/ctl"

hyprctl monitors -j | jq -e 'any(.name == "PROMO")' >/dev/null || hyprctl output create headless PROMO >/dev/null
hyprctl eval 'hl.monitor({ output = "PROMO", mode = "3840x2160@60", position = "0x-6000", scale = 2 })' >/dev/null
for workspace in 3 4; do
  hyprctl eval "hl.workspace_rule({ workspace = '$workspace', monitor = 'PROMO', persistent = true })" >/dev/null
done

open() {
  hyprctl dispatch "hl.dsp.exec_cmd([[$2]], { workspace = '$1 silent' })" >/dev/null
  sleep 2
}
open 3 "ghostty --class=promo.claude --font-size=14 --working-directory=$root -e /usr/bin/python3 -I $root/tools/promo/driver.py $dir/ctl claude"
open 3 "ghostty --class=promo.code --font-size=14 --working-directory=$root -e nvim bin/screensaver.py"
open 4 "chromium --user-data-dir=$dir/chromium --no-first-run --no-default-browser-check --app=https://dev-null.sh"
