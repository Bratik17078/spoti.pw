#import <UIKit/UIKit.h>
@class SGModSection;
#define SGRKeyVisualizer @"spotifyglass.redesign.player.visualizer"
#define SGRKeyVisualizerStyle @"spotifyglass.redesign.player.visualizer.style"
#define SGRKeyVisualizerIntensity @"spotifyglass.redesign.player.visualizer.intensity"

@interface SGRVisualizer : UIView
@property (nonatomic) BOOL playerVisible;
@end
SGModSection *SGRVisualizerSection(void);
