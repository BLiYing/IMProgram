//  IMGroupTextViewController.h
//  群公告 / 群简介 全文只读视图（bottom sheet）。
//  设计：GROUP_FEATURES_DESIGN.md 决策 16/17——「看全文」唯一落点，横幅/详情页卡都指向它。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMGroupTextViewController : UIViewController

/// 以 bottom sheet 弹出只读全文。
/// @param title    顶部标题，如 @"群公告" / @"群简介"。
/// @param subtitle 副标题（公告传「群主 · 08-12 09:30 发布」，简介传 nil）。
/// @param body     正文全文。
+ (void)presentFrom:(UIViewController *)host
              title:(NSString *)title
           subtitle:(nullable NSString *)subtitle
               body:(NSString *)body;

/// 公告副标题：把发布时间（ms）格式化为「M月d日 HH:mm 发布」；<=0 返回 nil。
+ (nullable NSString *)announceSubtitleForMillis:(int64_t)ms;

@end

NS_ASSUME_NONNULL_END
