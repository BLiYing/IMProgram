//  IMReconnectReloader.h
//  重连刷新样板收敛（任务5·code-review #3）：断网期间页面看本地缓存种子，socket 恢复(Connected)
//  且页面可见时自动取一次权威数据。宿主 VC 只需持有本对象、在 viewWillAppear/Disappear 里更新 visible。
//  与「连接态 → 标题后缀」这类需响应**所有**状态的处理器无关（如会话列表 onSocketState 另做标题更新，不用本类）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMReconnectReloader : NSObject

/// @param reloadBlock 连接恢复(Connected) 且 visible=YES 时触发。**须弱引用宿主**（本对象被宿主强持有），
///                    否则 宿主→reloader→block→宿主 成环。
- (instancetype)initWithReloadBlock:(dispatch_block_t)reloadBlock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 宿主 VC 在 viewWillAppear 置 YES、viewDidDisappear 置 NO；仅可见时才响应重连（避免离屏空跑登录+HTTP）。
@property (nonatomic, assign) BOOL visible;

@end

NS_ASSUME_NONNULL_END
