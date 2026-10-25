// Portable, allocation-free analysis of mono PCM. No UIKit or Objective-C on the render thread.
#pragma once
#include <stdbool.h>
#include <stdint.h>
enum { SGSpectrumBands = 24, SGSpectrumWaveSamples = 128, SGSpectrumWindow = 1024 };
typedef struct {
    float bands[SGSpectrumBands], wave[SGSpectrumWaveSamples];
} SGSpectrumFrame;
typedef struct {
    double rate;
    unsigned filled;
    float samples[SGSpectrumWindow], window[SGSpectrumWindow];
    double coefficients[SGSpectrumBands];
} SGSpectrum;
void SGSpectrumReset(SGSpectrum *spectrum, double sampleRate);
// Returns true at a complete analysis window; accepts one sample at a time to preserve arbitrary IO sizes.
bool SGSpectrumSample(SGSpectrum *spectrum, float sample, SGSpectrumFrame *frame);
