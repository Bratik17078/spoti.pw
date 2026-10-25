// The foreground counterpart of the system Live Activity, which iOS hides inside its own app.
#import <UIKit/UIKit.h>

// Main thread, driven by LiveActivity.x's existing timer. A note collapses to a thin capsule.
void SGIslandOverlayShow(NSString *trackID, NSString *line, NSString *nextLine, BOOL paused);
void SGIslandOverlayHide(void);
