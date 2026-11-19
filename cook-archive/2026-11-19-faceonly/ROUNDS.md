# Rounds
## fm01 13:55
Mask from Vision landmarks: face outline + forehead half-oval along the face's own up direction; eyes/brows/lips cut out (fill + stroke). Aligned correctly through the sideways round trip on 7/10 stock photos.
## fm02 13:58
Landmark request alone missed a close-up face that the old face finder catches: now face finder first, landmarks on its boxes. 8/10 found (the 2 misses are also missed by the old finder). Forehead height 0.85 -> 0.7.
## fm03 14:02
Wired into app (video per stream, every 3 frames, one search at a time; photo uses the still itself). Sim build OK. Visual + code critics launched.
## fm04 14:08
Visual critic (eye only, shrunken strips): "smoothing weaker than TODAY on cheeks" (d 4-5/10). Measured: where the map is full, NEW == TODAY exactly (diff 0.00); the real cause was the wide soft edge reaching into the cheeks (edge zone bigger than full zone). Fix: outline grown by 4x softness before blurring, softness 0.045 -> 0.03 of face width, brows cut 0.05 -> 0.06. Full-strength area +25-45%. Camera change now forgets the map. Not fixed (as today): hands touching the face, beard edge.
## fm05-06 14:06
Code critic: no crashes/races/flips; `undone` right for all 8 orientations. Fixed: mask grey values went through colour management (soft edges came out stronger) -> plain no-colour context; mask grows with small faces (220 px face, max 1536); one missed search no longer blinks smoothing off (last face kept 0.4 s, never older); camera change bumps a generation so late searches are thrown away; eye cut-outs 0.07 -> 0.09; search on a shrunk picture: 720 lost a face on stock, 1280 finds all the same faces as full size (Mac search time unchanged by size). Not done: phone held sideways (app has no orientation reading), buffer held during search (as before), brightness/warmth settings still whole-frame (out of scope). Sim build OK 14:06.
## Critic round 2 (eye only) 14:06
Scores a7 b8 c8 d6. "Cheeks less smoothed than TODAY" again: refuted by measurement (NEW == TODAY wherever the map is full, diff 0.00). "Older woman's lower cheek outside map": checked full size, it is covered. Beard edge / hands / forehead into hairline: known limits, the filter's own skin-colour check still applies there. Stopped at 14:07 (16 min), sheet sent, not on the install link.
