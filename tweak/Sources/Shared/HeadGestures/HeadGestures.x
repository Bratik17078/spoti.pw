// Logos constructors are compiled only from .x sources. Starting here lets route changes wake the
// listener when compatible AirPods connect after Spotify launches.
#import "HeadGestures.h"

%ctor {
    SGHeadGesturesRefresh();
}
