// Clock and word timing math, independent of UIKit so the playback boundaries can be checked on
// any host. Timings are milliseconds; host times and output latency are seconds.
#ifndef SG_KARAOKE_MATH_H
#define SG_KARAOKE_MATH_H
#include <math.h>
#include <stdbool.h>

static inline double SGKaraokeWordProgress(double ms, double start, double end) {
    if (ms < start) return 0;
    // An instantaneous syllable must still finish, including one sharing the next syllable's start.
    if (end <= start || ms >= end) return 1;
    return (ms - start) / (end - start);
}

// Visual emphasis only: a soft 280ms rise and 380ms settling tail, without stretching word timing.
// Sampling the song clock keeps this frozen on pause and reversible on a backward seek.
static inline double SGKaraokeWordEmphasis(double ms, double start, double end) {
    if (ms <= start || ms >= fmax(start, end) + 380) return 0;
    double rise = fmin(1, (ms - start) / 280);
    double fall = fmax(0, fmin(1, (ms - fmax(start, end)) / 380));
    rise = rise * rise * (3 - 2 * rise);
    fall = fall * fall * (3 - 2 * fall);
    return rise * (1 - fall);
}

static inline double SGKaraokePresentationMs(double position, bool running, double rate,
                                           double now, double shown, double latency) {
    if (!isfinite(position) || position < 0) return -1;
    if (!isfinite(rate) || rate <= 0) rate = 1;
    if (!isfinite(latency) || latency < 0) latency = 0;
    // A stale display timestamp must not extrapolate a whole frame stall into the song.
    double lead = running && isfinite(shown) ? fmin(0.05, fmax(0, shown - now)) : 0;
    return fmax(0, position + (lead - latency) * rate * 1000);
}
#endif
