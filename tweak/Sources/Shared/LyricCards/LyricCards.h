#import <UIKit/UIKit.h>
@class SPTPlayerTrack;
void SGPresentLyricCard(UIViewController *presenter, SPTPlayerTrack *track);
void SGPresentPlayingLyricCard(void);

// Fixed logical canvas, exported at 3×. The editor uses the same renderer for its preview.
UIImage *SGLyricCardImage(NSString *title, NSString *artist, NSArray<NSString *> *lines, UIImage *artwork, NSInteger style);
