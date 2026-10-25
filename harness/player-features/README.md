# Playback rules, lyric cards and visualizer

On a Mac with Xcode, run `sh harness/player-features/build.sh`, then install and launch
`harness/player-features/build/PlayerFeatures.app` on an arm64 iOS simulator
(`com.vojta.playerfeatures`). No Spotify binary or account is needed. Launch logs assert rule
matching, cross-release version identity, duplicate removal, the master switch, exact expiry,
and rejection of malformed backup entries. The real renderer writes nine PNGs into Documents
for checking all three styles with Latin, Arabic and Japanese text, and checks fixed export size,
missing artwork and overflow. The app exposes the actual editor, rules page and visualizer settings.
Its test-only audio source feeds a 440 Hz sine wave into the actual visualizer queue.

The portable analyzer runs on Windows, Linux or macOS: `sh harness/visualizer/build.sh`.
On Windows compile `main.c` and `SGSpectrum.m` as C11 into separate object files with clang,
then link and run. It tests silence, nonfinite input, complete windows, remainder preservation,
sample-rate changes and 28 spectral peak cases.

Device verification on Spotify 9.1.78:

- In each look, open the player's ⋯ menu and add an exact track rule. Check that the song advances
  once, including with the player closed. Remove the rule in Player > Playback rules and replay.
- Add a version rule for a live/remix track. Verify that the same titled version on a reissue is
  skipped, but its studio version and another artist with the same title play normally.
- Add a 30-day break. Check its expiry date, removal and the master switch. An all-blocked queue
  should pause after 12 skips in 15 seconds rather than loop indefinitely.
- Create a lyric card from the player menu and from Player > Lyrics. Select/deselect lines,
  switch styles, share/save the image and check 1080 × 1350 dimensions. Try no lyrics, no artwork,
  long lines, a large Dynamic Type size, RTL text, and iPad share-sheet anchoring. Change the
  playing song with headphones while the editor is open; its captured song and lines must remain.
- In the redesign, enable Player > Now playing > Music visualizer with Music Haptics **off**.
  Try both styles and intensity, silence, pause/resume, track changes, Bluetooth route changes,
  opening/dismissing/cancelling dismissal of the player, background/foreground, Low Power Mode,
  and Reduce Motion. Check it stops off screen, has no fabricated activity for remote Connect,
  and the player's 120 Hz transition stays smooth. Disable it and verify the existing background
  and Music Haptics still work independently.

The Windows workspace can run the portable analyzer and layer checker; simulator assertions,
PNG visual review, and Spotify/device checks require Apple's toolchain and are not claimed by
those portable checks.
