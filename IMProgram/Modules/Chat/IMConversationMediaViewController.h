//  IMConversationMediaViewController.h
//  会话媒体库：按时间顺序展示本会话所有图片/视频缩略图网格；与资料页「媒体」tab 共用同一套门控格子
//  IMMediaTileCell（磨砂 + ↓/环形进度 + 尺寸角标）、同一套长按菜单（转发/定位/取消下载/删除）；
//  点击复用 IMMediaPagerViewController 左右翻页查看（不显「媒体库」按钮，避免死循环）。

#import <UIKit/UIKit.h>

@class IMMessageModel, IMMenuAction, IMPopoverCardItem;

NS_ASSUME_NONNULL_BEGIN

/// 媒体项（轻量值对象），供媒体库与查看器传递。
@interface IMMediaItem : NSObject
@property (nonatomic, copy)   NSString *url;   ///< 已拼好 host 的完整媒体地址
@property (nonatomic, assign) BOOL      isVideo;
@property (nonatomic, assign) int64_t   timestamp; ///< 毫秒
@property (nonatomic, copy, nullable) NSString *thumb; ///< 内嵌极小模糊缩略 dataURI（M4-7 门控占位；无则退灰底）
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp;
+ (instancetype)itemWithURL:(NSString *)url isVideo:(BOOL)isVideo timestamp:(int64_t)timestamp
                      thumb:(nullable NSString *)thumb;
@end

@interface IMConversationMediaViewController : UIViewController
/// @param items                  展示项（内部统一按时间新→旧排序）。
/// @param messages               与 items **逐位对齐**的消息模型（门控态/缩略/长按菜单/查看器更多都据此）。
/// @param host                   供内部自建下载协调器（门控/进度/取消，autoPrefetch 关，与聊天页共享同一份下载态）。
/// @param myUserID               同上：下载协调器所属账号。
/// @param isGroup                同上：群/单聊语境。
/// @param title                  查看器顶部标题（会话名）。
/// @param contextActionsProvider 长按菜单里「消息相关」动作（转发/定位/删除）——由聊天页按上下文构造；「取消下载」本页自带。
/// @param moreActionsProvider    查看器「更多」外部动作（定位/收藏/复制/转发）。
+ (instancetype)galleryWithItems:(NSArray<IMMediaItem *> *)items
                        messages:(NSArray<IMMessageModel *> *)messages
                            host:(NSString *)host
                        myUserID:(NSString *)myUserID
                         isGroup:(BOOL)isGroup
                           title:(nullable NSString *)title
          contextActionsProvider:(nullable NSArray<IMMenuAction *> *(^)(IMMessageModel *m))contextActionsProvider
             moreActionsProvider:(nullable NSArray<IMPopoverCardItem *> *(^)(IMMessageModel *m))moreActionsProvider;
@end

NS_ASSUME_NONNULL_END
