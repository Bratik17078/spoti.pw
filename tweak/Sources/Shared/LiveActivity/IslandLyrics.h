// Text that fits either side of the camera without opening the Island.
#import "Shared/Lyrics/Lyrics.h"

// Real word timing follows the current word; line timing shows the opening phrase of that line.
// Joined syllables stay one word in spaced scripts. Untimed lyrics and pre-roll return a note.
void SGIslandLyricWords(SGKaraokeLine *line, NSInteger ms, NSString **current, NSString **next);
