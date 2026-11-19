# Rounds
r01 06:21 new OKLab engine (GradeLook), first set. Too timid vs Crisp; blacks greyish.
r02 06:24 measured: Crisp is the only look with true blacks (1% black 0.000). Added deep-blacks toe, contrast up.
r03 06:26 tints x1.8. Warm looks turned blue skies cream.
r04 06:28 sky protection. Critic 1: median ~5/10; clusters of near-duplicates (warm, pink, faded); Pop/Punch = Crisp.
r05 06:31 redesign for distinct identities; Blush->Fresh (Fuji 400H), Sunny->Neon (CineStill 800T); skin range widened (OKLab hue 62 +-30).
Decisions: kept 24 slots; removed grain from Summer/B&W/Retro (critic saw speckle); tables built in background at launch.
r06 critic 2: median ~6. Pale hazy sky picks up tints.
r07 clean-white protection (near-white low-chroma ignores tints). Installed on phone ~06:33 as checkpoint. Critic 3: ~5.5.
r08 bloom edge-darkening fixed (clampedToExtent). Critic 4: ~6.
r09 critic 5: ~6; best Summer/Noir 8, Cinema/Sunset/Rosy/Warm/B&W 7; weakest Moody, Punch, Airy, Antique, Frost, Pop.
r10 06:39 reworked weakest: Punch deep vivid, Pop bright colourful, Moody dark rich, Airy deeper blacks, skin protect 0.95 on cool looks, Antique saturation 0.4, Dreamy pinker, Retro plum shadows.
r10 critic 6: median 5 (harsh); Punch/Pop alike, warm cluster, Fresh~Glow.
r11 Rosy less fade, Fresh minty (no pink), Neon less teal, Punch deeper (skin 0.75), Pop brighter. Critic 7: 5.5.
   Measured 10th-percentile darks: soft looks are DARKER than Crisp (0.13-0.18 vs 0.18) -> "grey/milky" = low colour, not lifted blacks.
r12 vibrance on Rosy/Airy/Frost/Moody; Neon sky less cyan; Retro less yellow; Dreamy bloom 0.45; Pop candy hues (turquoise, lime). Critic 8: 5.5, Pop 8.
r13 Frost livelier, Neon gentler, Retro vibrance, Film cleaner. Critic 9: 6.
r14 Antique stronger sepia, Neon brighter highlights. Critic 10: 6.
r15 06:47 new `halation` (red glow round brightest spots, screen blend; additive blend blew everything to white) on Neon. 4K: Neon 1.6 ms.
   Installed on phone 06:48 (launch blocked: phone locked). Before/after grids sent. STOPPED: waiting for user to say proceed.
Open: critics plateau at ~6 on thumbnails of an AI portrait; real skin + live camera never checked. Clusters still flagged: Warm/Golden/Summer, B&W/Noir, Retro/Antique, Frost/Cool.
