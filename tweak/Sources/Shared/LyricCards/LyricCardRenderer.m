#import "LyricCards.h"
#include <math.h>

static NSDictionary *attributes(CGFloat size, UIFontWeight weight, UIColor *color, CGFloat spacing) {
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineSpacing = spacing;
    paragraph.baseWritingDirection = NSWritingDirectionNatural;
    return @{NSFontAttributeName: [UIFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph};
}

static void cover(UIImage *image, CGRect rect) {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return;
    CGFloat scale = MAX(rect.size.width / image.size.width, rect.size.height / image.size.height);
    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:10] addClip];
    [image drawInRect:CGRectMake(CGRectGetMidX(rect) - size.width / 2, CGRectGetMidY(rect) - size.height / 2, size.width, size.height)];
    CGContextRestoreGState(context);
}

UIImage *SGLyricCardImage(NSString *title, NSString *artist, NSArray<NSString *> *lines, UIImage *artwork, NSInteger style) {
    if (!lines.count) return nil;
    NSString *quote = [lines componentsJoinedByString:@"\n"];
    UIColor *ink = style == 1 ? [UIColor colorWithWhite:0.10 alpha:1] : UIColor.whiteColor;
    UIColor *muted = style == 1 ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor colorWithWhite:1 alpha:0.76];
    CGRect textRect = CGRectMake(28, 128, 304, 234);
    NSDictionary *textAttributes;
    CGFloat size = 29;
    for (; size >= 14; size--) {
        textAttributes = attributes(size, UIFontWeightBold, ink, 5);
        CGRect bounds = [quote boundingRectWithSize:CGSizeMake(textRect.size.width, CGFLOAT_MAX)
            options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:textAttributes context:nil];
        if (ceil(bounds.size.height) <= textRect.size.height) break;
    }
    if (size < 14) return nil; // Never clip selected lyrics; ask the editor for a shorter selection.
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 3; format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(360, 450) format:format] imageWithActions:^(UIGraphicsImageRendererContext *renderer) {
        [(style == 1 ? [UIColor colorWithRed:0.96 green:0.94 blue:0.89 alpha:1] : [UIColor colorWithRed:0.055 green:0.065 blue:0.09 alpha:1]) setFill];
        [renderer fillRect:CGRectMake(0, 0, 360, 450)];
        if (style == 2 && artwork) {
            cover(artwork, CGRectMake(0, 0, 360, 450));
            // A solid scrim keeps every part of the text legible, including pale cover art.
            [[UIColor colorWithWhite:0 alpha:0.76] setFill];
            [renderer fillRect:CGRectMake(0, 0, 360, 450)];
        }
        if (artwork) cover(artwork, CGRectMake(28, 28, 68, 68));
        else {
            [[ink colorWithAlphaComponent:0.10] setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(28, 28, 68, 68) cornerRadius:10] fill];
            UIImage *note = [[UIImage systemImageNamed:@"music.note"] imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
            [note drawInRect:CGRectMake(51, 49, 22, 26)];
        }
        [@"LYRICS" drawInRect:CGRectMake(112, 35, 220, 20) withAttributes:attributes(11, UIFontWeightSemibold, muted, 0)];
        NSMutableDictionary *songAttributes = [attributes(17, UIFontWeightSemibold, ink, 2) mutableCopy];
        NSMutableParagraphStyle *songParagraph = [songAttributes[NSParagraphStyleAttributeName] mutableCopy];
        songParagraph.lineBreakMode = NSLineBreakByTruncatingTail;
        songAttributes[NSParagraphStyleAttributeName] = songParagraph;
        [title drawInRect:CGRectMake(112, 57, 220, 42) withAttributes:songAttributes];
        [quote drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:textAttributes context:nil];
        [[ink colorWithAlphaComponent:0.18] setFill];
        [renderer fillRect:CGRectMake(28, 382, 304, 0.5)];
        NSMutableDictionary *artistAttributes = [attributes(14, UIFontWeightMedium, muted, 0) mutableCopy];
        artistAttributes[NSParagraphStyleAttributeName] = songParagraph;
        [artist drawInRect:CGRectMake(28, 397, 304, 20) withAttributes:artistAttributes];
        [@"spoti.pw" drawInRect:CGRectMake(28, 423, 304, 14) withAttributes:attributes(10, UIFontWeightRegular, muted, 0)];
    }];
}
