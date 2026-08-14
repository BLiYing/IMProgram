//  IMCircleCheckbox.h
//  可复用的圆形勾选框（行首多选用）：未选 circle / 选中 checkmark.circle.fill + 主色。
//  多处「头像+名字」多选列表共享此控件，只统一「圆圈外观 + 选中态」，各 cell 保留自己的布局与数据模型。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCircleCheckbox : UIImageView

/// 选中态：切换 circle ↔ checkmark.circle.fill，并切换灰/主色 tint。
@property (nonatomic, assign, getter=isChecked) BOOL checked;

@end

NS_ASSUME_NONNULL_END
