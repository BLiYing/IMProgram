//  IMFavoritesViewController.h
//  收藏消息列表（M4-4）：GET /api/v1/favorites 展示内容快照，左滑删除。
//  两种呈现模式：
//    - browse（默认）：从"我 → 收藏"push 进入，浏览 + 右上"⋯"切消息/聊天 + 长按菜单
//    - pick（Batch 2 新增）：从聊天页加号 → 收藏调出，多选 + 底部"发送(N)"，选中收藏透传回宿主

#import <UIKit/UIKit.h>

@class IMMediaAttributes;

NS_ASSUME_NONNULL_BEGIN

@interface IMFavoritesViewController : UIViewController

/// pick 模式：多选收藏 → 底部"发送(N)"→ onPickCompleted 回调返回选中项数组；用户取消返回空数组。
/// 上层（聊天页）拿到后按 forwardEchoContent: 逐条发到当前会话。宿主负责 dismiss 本页（回调返回后
/// 通常立即 dismiss；不 dismiss 也无害，用户可继续选发第二批）。
- (instancetype)initInPickModeWithDone:(void (^)(NSArray<NSDictionary *> *selectedFavs))onDone;

/// 把收藏字典里的媒体元数据（磨砂缩略/封面/时长/尺寸/图说）拼成 IMMediaAttributes，供转发通路带走
/// （避免收端收到裸内容缺封面/缩略图/尺寸导致空白）。非媒体且无 caption 时返回 nil。**类方法**：聊天页
/// 走 forwardEchoContent: 时同款调用，保证收藏页原 forwardFavorite: 与聊天页"从收藏发送"两路口径一致。
+ (nullable IMMediaAttributes *)mediaAttributesFromFavorite:(NSDictionary *)f;

@end

NS_ASSUME_NONNULL_END
