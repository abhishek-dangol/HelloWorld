# Proposals 2026-11-19 (research only, nothing built)
Evidence on complaints was thin (no Reddit/App Store text reachable). Sources in scratchpad notes; summary here.

## Findings
- Native Camera: most-heard complaint = iOS 26 redesign hides controls; also recordings cutting off / lost or corrupt clips; soft front video after 26.0.1 (anecdotal).
- TikTok/Instagram cameras: mostly upload recompression; TikTok camera believed to add a beauty filter by default; creators told to film in the native camera and upload.
- Creator gaps: reading a script while keeping eye contact; lost takes; script/record/captions split over several apps.
- Stabilization: our normal video uses `lowLatency` (iOS 26), which an Apple engineer called the closest public match to the Camera app; selfie+blur+4K uses `standard` (soft-face fix 11-16); Enhanced uses cinematicExtendedEnhanced (steadiest public mode) but turns blur off. Action mode has no public API. Never measured side by side.
- Skin smoothing: MTIHighPassSkinSmoothing on the WHOLE frame whenever a face is seen; createFaceMask exists but is never called; eyes/lips/brows not protected; earlier measure ~12-15% sharpness loss. RetouchSettingsView (presets, glow, warmth, edge, face area) is never shown.
- Looks panel: 72pt tiles all show FilterSample = AI-drawn pink glitter woman.

## Proposals
1. Skin smoothing upgrade: face-only mask from face points, eyes/brows/lips/beard/hair/background sharp, add back fine texture. Prototype on stills: smooth/sheet. Phone speed unmeasured.
2. Looks tiles A-E (icons-A-E.png): A live own face, B split before/after, C swipe on picture + round previews, D film-roll boxes with face window, E groups + one-line hint.
3. Stabilization walking test vs native Camera (no code), then decide.
4. Teleprompter follows your voice.
5. Mid-recording phone call / app closed test; visible Saved check.
