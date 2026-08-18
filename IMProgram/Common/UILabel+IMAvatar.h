//  UILabel+IMAvatar.h
//  让现有「首字母圆」头像 UILabel 支持渲染 avatar_url 图片：
//  立即画首字母+稳定取色底（无空白闪烁），随后异步加载图片覆盖；cell 复用安全。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 首字母圈的显示字符：取名字末两位（中文名去姓留名/英文名取尾），不足两位原样。
/// 头像圈（本 category）/ 聊天页导航头像 / 详情头图共用同一规则，改动只此一处。
FOUNDATION_EXPORT NSString *IMAvatarInitials(NSString *_Nullable name);

@interface UILabel (IMAvatar)

/// url：data:/http(s)，可空（空=只显首字母圈）。seed：稳定取色种子（一般 uid）。displayName：取末两位作首字母。
- (void)im_setAvatarURL:(nullable NSString *)url seed:(NSString *)seed displayName:(nullable NSString *)displayName;

/// 复用为「非图片头像」（如 @所有人 的纯色 @ 圆）前调用：隐藏并清掉覆盖用 UIImageView，
/// 同时自增 token 作废任何在途的异步头像加载——否则上一格成员的照片会残留/晚到覆盖上来。
- (void)im_clearAvatarImage;

@end

NS_ASSUME_NONNULL_END
