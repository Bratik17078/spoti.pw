#import <Foundation/Foundation.h>
#include "SGSpectrum.h"

// One foreground player surface owns the consumer. Enabling analysis never enables Music Haptics.
void SGVisualizationSetListening(BOOL listening);
BOOL SGVisualizationListening(void);
// Render thread only; seconds use the mach absolute clock. No allocation, locks, or Objective-C.
void SGVisualizationPush(const float *mono, uint32_t count, double rate, double hostSeconds);
// Main thread only. Future audio is held until its output latency has elapsed.
BOOL SGVisualizationRead(SGSpectrumFrame *frame, double now, double *heardAt);
