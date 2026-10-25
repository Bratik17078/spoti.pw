// Exercises the actual portable analyzer, including silence, invalid samples and spectral peaks.
#include "Shared/AudioVisualization/SGSpectrum.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static SGSpectrum analyzer;
static SGSpectrumFrame frame;

static void checkBounds(void) {
    for (unsigned b = 0; b < SGSpectrumBands; b++) assert(isfinite(frame.bands[b]) && frame.bands[b] >= 0 && frame.bands[b] <= 1);
    for (unsigned i = 0; i < SGSpectrumWaveSamples; i++) assert(isfinite(frame.wave[i]) && fabsf(frame.wave[i]) <= 1);
}
static void tone(double rate, unsigned band) {
    SGSpectrumReset(&analyzer, rate);
    double high = fmin(14000, rate * 0.45);
    double hz = 50 * pow(high / 50, (double)band / (SGSpectrumBands - 1));
    unsigned emitted = 0;
    // Deliberately not a multiple of the window length, like arbitrary hardware IO buffers.
    for (unsigned i = 0; i < 7777; i++) {
        if (SGSpectrumSample(&analyzer, (float)(0.7 * sin(6.283185307179586 * hz * i / rate)), &frame)) {
            checkBounds(); emitted++;
            unsigned peak = 0;
            for (unsigned b = 1; b < SGSpectrumBands; b++) if (frame.bands[b] > frame.bands[peak]) peak = b;
            assert(peak == band);
            assert(frame.bands[peak] > 0.8f);
        }
    }
    assert(emitted == 7 && analyzer.filled == 609);
}
int main(void) {
    SGSpectrumReset(&analyzer, 48000);
    for (unsigned i = 0; i < SGSpectrumWindow; i++) {
        bool ready = SGSpectrumSample(&analyzer, 0, &frame);
        assert(ready == (i == SGSpectrumWindow - 1));
    }
    checkBounds();
    for (unsigned b = 0; b < SGSpectrumBands; b++) assert(frame.bands[b] == 0);
    for (unsigned i = 0; i < SGSpectrumWaveSamples; i++) assert(frame.wave[i] == 0);
    for (unsigned i = 0; i < SGSpectrumWindow; i++) SGSpectrumSample(&analyzer, i % 2 ? NAN : INFINITY, &frame);
    checkBounds();
    for (unsigned b = 0; b < SGSpectrumBands; b++) assert(frame.bands[b] == 0);
    const double rates[] = {8000, 44100, 48000, 96000};
    for (unsigned r = 0; r < 4; r++) for (unsigned b = 5; b < SGSpectrumBands; b += 3) tone(rates[r], b);
    SGSpectrumReset(&analyzer, NAN); assert(analyzer.rate == 48000);
    SGSpectrumReset(&analyzer, 0); assert(analyzer.rate == 48000);
    assert(!SGSpectrumSample(NULL, 0, &frame));
    puts("PASS: window boundaries, silence, nonfinite input, rate changes, and 28 spectral peak cases");
    return 0;
}
