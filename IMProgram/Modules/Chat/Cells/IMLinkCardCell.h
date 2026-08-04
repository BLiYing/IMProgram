#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMLinkCardCell : UITableViewCell
/// 长按菜单高亮/收起、引用跳转闪烁的目标视图（=网址文本+OG 卡片整体，与 Web 一致一起高亮）。
@property (nonatomic, strong, readonly) UIView *previewTargetView;
@property (nonatomic, copy, nullable) void (^onTap)(NSString *url);
/// OG 预览异步到达、卡片展开改变了行高 → 回调聊天页刷一次行高（否则内容被压进旧行高，滚动后才正常）。
@property (nonatomic, copy, nullable) void (^onContentSizeResolved)(void);
- (void)configureWithMessage:(IMMessageModel *)message mine:(BOOL)mine
                  senderName:(nullable NSString *)senderName;
/// 群聊对方消息的头像列 + 昵称（与 IMBubbleCell/IMImageCell 同签名）：gutter=YES 时左移 30pt 头像列对齐。
- (void)applyGroupAvatarURL:(nullable NSString *)url
                       seed:(NSString *)seed
                       name:(nullable NSString *)name
                 showAvatar:(BOOL)showAvatar
                     gutter:(BOOL)gutter;
@end

NS_ASSUME_NONNULL_END
