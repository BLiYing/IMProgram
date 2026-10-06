//  IMMediaPickerBars.h
//  自建相册选择器的顶栏与底栏（规格见 docs/design/MEDIA_PICKER_IOS_DESIGN.md §2.1 / §2.2）。
//  底栏在宫格页与预览页共用（预览页深色样式、无「预览」钮），保证两页同一套规则。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 顶栏：左「取消」/ 中标题（相册 ≥2 个时带 ▼▲，可点）/ 右占位。背景 surface。
@interface IMMediaPickerTopBar : UIView
@property (nonatomic, copy, nullable) void (^onCancel)(void);
@property (nonatomic, copy, nullable) void (^onTitleTap)(void);
/// canSwitch=YES 才显示箭头并可点；expanded 决定 ▲/▼。
- (void)setTitle:(NSString *)title canSwitch:(BOOL)canSwitch expanded:(BOOL)expanded;
@end

/// 底栏：[limited 横幅] / 「预览」· 原图勾选 · 发送钮。
@interface IMMediaPickerBottomBar : UIView
/// dark=YES：预览页样式（黑 80% 底、白字、无「预览」钮、无横幅）。
- (instancetype)initWithDarkStyle:(BOOL)dark;
@property (nonatomic, copy, nullable) void (^onPreview)(void);
@property (nonatomic, copy, nullable) void (^onOriginalToggle)(void);
@property (nonatomic, copy, nullable) void (^onSend)(void);
@property (nonatomic, copy, nullable) void (^onManageAccess)(void); ///< 点 limited 横幅
/// totalBytes<=0 时「原图」后不显示括号（体积未知）。
- (void)updateWithSelectedCount:(NSInteger)count
                     originalOn:(BOOL)originalOn
                     totalBytes:(long long)totalBytes
                    showsBanner:(BOOL)showsBanner;
@end

NS_ASSUME_NONNULL_END
