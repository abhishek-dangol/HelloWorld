# Rounds: research + proposals

## Decisions
- Prior intro-v2 run archived to cook-archive/2026-11-19-intro-v2.

## r01 (13:19-13:29 CT)
- Research: 3 agents (complaints: evidence thin, no Reddit/App Store text; filter-picker patterns; stabilization + smoothing tech).
- Code read (no changes): normal video stabilization = lowLatency (iOS 26) / standard; selfie+blur+4K = standard; Enhanced = cinematicExtendedEnhanced, blur off. Skin smoothing = MTIHighPassSkinSmoothing on whole frame when a face is seen; createFaceMask never called; RetouchSettingsView never shown. Looks tiles use AI pink sample image.
- Built in scratchpad only: look tiles from the app's real filter code on real photos; face-only smoothing prototype on stills (Vision landmarks mask, eyes/brows/lips excluded, 20% fine detail added back).
- Critics r1: smoothing differences invisible at phone size + proposed grainy -> close-ups only, texture 50%->20%. Tiles too small/alike, A caption implied owner's face, E "Film" repeated -> Up-close strip, captions fixed, group renamed Vintage.
- Sheets: scratchpad/deliver2/1-3. Critics r2 running.

## r02
- Critics r2: looks sheet captions/spacing fixed. Smoothing sheet: critic MEASURED only 2-3/255 difference and ~3% eye-edge drop on the stock stills, so before/after claims were overstated; texture add-back read as sharpening. Replaced with a "where smoothing applies" map (today = whole frame, proposed = skin only, eyes/brows/lips cut out) + the Nov 16 phone measurement (12-15% face sharpness loss). Other-ideas wording de-jargoned, mockups given a record button, alert reworded.
- Delivered scratchpad/deliver2/1-3. Stopped for the user's pick.
