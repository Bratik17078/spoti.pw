#include "SGSpectrum.h"
#include <math.h>
#include <string.h>

void SGSpectrumReset(SGSpectrum *spectrum, double sampleRate) {
    memset(spectrum, 0, sizeof *spectrum);
    spectrum->rate = isfinite(sampleRate) && sampleRate >= 8000 && sampleRate <= 384000 ? sampleRate : 48000;
    const double pi = 3.14159265358979323846;
    for (unsigned i = 0; i < SGSpectrumWindow; i++) spectrum->window[i] = (float)(0.5 - 0.5 * cos(2 * pi * i / (SGSpectrumWindow - 1)));
    double high = fmin(14000, spectrum->rate * 0.45);
    for (unsigned b = 0; b < SGSpectrumBands; b++) {
        double frequency = 50 * pow(high / 50, (double)b / (SGSpectrumBands - 1));
        spectrum->coefficients[b] = 2 * cos(2 * pi * frequency / spectrum->rate);
    }
}

bool SGSpectrumSample(SGSpectrum *spectrum, float sample, SGSpectrumFrame *frame) {
    if (!spectrum || !frame || spectrum->rate <= 0) return false;
    spectrum->samples[spectrum->filled++] = isfinite(sample) ? fminf(1, fmaxf(-1, sample)) : 0;
    if (spectrum->filled < SGSpectrumWindow) return false;
    spectrum->filled = 0;
    for (unsigned b = 0; b < SGSpectrumBands; b++) {
        double q1 = 0, q2 = 0, coefficient = spectrum->coefficients[b];
        for (unsigned i = 0; i < SGSpectrumWindow; i++) {
            double next = spectrum->samples[i] * spectrum->window[i] + coefficient * q1 - q2;
            q2 = q1; q1 = next;
        }
        double power = fmax(0, q1 * q1 + q2 * q2 - coefficient * q1 * q2);
        double magnitude = sqrt(power) * 4 / SGSpectrumWindow;
        frame->bands[b] = (float)fmin(1, fmax(0, (20 * log10(fmax(1e-9, magnitude)) + 60) / 60));
    }
    for (unsigned i = 0; i < SGSpectrumWaveSamples; i++) {
        float peak = 0;
        for (unsigned j = 0; j < SGSpectrumWindow / SGSpectrumWaveSamples; j++) {
            float value = spectrum->samples[i * (SGSpectrumWindow / SGSpectrumWaveSamples) + j];
            if (fabsf(value) > fabsf(peak)) peak = value;
        }
        frame->wave[i] = peak;
    }
    return true;
}
