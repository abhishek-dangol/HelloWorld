# Brief: welcome intro v2 (started 2026-11-19 12:42 CT, ~15-30 min)
Target: first welcome screen (shutter intro). User words: "The shutter should be more detailed... add some more flaps... It should be closed in the beginning and then open. Use a different image than the same woman... look some nice pictures up and let me know... ideally a person. ... text animations for cinematic cam. Maybe use a different font. ... look at what the top apps do... 21st.dev or Mobbin... be really creative."
Rules: only the intro screen changes. Photos only from Unsplash/Pexels (free commercial licence). No scale animation on text. iOS 16.6 target.
Deliverable: simulator screenshots (closed, opening, open, title mid-animation, final) + photo choices A-E + font choices. No install, no commit.
Harness: scripts/welcome-shots.sh style; debug args -introTime (seconds), -introPhoto N, -introFont N. Critics = fresh subagents, defects only.
Bar: critic median >= 8/10 on "premium, cinematic, detailed"; no clipped/overlapping text.
