#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include <stdatomic.h>
#include <string.h>
#include <math.h>
#import "Visualization.h"

enum { kFrames = 128 };
typedef struct { SGSpectrumFrame frame; double heardAt; unsigned generation; } TimedFrame;
static TimedFrame sg_frames[kFrames];
static atomic_uint sg_head, sg_tail, sg_generation;
static atomic_bool sg_listening;
static atomic_uint_fast64_t sg_latency;
static atomic_flag sg_writing = ATOMIC_FLAG_INIT;
static SGSpectrum sg_spectrum;

static void readLatency(void) {
    double latency = AVAudioSession.sharedInstance.outputLatency;
    if (!isfinite(latency) || latency < 0) latency = 0;
    uint64_t bits; memcpy(&bits, &latency, sizeof bits); atomic_store(&sg_latency, bits);
}
void SGVisualizationSetListening(BOOL listening) {
    if (SGVisualizationListening() == listening) return;
    if (listening) readLatency();
    atomic_fetch_add(&sg_generation, 1);
    atomic_store(&sg_tail, atomic_load_explicit(&sg_head, memory_order_acquire));
    atomic_store(&sg_listening, listening);
}
BOOL SGVisualizationListening(void) { return atomic_load_explicit(&sg_listening, memory_order_relaxed); }

void SGVisualizationPush(const float *mono, uint32_t count, double rate, double hostSeconds) {
    if (!SGVisualizationListening() || !mono || rate <= 0 || !isfinite(rate)) return;
    // A second output unit may render concurrently while a route changes. Never wait on audio.
    if (atomic_flag_test_and_set_explicit(&sg_writing, memory_order_acquire)) return;
    static unsigned analyzedGeneration;
    unsigned generation = atomic_load(&sg_generation);
    if (generation != analyzedGeneration || rate != sg_spectrum.rate) {
        SGSpectrumReset(&sg_spectrum, rate); analyzedGeneration = generation;
    }
    uint64_t bits = atomic_load(&sg_latency); double latency; memcpy(&latency, &bits, sizeof latency);
    SGSpectrumFrame frame;
    for (uint32_t i = 0; i < count; i++) {
        if (!SGSpectrumSample(&sg_spectrum, mono[i], &frame)) continue;
        unsigned head = atomic_load_explicit(&sg_head, memory_order_relaxed);
        unsigned tail = atomic_load_explicit(&sg_tail, memory_order_acquire);
        if (head - tail >= kFrames) continue;
        sg_frames[head % kFrames] = (TimedFrame){frame, hostSeconds + i / rate + latency, generation};
        atomic_store_explicit(&sg_head, head + 1, memory_order_release);
    }
    atomic_flag_clear_explicit(&sg_writing, memory_order_release);
}
BOOL SGVisualizationRead(SGSpectrumFrame *frame, double now, double *heardAt) {
    unsigned head = atomic_load_explicit(&sg_head, memory_order_acquire);
    unsigned tail = atomic_load_explicit(&sg_tail, memory_order_relaxed);
    unsigned generation = atomic_load(&sg_generation);
    BOOL found = NO;
    while (tail != head) {
        TimedFrame *next = &sg_frames[tail % kFrames];
        if (next->generation == generation) {
            if (next->heardAt > now) break;
            *frame = next->frame;
            if (heardAt) *heardAt = next->heardAt;
            found = YES;
        }
        tail++;
    }
    atomic_store_explicit(&sg_tail, tail, memory_order_release);
    return found;
}
__attribute__((constructor)) static void visualizationInit(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (SGVisualizationListening()) { SGVisualizationSetListening(NO); SGVisualizationSetListening(YES); }
    }];
}
