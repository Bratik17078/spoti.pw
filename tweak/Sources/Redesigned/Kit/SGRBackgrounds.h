// Photo backgrounds belong to the redesign. Photos are copied into app storage at a bounded size;
// preferences hold only the file name, so resetting preferences restores the original backgrounds.
#import <UIKit/UIKit.h>

#define SGRKeyPlaylistBackgroundMode @"spotifyglass.redesign.backgrounds.playlistMode"
extern NSNotificationName const SGRBackgroundDidChangeNotification;
extern NSString *const SGRBackgroundHome;
extern NSString *const SGRBackgroundPlaylists;
extern NSString *const SGRBackgroundLikedSongs;

BOOL SGRBackgroundHasPhoto(NSString *scope);
NSString *SGRBackgroundScopeForPlaylist(NSString *uri, BOOL liked);
void SGRChooseBackground(NSString *scope, NSString *title);
UIViewController *SGRBackgroundsPage(void);
// Installs one noninteractive, fixed photo behind a page's content. The caller owns the ordering.
UIView *SGRInstallPhotoBackground(UIView *page, NSString *scope, NSUInteger index);
