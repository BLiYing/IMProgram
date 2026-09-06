//  IMChatSelectionState.h
//  多选态的**状态协作对象**（仅 IMChatViewController+Selection.m / +DataSource.m 使用）。
//  按 CODING_STYLE §7：新增多选状态收进本状态袋，别再堆进共享私有头 IMChatViewController+Private.h
//  （会触发 pre-commit「共享私有头属性数」>72 预算）。聊天页只持有一个 selectionState，
//  进入多选创建、退出置 nil 整体释放。纯状态容器，无行为。
//  注：selecting / selectionBar / savedTitle / savedRightItem 因缓存生命周期跨进出复用，仍留在 Private.h。

#import <UIKit/UIKit.h>

@class IMMessageModel;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatSelectionState : NSObject

/// 已勾选的消息，**按 conv_seq 索引**（key=@(conv_seq)，value=消息模型）。多选态的**唯一真相**。
///
/// 2026-09-06 由「相册逐格用集合 + 非相册靠 UITableView 行选中」两套合并成这一套。原先那套有两个死穴，
/// 都在用户上翻拉历史时发作（实测：勾两条 → 上滚拉新页 → 再勾一条，前两条静默消失、只剩 1 条）：
///   ① `reloadData` 会清空 `indexPathsForSelectedRows`——而向上翻页的 `prependMessages:` 必然 reload；
///   ② 行选中是**按下标**记的，prepend 在头部插 N 条后所有下标平移，就算没被清也全部指向了别人。
/// 改按 conv_seq 记就都免疫了（Web 端一直是 `Set<convSeq>`，所以从没这个毛病）。
///
/// 存**模型**而不只存 seq：勾过的消息可能被窗口裁剪挤出内存（上翻会从尾部裁），
/// 只留 seq 的话计数与实际能操作的条数会对不上；存着模型则转发/收藏/举报都不必回查数据库。
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, IMMessageModel *> *selectedModels;
@property (nonatomic, strong, nullable) NSLayoutConstraint *savedTableBottom; ///< 多选前「表底=replyBar 顶」约束（退出恢复）
@property (nonatomic, strong, nullable) NSLayoutConstraint *tableBottom;      ///< 多选期间「表底=屏幕底」（壁纸铺到底，玻璃钮浮其上、无背景）
@property (nonatomic, assign) CGFloat savedBottomInset;                       ///< 多选前表格 contentInset.bottom（退出恢复）
@property (nonatomic, strong, nullable) NSLayoutConstraint *barBottom;        ///< 选择栏底边约束：搜索开着=贴搜索栏顶（堆叠不重叠）/否则=安全区底

@end

NS_ASSUME_NONNULL_END
