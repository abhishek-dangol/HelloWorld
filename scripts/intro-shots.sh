#!/bin/zsh
# Stills of the shutter intro in the simulator, held at set moments with the debug launch argument
# -introTime <seconds>. Optional photo (1-5) and title font (1-5) choices.
# Usage: scripts/intro-shots.sh <app path> <out dir> [photo] [font] [times...]
SIM=${SIM:-0AFE2D54-8941-41A5-BE21-CF0DEBC6E148}
APP=$1; OUT=$2; PHOTO=${3:-1}; FONT=${4:-1}; shift 4 2>/dev/null
TIMES=(${@:-0.7 1.4 1.8 2.2 3.0 3.4 5})
mkdir -p "$OUT"
BID=com.abhishekdangol.CinematiCam
[ -n "$APP" ] && [ "$APP" != "-" ] && xcrun simctl install $SIM "$APP"
for t in $TIMES; do
  xcrun simctl launch --terminate-running-process $SIM $BID -welcomePage 0 -skipIntro NO \
    -introTime $t -introPhoto $PHOTO -introFont $FONT >/dev/null
  python3 -c "import time; time.sleep(3.5)"
  xcrun simctl io $SIM screenshot "$OUT/t$t-p$PHOTO-f$FONT.png" >/dev/null 2>&1
done
ls "$OUT"
