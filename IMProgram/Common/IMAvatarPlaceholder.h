//  IMAvatarPlaceholder.h
//  「首字母圈」头像的规则：显示哪两个字、用什么底色。App 内各处头像（UILabel+IMAvatar、聊天页导航头像、
//  详情头图）与通知扩展（没有可用头像时画一张同样的图，别让系统退回 App 图标）共用这一处。
//  只依赖 UIKit，**同编进通知扩展**（project.pbxproj 的 membership exception）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 首字母圈的显示字符（2026-10-01 改，三端同口径，见 `../IMServer/docs/UI.md` §「图标与头像资源」）：
/// 末一个字是汉字（CJK 统一表意文字及扩展）就取它（中文名去姓留名）；否则取首字母并转大写（英文名/用户名）。
/// 按「组合字符序列」取字，不会把结尾的 emoji／变体选择符切成半个乱码。
FOUNDATION_EXPORT NSString *IMAvatarInitials(NSString *_Nullable name);

/// 由种子（用户 uid / 群 conv_id）派生稳定的头像底色（一组柔和色循环）。
FOUNDATION_EXPORT UIColor *IMAvatarSeedColor(NSString *_Nullable seed);

/// 画一张 side×side 的首字母头像（方图，系统通知 / 圆形头像位自己裁圆），PNG 数据。
/// name 为空时用 seed 取字；渲染失败返回 nil。
FOUNDATION_EXPORT NSData *_Nullable IMAvatarPlaceholderPNG(NSString *_Nullable name, NSString *_Nullable seed, CGFloat side);

NS_ASSUME_NONNULL_END
