//  IMPasteImageTextField.m

#import "IMPasteImageTextField.h"

@implementation IMPasteImageTextField
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:) && UIPasteboard.generalPasteboard.hasImages) { return YES; }
    return [super canPerformAction:action withSender:sender];
}
- (void)paste:(id)sender {
    if (UIPasteboard.generalPasteboard.hasImages) {
        UIImage *img = UIPasteboard.generalPasteboard.image;
        if (img && self.onPasteImage) { self.onPasteImage(img); return; }
    }
    [super paste:sender];
}
@end
