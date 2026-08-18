//  IMDetailHeaderViews.m

#import "IMDetailHeaderViews.h"
#import "IMImageLoader.h"
#import "IMTheme.h"

@implementation IMDetailAvatarView {
    NSUInteger _token;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        _letter = [[UILabel alloc] initWithFrame:self.bounds];
        _letter.textAlignment = NSTextAlignmentCenter;
        _letter.textColor = UIColor.whiteColor;
        [self addSubview:_letter];
        _photo = [[UIImageView alloc] initWithFrame:self.bounds];
        _photo.contentMode = UIViewContentModeScaleAspectFill;
        _photo.clipsToBounds = YES;
        _photo.hidden = YES;
        [self addSubview:_photo];                 // 图在首字母之上
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _letter.frame = self.bounds;
    _photo.frame = self.bounds;                   // 显式铺满，随 morph 每帧更新
    _letter.font = [UIFont systemFontOfSize:MAX(10, self.bounds.size.width * 0.4) weight:UIFontWeightSemibold];
}
- (void)setAvatarURL:(NSString *)url seed:(NSString *)seed name:(NSString *)name {
    NSString *n = name.length ? name : seed;
    _letter.text = n.length >= 2 ? [n substringFromIndex:n.length - 2] : n;
    self.backgroundColor = [IMTheme avatarColorForSeed:seed];
    _photo.image = nil; _photo.hidden = YES;
    NSUInteger token = ++_token;
    if (url.length == 0) { return; }
    __weak typeof(self) ws = self;
    [[IMImageLoader shared] loadImageURL:url completion:^(UIImage *img) {
        __strong typeof(ws) self = ws;
        if (!self || !img || token != self->_token) { return; }
        self->_photo.image = img;
        self->_photo.frame = self.bounds;          // 应用时再钉一次 frame，防止 0×0 起步残留
        self->_photo.hidden = NO;
    }];
}
@end

@implementation IMDetailHeaderContainer
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha <= 0.01 || !self.userInteractionEnabled) { return nil; }
    UIView *child = self.interactiveChild;
    if (!child || child.hidden || child.alpha <= 0.01) { return nil; }
    CGPoint p = [self convertPoint:point toView:child];
    if (![child pointInside:p withEvent:event]) { return nil; }
    return [child hitTest:p withEvent:event] ?: child;
}
@end
