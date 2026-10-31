#!/bin/zsh
# Segment A: demo-mode station tour (isolated from other sessions, variants pinned). Segment B: live chimes via hooks.
set -u
S=/private/tmp/claude-501/-Users-hirakbanerjee/957e5f7e-a7b2-4ccf-b50f-17e85ab8ab69/scratchpad
APP=$HOME/RadioWave/build/dd/Build/Products/Debug/RadioWave.app
H=http://localhost:19847/hook
LOGA=$S/tourA.log; LOGB=$S/tourB.log; : > $LOGA; : > $LOGB
post() { curl -s -m 2 -o /dev/null -X POST "$H" -H 'Content-Type: application/json' -d "{\"hook_event_name\":\"$1\",\"session_id\":\"tour\",\"cwd\":\"/Users/hirakbanerjee/radiowave-tour\",\"tool_name\":\"${2:-}\"}"; }
openpop() { $S/haswin | grep -q OPEN || { osascript -e 'tell application "System Events" to tell process "RadioWave" to click menu bar item 1 of menu bar 2' >/dev/null; sleep 1.5; }; B=$($S/bounds); set -- ${=B}; PX=$1; PY=$2; PW=$3; PH=$4; }
audio_on() { for try in 1 2 3; do /usr/local/bin/cliclick c:$((PX+197)),$((PY+36)); sleep 1; screencapture -x -R$PX,$PY,$PW,$PH $S/pop_now.png; px=$(ffmpeg -v error -i $S/pop_now.png -vf "crop=90:30:350:57,scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p); r=$((16#${px:0:2})); g=$((16#${px:2:2})); [ $r -gt $g ] && { echo "audio on"; return; }; done; echo "AUDIO NOT ON"; }
btn() { case $1 in STATIC) x=49;; STANDBY) x=93;; THINKING) x=142;; "TOOL USE") x=192;; "ON AIR") x=240;; ERROR) x=280;; esac; /usr/local/bin/cliclick c:$((PX+x)),$((PY+307)); }

pkill -x RadioWave 2>/dev/null; sleep 1.5; defaults write com.hirakbanerjee.RadioWave forcedVariant -int 0; open "$APP"; sleep 5
openpop; echo "popover $PX $PY $PW $PH"; audio_on
btn STATIC; sleep 1.5          # enter demo mode first so the popover has its final (taller) size before recording
( $S/recwin $S/tourA.mov 75 RadioWave > $S/tourA_rec.log 2>&1 & )
echo "$(date +%s.%N) REC start" >> $LOGA; sleep 2
echo "$(date +%s.%N) STATIC|idle static — no session|between stations" >> $LOGA; sleep 4
btn STANDBY; echo "$(date +%s.%N) STANDBY|presence hiss + pilot tone|session connected, waiting" >> $LOGA; sleep 3.5
for v in 0 1 2; do
  defaults write com.hirakbanerjee.RadioWave forcedVariant -int $v
  case $v in 0) T="chord drone"; U="clockwork"; G="FM synthesis"; E="descending siren";;
             1) T="oceanic pad"; U="dialup modem"; G="music-box arpeggio"; E="digital glitch";;
             2) T="number station"; U="teletype"; G="pulsar"; E="";; esac
  btn THINKING;   echo "$(date +%s.%N) THINKING|$T|processing your prompt" >> $LOGA; sleep 4.5
  btn "TOOL USE"; echo "$(date +%s.%N) TOOL USE|$U|running a tool" >> $LOGA; sleep 4.5
  btn "ON AIR";   echo "$(date +%s.%N) ON AIR|$G|generating the response" >> $LOGA; sleep 4.5
  if [ $v -lt 2 ]; then btn ERROR; echo "$(date +%s.%N) ERROR|$E|error / signal lost" >> $LOGA; sleep 3.5; fi
  btn STANDBY;    echo "$(date +%s.%N) STANDBY|back on standby|turn finished" >> $LOGA; sleep 2.5
done
btn STATIC; echo "$(date +%s.%N) STATIC|idle static|no session" >> $LOGA; sleep 4
echo "$(date +%s.%N) REC end" >> $LOGA
for i in $(seq 1 40); do grep -q "^done" $S/tourA_rec.log 2>/dev/null && break; sleep 1; done; cat $S/tourA_rec.log

# Segment B — chimes (live mode: relaunch to leave demo mode)
pkill -x RadioWave 2>/dev/null; sleep 1.5; defaults write com.hirakbanerjee.RadioWave forcedVariant -int 0; open "$APP"; sleep 5
openpop; audio_on
( $S/recwin $S/tourB.mov 24 RadioWave > $S/tourB_rec.log 2>&1 & )
echo "$(date +%s.%N) REC start" >> $LOGB; sleep 2
post SessionStart;         echo "$(date +%s.%N) CHIME|session connect|SessionStart" >> $LOGB; sleep 3.5
post PreToolUse Bash; sleep 0.5; post PostToolUse Bash; echo "$(date +%s.%N) CHIME|tool complete|PostToolUse" >> $LOGB; sleep 3.5
post Stop;                 echo "$(date +%s.%N) CHIME|success|Stop" >> $LOGB; sleep 3.5
post PreToolUse Bash; sleep 0.5; post PostToolUseFailure Bash; echo "$(date +%s.%N) CHIME|failure|PostToolUseFailure" >> $LOGB; sleep 3.5
post Stop; sleep 1; post SessionEnd; echo "$(date +%s.%N) CHIME|session disconnect|SessionEnd" >> $LOGB; sleep 4
echo "$(date +%s.%N) REC end" >> $LOGB
for i in $(seq 1 30); do grep -q "^done" $S/tourB_rec.log 2>/dev/null && break; sleep 1; done; cat $S/tourB_rec.log
defaults delete com.hirakbanerjee.RadioWave forcedVariant 2>/dev/null
cat $LOGA; echo ===; cat $LOGB
