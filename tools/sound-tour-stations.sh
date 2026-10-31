#!/bin/zsh
set -u
S=/private/tmp/claude-501/-Users-hirakbanerjee/957e5f7e-a7b2-4ccf-b50f-17e85ab8ab69/scratchpad
APP=$HOME/RadioWave/build/dd/Build/Products/Debug/RadioWave.app
LOGA=$S/tourA.log; : > $LOGA
openpop() { $S/haswin | grep -q OPEN || { osascript -e 'tell application "System Events" to tell process "RadioWave" to click menu bar item 1 of menu bar 2' >/dev/null; sleep 1.5; }; B=$($S/bounds); set -- ${=B}; PX=$1; PY=$2; PW=$3; PH=$4; ROWY=$((PH-64)); }
pill() { screencapture -x -R$PX,$PY,$PW,$PH $S/pill_now.png; ffmpeg -v error -i $S/pill_now.png -vf "crop=260:45:60:105,scale=1:1:flags=area" -f rawvideo -pix_fmt rgb24 - | python3 -c "
import sys,colorsys; b=sys.stdin.buffer.read(); r,g,bl=[x/255 for x in b[:3]]; h,s,v=colorsys.rgb_to_hsv(r,g,bl); h*=360
print('STATIC' if s<0.18 else 'ERROR' if (h<15 or h>330) else 'THINKING' if h<60 else 'ON AIR' if 90<=h<165 else 'TOOL USE' if 165<=h<200 else 'STANDBY' if 200<=h<260 else '?')"; }
audio_on() { for try in 1 2 3; do /usr/local/bin/cliclick c:$((PX+197)),$((PY+36)); sleep 1; screencapture -x -R$PX,$PY,$PW,$PH $S/pop_now.png; px=$(ffmpeg -v error -i $S/pop_now.png -vf "crop=90:30:350:57,scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p); r=$((16#${px:0:2})); g=$((16#${px:2:2})); [ $r -gt $g ] && { echo "audio on"; return; }; done; echo "AUDIO NOT ON"; }
btn() { case $1 in STATIC) x=49;; STANDBY) x=93;; THINKING) x=142;; "TOOL USE") x=189;; "ON AIR") x=240;; ERROR) x=280;; esac
        for try in 1; do /usr/local/bin/cliclick c:$((PX+x)),$((PY+ROWY)); sleep 0.45; p=$(pill); [ "$p" = "$1" ] && { echo "$(date +%s.%N) $1|$2|$3" >> $LOGA; return 0; }; done
        echo "$(date +%s.%N) $1|$2|$3 (UNVERIFIED, saw $p)" >> $LOGA; return 1; }

pkill -x RadioWave 2>/dev/null; sleep 1.5; defaults write com.hirakbanerjee.RadioWave forcedVariant -int 0; open "$APP"; sleep 5
openpop; echo "popover $PX $PY $PW $PH"; audio_on
btn STATIC "idle static — no session" "between stations"; sleep 1.5
( $S/recwin $S/tourA.mov 82 RadioWave > $S/tourA_rec.log 2>&1 & )
echo "$(date +%s.%N) REC start" >> $LOGA; sleep 2
echo "$(date +%s.%N) STATIC|idle static — no session|between stations" >> $LOGA; sleep 4
btn STANDBY "presence hiss + pilot tone" "session connected, waiting"; sleep 3.5
for v in 0 1 2; do
  defaults write com.hirakbanerjee.RadioWave forcedVariant -int $v
  case $v in 0) T="chord drone"; U="clockwork"; G="FM synthesis"; E="descending siren";;
             1) T="oceanic pad"; U="dialup modem"; G="music-box arpeggio"; E="digital glitch";;
             2) T="number station"; U="teletype"; G="pulsar"; E="";; esac
  btn THINKING "$T" "processing your prompt"; sleep 4.5
  btn "TOOL USE" "$U" "running a tool"; sleep 4.5
  btn "ON AIR" "$G" "generating the response"; sleep 4.5
  if [ $v -lt 2 ]; then btn ERROR "$E" "error / signal lost"; sleep 3.5; fi
  btn STANDBY "back on standby" "turn finished"; sleep 2.5
done
btn STATIC "idle static" "no session"; sleep 4
echo "$(date +%s.%N) REC end" >> $LOGA
for i in $(seq 1 40); do grep -q "^done" $S/tourA_rec.log 2>/dev/null && break; sleep 1; done; cat $S/tourA_rec.log; cat $LOGA
