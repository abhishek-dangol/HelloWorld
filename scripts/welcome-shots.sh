#!/bin/zsh
# Screenshots of the welcome screens in the simulator: the shutter intro at several moments,
# then each of the 5 pages after its pieces have come in.
# Usage: scripts/welcome-shots.sh <app path> <out dir>
SIM=${SIM:-0AFE2D54-8941-41A5-BE21-CF0DEBC6E148}
APP=$1; OUT=$2; mkdir -p "$OUT"
BID=com.abhishekdangol.CinematiCam
xcrun simctl install $SIM "$APP"
# Shutter intro, held still at set openings with the debug launch argument -introFreeze (above 1 = finished screen)
for o in 0.001 0.2 0.55 1 2; do
  xcrun simctl launch --terminate-running-process $SIM $BID -welcomePage 0 -skipIntro NO -introFreeze $o >/dev/null
  python3 -c "import time; time.sleep(6)"
  xcrun simctl io $SIM screenshot "$OUT/i$o.png" >/dev/null 2>&1
done
for p in 0 1 2 3 4; do
  xcrun simctl launch --terminate-running-process $SIM $BID -welcomePage $p -skipIntro YES >/dev/null
  python3 -c "import time; time.sleep(5)"
  xcrun simctl io $SIM screenshot "$OUT/p$p.png" >/dev/null 2>&1
done
ls "$OUT"
