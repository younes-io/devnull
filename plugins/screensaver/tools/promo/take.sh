#!/usr/bin/env bash
# Records one take on the stage built by stage.sh through record.sh, and writes when
# each beat started to OUT.marks for edit.sh.
#   take.sh DIR OUT.mkv
set -euo pipefail

dir=${1:?usage: take.sh DIR OUT.mkv}
out=${2:?usage: take.sh DIR OUT.mkv}
marks=${out%.*}.marks

say() { printf '%s\n' "$1" >"$dir/ctl"; }

# Hyprland focuses the monitor whose workspace changes, so hand focus straight back to wherever you are.
show() {
  local active
  active=$(hyprctl activewindow -j | jq -r .address)
  hyprctl eval "hl.get_monitor('PROMO'):set_workspace({ workspace = '$1' }); hl.dispatch(hl.dsp.focus({ window = 'address:$active' }))" >/dev/null
}

mark() { awk -v start="$start" -v now="$EPOCHREALTIME" -v beat="$1" 'BEGIN { printf "%.2f %s\n", now - start, beat }' >>"$marks"; }

show 3
sleep 1
: >"$marks"
"$(dirname "$0")/record.sh" "$dir" "$out" </dev/null >"${out%.*}.log" 2>&1 &
recorder=$!
start=$EPOCHREALTIME
sleep 4

mark ask
say 'explain /dev/null in one line'
sleep 0.6
say '\r'
sleep 14

mark command
say '/screensaver'
sleep 1.2
say '\r'
mark saver
sleep 8

mark away
show 4
sleep 3.5

mark back
show 3
sleep 4.5

# Esc reaches the screensaver only through its own keyboard focus; SIGTERM runs the same exit path.
mark esc
ps -C python3 -o pid=,args= | awk '/screensaver\.py/ {print $1}' | xargs -r kill
sleep 4

mark end
kill -INT "$(cat "$dir/recorder.pid")"
wait "$recorder"
