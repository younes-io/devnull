#!/usr/bin/env bash
# Cuts a take from take.sh into the promo: a title card, the take with captions, an install card.
# The recorder catches about 43 fps while the logo drifts, so those stretches are motion-interpolated
# to 60 in parallel one-second chunks; the rest only repeats frames.
#   edit.sh TAKE.mkv OUT_DIR
set -euo pipefail

take=${1:?usage: edit.sh TAKE.mkv OUT_DIR}
out=${2:?usage: edit.sh TAKE.mkv OUT_DIR}
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$out/work
mkdir -p "$work"

# Recording seconds for take 3: the answer, then /screensaver typed, drift, workspace 4, drift again, Esc.
# blur=X:Y:W:H hides other people's posts on dev-null.sh.
segments="
answer 1.90 7.00 repeat
command 16.30 18.15 repeat
drift 18.15 25.961 interpolate
away 25.961 29.40 repeat blur=1200:150:1300:2010
back 29.40 33.92 interpolate
esc 33.92 34.02 repeat
"
hold=2.5

calc() { awk "BEGIN { printf \"%.3f\", $* }"; }
frames() { awk "BEGIN { printf \"%d\", ($*) * 60 + 0.5 }"; }
range=scale=out_range=tv,format=yuv420p
x264=(-c:v libx264 -preset veryfast -crf 6 -an)

# Finished pieces are kept, so a rerun redoes only what was deleted.
# Seeks start three seconds early because the recorder writes a frame only when the screen changes.
repeat() {
  local file=$1 from=$2 to=$3 margin blur=
  [ -s "$file" ] && return
  if [[ ${4:-} == blur=* ]]; then
    IFS=: read -r x y w h <<<"${4#blur=}"
    blur="split[m][c];[c]crop=$w:$h:$x:$y,boxblur=48:3[b];[m][b]overlay=$x:$y,"
  fi
  margin=$(calc "$from < 3 ? $from : 3")
  ffmpeg -v error -y -ss "$(calc "$from - $margin")" -t "$(calc "$to - $from + $margin + 1")" -i "$take" \
    -vf "fps=60:start_time=0,trim=start=$margin,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=$(frames "$to - $from"),$blur$range" \
    "${x264[@]}" "$file"
}

interpolate() {
  local file=$1 from=$2 to=$3 count
  [ -s "$file" ] && return
  count=$(frames "$to - $from")
  ffmpeg -v error -y -ss "$(calc "$from - 0.5")" -t "$(calc "$to - $from + 1")" -i "$take" \
    -vf "minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1,trim=start=0.5,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=$count,$range" \
    "${x264[@]}" "$file"
}

: >"$work/body.txt"
pids=()
while read -r name from to mode extra; do
  [ -n "$name" ] || continue
  if [ "$mode" = repeat ]; then
    repeat "$work/$name.mkv" "$from" "$to" "$extra" &
    pids+=($!)
    echo "file '$name.mkv'" >>"$work/body.txt"
    continue
  fi
  chunks=$(awk "BEGIN { print int(($to - $from) - 0.001) + 1 }")
  for ((k = 0; k < chunks; k++)); do
    start=$(calc "$from + $k")
    end=$(calc "$from + $k + 1 < $to ? $from + $k + 1 : $to")
    interpolate "$work/$name.$k.mkv" "$start" "$end" &
    pids+=($!)
    echo "file '$name.$k.mkv'" >>"$work/body.txt"
  done
done <<<"$segments"
for pid in "${pids[@]}"; do wait "$pid"; done
ffmpeg -v error -y -f concat -safe 0 -i "$work/body.txt" -vf "tpad=stop_mode=clone:stop_duration=$hold" "${x264[@]}" "$work/body.mkv"

wordmark() { # X Y WIDTH
  printf '<svg x="%s" y="%s" width="%s" height="%s" viewBox="0 -0.55 5.6577 1.1">' "$1" "$2" "$3" "$(calc "$3 * 1.1 / 5.6577")"
  sed '1d;$d' "$root/assets/wordmark.svg" | sed 's/{ink}/#ececec/g; s/{accent}/#ff8a4c/g'
  echo '</svg>'
}
mono='font-family="JetBrainsMono Nerd Font"'

card() { # NAME then SVG body on stdin
  { echo "<svg xmlns='http://www.w3.org/2000/svg' width='3840' height='2160'><rect width='3840' height='2160' fill='#121212'/>"; cat; echo '</svg>'; } >"$work/$1.svg"
  rsvg-convert -w 3840 -h 2160 "$work/$1.svg" -o "$work/$1.png"
}

{
  wordmark 1020 860 1800
  echo "<text x='1920' y='1420' text-anchor='middle' $mono font-size='64' fill='#8a8a8a'>a screensaver for claude code</text>"
} | card intro

