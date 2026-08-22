//  IMChatSelectionState.h
//  多选态的**状态协作对象**（仅 IMChatViewController+Selection.m / +DataSource.m 使用）。
//  按 CODING_STYLE §7：新增多选状态收进本状态袋，别再堆进共享私有头 IMChatViewController+Private.h
//  （会触发 pre-commit「共享私有头属性数」>72 预算）。聊天页只持有一个 selectionState，
//  进入多选创建、退出置 nil 整体释放。纯状态容器，无行为。
//  注：selecting / selectionBar / savedTitle / savedRightItem 因缓存生命周期跨进出复用，仍留在 Private.h。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatSelectionState : NSObject

@property (nonatomic, strong, nullable) NSMutableSet<NSNumber *> *selectedMediaSeqs; ///< 相册逐格勾选的成员 conv_seq（2a）；非相册消息仍用表格行选中
@property (nonatomic, strong, nullable) NSLayoutConstraint *savedTableBottom; ///< 多选前「表底=replyBar 顶」约束（退出恢复）
@property (nonatomic, strong, nullable) NSLayoutConstraint *tableBottom;      ///< 多选期间「表底=屏幕底」（壁纸铺到底，玻璃钮浮其上、无背景）
@property (nonatomic, assign) CGFloat savedBottomInset;                       ///< 多选前表格 contentInset.bottom（退出恢复）
@property (nonatomic, strong, nullable) NSLayoutConstraint *barBottom;        ///< 选择栏底边约束：搜索开着=贴搜索栏顶（堆叠不重叠）/否则=安全区底

@end

NS_ASSUME_NONNULL_END
