# Lyrics harness

The redesign's lyrics view (`Redesigned/Lyrics/SGRKaraokeView.m`) playing a song on a clock of the
harness's own, so lines sung over each other, instrumental breaks, pronunciations and translations can
be looked at on the Mac without the phone. The songs are TTML read by the real `SGTTML.m`, or LRC timed
by the real estimate in `KaraokeTiming.m`.

    ./build.sh                  # this checkout; ./build.sh old builds HEAD's for a before and after, OPT=-O2 optimised
    xcrun simctl install <udid> build/new/LyricsHarness.app
    xcrun simctl launch <udid> com.vojta.lyricsharness.new -song duet -at 114000 -pauseAt 117600
    xcrun simctl io <udid> screenshot shot.png

`stubs.m` stands in for the player and the store: the position runs from `-at` at `-rate` and holds at
`-pauseAt` (for `-holdFor` seconds, then runs on). `main.m` lists every launch argument; the lyrics'
own settings are taken by their keys, e.g. `-spotifyglass.redesign.lyricsPronunciation 1`.
`-latencyMs 200` simulates a Bluetooth output delay in the presentation clock. Compare at `-rate 0.5`
and `-rate 2`, pause mid-word, then resume: the fill and word emphasis should stop together.

The fixtures are real TTML and LRC with every word swapped for filler of the same script and length
(`fixtures/anonymise.py`), so each keeps its song's timing and structure without its lyrics:

- `duet` two voices and a group over each other, three at once in places (from about 99 s)
- `romanised` Japanese with Apple's word timed pronunciation, backing rows, an 11 s break at 114.7 s
- `translated` Spanish with Apple's English translation and backing rows carried into it
- `both` Korean with both, and English lines the pronunciation leaves out
- `plain` line timed LRC, the words estimated, with a 13 s intro and a break after the first line
- `linetimed` TTML timed by the line only (BiniLyrics' line timed shape): two voices, two lines sung
  over each other at 42.4 s, a Hebrew line at 50.6 s, a 9 s break at 85.4 s, translations
- `spotify-line`, `spotify-static` Spotify's own color-lyrics JSON, LINE_SYNCED and UNSYNCED, read by
  the real `SGKaraokeLinesFromBody`; `static` plain text, as LRCLIB's plainLyrics
  (these four are written by `fixtures/linetimed.py` from `plain`'s timing)
- `rtl` (built in) right to left lines among left to right ones, a second voice, a break before the
  last line; `rtlx` the same with translations and a romanization
- `boundaries` synthetic word timing: a gap, identical starts, overlapping syllables, an 8ms word,
  and a sustained word ending after its container and after a later word. At 4.5s both lines should
  remain active, and the first line's sustained word should still be filling until 5.3s.

Lines timed by the line light up whole; `-spotifyglass.lyricsSimulateWords 1` sweeps them on the
estimate instead, as the Lyrics page's switch does. Untimed lyrics show every line lit, whatever `-at`.
Untimed `static` and `spotify-static`, and line-timed `linetimed` and `spotify-line`, must have no
word glow, including with simulated word timing enabled. Compare a word-timed fixture with
`-spotifyglass.redesign.lyricsGlow 0` and `1`: the fill should stay the same, with only the glow changing.
On a device, Mod Settings > Player > Lyrics > Lyrics glow applies immediately to both lyrics surfaces.
`-checkIslandLyrics 1` runs the real compact-Island text selector and exits with a result. It checks
word boundaries, gaps, seeking back, joined syllables, unspaced scripts, overlapping words, identical
starts, and line-timed/untimed fallbacks. Island text uses real word times only; estimated words
never make a line-timed song advance word by word.
`-islandOverlay 1` runs the foreground lyrics capsule over the harness with the real clock and
fixtures. On a portrait iPhone simulator, `-song boundaries -at 1000 -pauseAt 1200 -islandOverlay 1
-overlayChecksAt 2` checks safe-area placement, expanded/collapsed geometry, touch pass-through,
preservation of the app's key window, and cleanup. Verify Reduce Motion, large Dynamic Type, a
right-to-left fixture, rotation, foreground/background, and automatic expansion after a long break.
`-song spotify-line -spotifyglass.lyricsSimulateWords 1 -checkNoGlowAt 2` checks the actual word
views and layer shadow opacities, failing if any may glow. Repeat with `spotify-static`, and with
`boundaries -spotifyglass.redesign.lyricsGlow 0`; all three should report `no-glow check ... PASS`.

Run it on an iOS 26 or newer iPhone simulator, by UDID. The harness supplies a scene delegate so the
foreground overlay attaches to a real window scene. `-dumpTo PATH` writes the dump to a file, for when
`--console` shows nothing.

A real file goes in with `-file /path/song.ttml`: the simulator reads the Mac's paths.

`-perf LABEL` logs the view's per frame cost (its display link's `tick`) every 240 frames; run with
`simctl launch --console` to read it. `-dump 1` prints the lines as read, with their pronunciations and
translations, and quits. `-openMenu 3` opens the pronunciation and translation menu three seconds in,
`-toggleAt 3` switches both over as the menu would, and `-light 1` puts the window in light mode.

A screen recording catches the motion: `simctl io <udid> recordVideo -f run.mp4`, then e.g.
`ffmpeg -i run.mp4 -vf "fps=10,crop=1206:520:0:560,scale=233:-1,tile=12x1" -frames:v 1 strip.png`.

What it does not cover: Spotify's pages around the view (the player's stage is only its size, `-player 1`),
the lyrics arriving late or changing track, and the device's frame pacing.

Portable timing regressions use the renderer's actual `KaraokeMath.h`, with no Apple SDK:

    clang -std=c11 -Wall -Wextra -Werror timing.c -lm -o /tmp/lyrics-timing
    /tmp/lyrics-timing

On Windows, compile and link separately (omit `-lm`) with Clang and the Windows SDK. These checks
cover gaps, overlaps, duplicate starts, short/zero-duration words, Bluetooth delay, playback speed,
pauses, small seeks, stale frame timestamps and the gentle emphasis of short syllables; UIKit
rendering still needs the simulator or phone. With `boundaries`, the 8ms word should fill immediately
but its lift and glow should settle softly, with no snap at the end of the word.
