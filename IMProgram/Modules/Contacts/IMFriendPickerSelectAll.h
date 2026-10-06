//  IMFriendPickerSelectAll.h
//  建群选人页「全选 / 取消全选」的纯逻辑（口径见 IMServer/docs/design/CREATE_GROUP_SELECT_ALL_DESIGN.md §0）。
//  无 UIKit 依赖，可直接单测；三端同口径。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 可见行（搜索过滤后的 uid，按显示顺序）是否已**全部**选中。可见为空返回 NO（此时按钮本就隐藏）。
FOUNDATION_EXPORT BOOL IMFriendPickerAllVisibleSelected(NSArray<NSString *> *selected, NSArray<NSString *> *visible);

/// 点「全选」后的选中集：**保留已选**（含不可见的），再按可见顺序补，补到 `limit` 为止（0 = 不截断）。
/// 已选数本身已 >= limit 时不再补。结果保持「已选在前、新补在后」的顺序。
FOUNDATION_EXPORT NSArray<NSString *> *IMFriendPickerNextSelection(NSArray<NSString *> *selected,
                                                                    NSArray<NSString *> *visible,
                                                                    NSInteger limit);

/// 点「取消全选」后的选中集：只移除**可见行**，不动不可见的已选。
FOUNDATION_EXPORT NSArray<NSString *> *IMFriendPickerDeselectVisible(NSArray<NSString *> *selected,
                                                                      NSArray<NSString *> *visible);

NS_ASSUME_NONNULL_END
