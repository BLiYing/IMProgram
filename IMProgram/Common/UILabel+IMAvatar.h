//  UILabel+IMAvatar.h
//  让现有「首字母圆」头像 UILabel 支持渲染 avatar_url 图片：
//  立即画首字母+稳定取色底（无空白闪烁），随后异步加载图片覆盖；cell 复用安全。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UILabel (IMAvatar)

/// url：data:/http(s)，可空（空=只显首字母圈）。seed：稳定取色种子（一般 uid）。displayName：取末两位作首字母。
- (void)im_setAvatarURL:(nullable NSString *)url seed:(NSString *)seed displayName:(nullable NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
