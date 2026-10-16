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

/// 嵌入扫一扫页时由宿主补正资料（名片码模式；群码模式忽略）。码本身不依赖资料，先能扫要紧。
- (void)updateMyProfileWithUsername:(nullable NSString *)username
                           nickname:(nullable NSString *)nickname
                          avatarURL:(nullable NSString *)avatarURL;
/// 展示给别人扫期间拉满亮度 / 还原（幂等）。嵌入页签切换时宿主手动调；独立页走自身 appear/disappear。
/// 嵌入页签每次切回时调：码还没取到（上次失败/未登录）就重取，已有码则无操作。
- (void)reloadCodeIfNeeded;
- (void)boostBrightness;
- (void)restoreBrightness;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
