//  IMQRCardViewController.h
//  二维码展示页（QRCODE P0）：我的名片码 / 群二维码共用一页，差异只在取码接口与文案。
//  码内容串由服务端下发（`GET /qr/me`、`GET /groups/{id}/qr`），图片端上本地生成。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQRCardViewController : UIViewController

/// 我的名片码（长期有效，可重置）。
- (instancetype)initMyCardWithHost:(NSString *)host
                            userID:(NSString *)userID
                          username:(nullable NSString *)username
                          nickname:(nullable NSString *)nickname
                         avatarURL:(nullable NSString *)avatarURL;

/// 群二维码（7 天有效）。canReset=是否显示「重置群二维码」（群主/管理员；服务端二次校验）。
/// asLink=YES 时页面按「群邀请链接」呈现（标题/文案），码本体一致——码即邀请链接（与 Web 对齐）。
- (instancetype)initGroupCardWithHost:(NSString *)host
                               userID:(NSString *)userID
                               convID:(NSString *)convID
                            groupName:(nullable NSString *)groupName
                            avatarURL:(nullable NSString *)avatarURL
                          memberCount:(NSInteger)memberCount
                             canReset:(BOOL)canReset
                               asLink:(BOOL)asLink;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
