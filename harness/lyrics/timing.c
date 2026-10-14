// Portable regression checks against the same math the UIKit renderer and player clock use.
// clang -std=c11 -Wall -Wextra -Werror harness/lyrics/timing.c -lm -o /tmp/lyrics-timing
#include "../../tweak/Sources/Shared/Lyrics/KaraokeMath.h"
#include <assert.h>
#include <stdio.h>

static void near(double actual, double expected) { assert(fabs(actual - expected) < 0.000001); }

int main(void) {
    // A syllable finishes at its own end, holding white through a gap before the next word.
    near(SGKaraokeWordProgress(999, 1000, 1200), 0);
    near(SGKaraokeWordProgress(1100, 1000, 1200), 0.5);
    near(SGKaraokeWordProgress(1200, 1000, 1200), 1);
    near(SGKaraokeWordProgress(1600, 1000, 1200), 1);
    near(SGKaraokeWordProgress(1600, 1800, 2000), 0);
    // Same starts, overlaps and a word sustained past the next one's end are independent.
    near(SGKaraokeWordProgress(1100, 1000, 1400), 0.25);
    near(SGKaraokeWordProgress(1300, 1000, 1400), 0.75);
    near(SGKaraokeWordProgress(1300, 1100, 1200), 1);
    near(SGKaraokeWordProgress(999, 1000, 1000), 0);
    near(SGKaraokeWordProgress(1000, 1000, 1000), 1);
    near(SGKaraokeWordProgress(1000, 1000, 900), 1);
    // A short word is fully visible on the next frame even if no frame lands inside its span.
    near(SGKaraokeWordProgress(1016, 1000, 1008), 1);
    // Visual emphasis eases independently: short syllables must not squeeze motion into 8ms.
    near(SGKaraokeWordEmphasis(1000, 1000, 1008), 0);
    assert(SGKaraokeWordEmphasis(1008, 1000, 1008) < 0.01);
    assert(SGKaraokeWordEmphasis(1140, 1000, 1008) > 0.3);
    near(SGKaraokeWordEmphasis(1388, 1000, 1008), 0);
    near(SGKaraokeWordEmphasis(1140, 1000, 2000), 0.5);
    near(SGKaraokeWordEmphasis(1280, 1000, 2000), 1);
    near(SGKaraokeWordEmphasis(2190, 1000, 2000), 0.5);
    near(SGKaraokeWordEmphasis(2380, 1000, 2000), 0);
    // Seeking back before the word resets the effect.
    near(SGKaraokeWordEmphasis(990, 1000, 2000), 0);
    for (int ms = 900; ms <= 2500; ms++) {
        double effect = SGKaraokeWordEmphasis(ms, 1000, 1008);
        assert(effect >= 0 && effect <= 1);
        // No single 120Hz frame can jump the short word's emphasis from dim to full and back.
        assert(fabs(effect - SGKaraokeWordEmphasis(ms + 8, 1000, 1008)) < 0.06);
    }
    // At 120Hz, only the next frame is projected, at the actual playback speed.
    near(SGKaraokePresentationMs(10000, true, 1, 100, 100.008, 0), 10008);
    near(SGKaraokePresentationMs(10000, true, 2, 100, 100.008, 0), 10016);
    // Bluetooth delay is in wall time: scale it into song time, not a guessed AirPods constant.
    near(SGKaraokePresentationMs(10000, true, 1, 100, 100.008, 0.2), 9808);
    near(SGKaraokePresentationMs(10000, true, 0.5, 100, 100.008, 0.2), 9904);
    near(SGKaraokePresentationMs(10000, true, 2, 100, 100.008, 0.2), 9616);
    // Pause, small backward seek, and disconnect take effect without accumulated clock smoothing.
    near(SGKaraokePresentationMs(10000, false, 1, 100, 100.008, 0.2), 9800);
    near(SGKaraokePresentationMs(9900, false, 1, 101, 101.008, 0.2), 9700);
    near(SGKaraokePresentationMs(9900, false, 1, 102, 102.008, 0), 9900);
    near(SGKaraokePresentationMs(0, true, 1, 100, 100.008, 0.2), 0);
    near(SGKaraokePresentationMs(-1, true, 1, 100, 100.008, 0), -1);
    near(SGKaraokePresentationMs(NAN, true, 1, 100, 100.008, 0), -1);
    near(SGKaraokePresentationMs(10000, true, NAN, 100, 100.008, NAN), 10008);
    near(SGKaraokePresentationMs(10000, true, 1, 100, 99, -0.2), 10000);
    near(SGKaraokePresentationMs(10000, true, 1, 100, 105, 0), 10050);
    puts("lyrics timing: all checks passed");
    return 0;
}