install='/plugin install screensaver --marketplace younes-io/devnull'
{
  wordmark 1470 560 900
  printf "<rect x='%s' y='1060' width='%s' height='150' rx='28' fill='#1c1c1c' stroke='#2a2a2a' stroke-width='3'/>" "$(calc "1920 - (${#install} * 31.2 + 200) / 2")" "$(calc "${#install} * 31.2 + 200")"
  echo "<text x='1920' y='1154' text-anchor='middle' $mono font-size='52' fill='#ececec'><tspan fill='#ff8a4c'>›</tspan> $install</text>"
  echo "<text x='1920' y='1420' text-anchor='middle' $mono font-size='56' fill='#ff8a4c'>github.com/younes-io/devnull</text>"
} | card outro

# A caption is a dark pill near the bottom edge; a leading "esc" draws as a keycap.
caption() { # NAME TEXT [KEY]
  local text=$2 key=${3:-} w kw=0
  [ -n "$key" ] && kw=$(calc "${#key} * 33.6 + 110")
  w=$(calc "${#text} * 33.6 + 140 + $kw")
  {
    echo "<svg xmlns='http://www.w3.org/2000/svg' width='$w' height='150'>"
    echo "<rect width='$w' height='150' rx='40' fill='#0e0e0e' fill-opacity='0.86' stroke='#ffffff' stroke-opacity='0.08' stroke-width='3'/>"
    if [ -n "$key" ]; then
      echo "<rect x='56' y='30' width='$(calc "$kw - 40")' height='90' rx='16' fill='#ececec'/><rect x='56' y='110' width='$(calc "$kw - 40")' height='10' rx='5' fill='#9a9a9a'/>"
      echo "<text x='$(calc "56 + ($kw - 40) / 2")' y='90' text-anchor='middle' $mono font-weight='bold' font-size='50' fill='#121212'>$key</text>"
    fi
    echo "<text x='$(calc "70 + $kw")' y='95' $mono font-size='56' fill='#ececec'>$text</text></svg>"
  } >"$work/$1.svg"
  rsvg-convert "$work/$1.svg" -o "$work/$1.png"
}
caption c1 'covers its terminal. nothing else.'
caption c2 'switch workspaces. it stays put.'
caption c3 'come back. still drifting.'
caption c4 "you're back." esc

# Body seconds for each caption: start, end.
captions="c1 7.6 14.5
c2 15.0 18.0
c3 18.4 22.2
c4 22.3 25.3"

intro=3 outro=4.5 fade=0.5
body=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/body.mkv")
inputs=(-loop 1 -framerate 60 -t "$intro" -i "$work/intro.png" -i "$work/body.mkv" -loop 1 -framerate 60 -t "$outro" -i "$work/outro.png")
graph="[1:v]setpts=PTS-STARTPTS[b0];"
n=3
while read -r name from to; do
  inputs+=(-loop 1 -framerate 60 -t "$(calc "$to - $from")" -i "$work/$name.png")
  graph+="[$n:v]format=rgba,fade=t=in:d=0.35:alpha=1,fade=t=out:st=$(calc "$to - $from - 0.35"):d=0.35:alpha=1,setpts=PTS-STARTPTS+$from/TB[o$n];"
  graph+="[b$((n - 3))][o$n]overlay=x=(W-w)/2:y=H-h-150:eof_action=pass[b$((n - 2))];"
  n=$((n + 1))
done <<<"$captions"
graph+="[0:v]format=yuv420p,fade=t=in:d=0.6[i];[2:v]format=yuv420p,fade=t=out:st=$(calc "$outro - 0.8"):d=0.8[e];"
graph+="[b$((n - 3))]settb=1/60[bt];[i][bt]xfade=transition=fade:duration=$fade:offset=$(calc "$intro - $fade")[ib];"
graph+="[ib][e]xfade=transition=fade:duration=0.6:offset=$(calc "$intro - $fade + $body - 0.6"),format=yuv420p[v]"
ffmpeg -v error -y "${inputs[@]}" -filter_complex "$graph" -map '[v]' \
  -c:v libx264 -preset slow -crf 14 -profile:v high -pix_fmt yuv420p \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -movflags +faststart "$out/devnull-screensaver.mp4"

# The README loop: from /screensaver to the restored session, at 1280 wide.
ffmpeg -v error -y -ss "$(calc "$intro - $fade + 5.1")" -t 20.2 -i "$out/devnull-screensaver.mp4" \
  -vf "fps=30,scale=1280:-1:flags=lanczos" -c:v libwebp_anim -q:v 80 -compression_level 6 -loop 0 "$out/hero.webp"
