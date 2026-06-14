//  IMTheme.m

#import "IMTheme.h"

@implementation IMTheme

+ (UIColor *)accent { return UIColor.systemBlueColor; }
+ (UIColor *)bubbleMe { return UIColor.systemBlueColor; }
+ (UIColor *)bubbleMeText { return UIColor.whiteColor; }
+ (UIColor *)bubbleThem { return UIColor.secondarySystemBackgroundColor; }
+ (UIColor *)textPrimary { return UIColor.labelColor; }
+ (UIColor *)textSecondary { return UIColor.secondaryLabelColor; }

+ (CGFloat)space1 { return 4; }
+ (CGFloat)space2 { return 8; }
+ (CGFloat)space3 { return 12; }
+ (CGFloat)space4 { return 16; }
+ (CGFloat)radiusBubble { return 14; }
+ (CGFloat)radiusCard { return 8; }

@end
