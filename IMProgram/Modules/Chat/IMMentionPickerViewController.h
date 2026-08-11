//  IMMentionPickerViewController.h
//  群聊 @提及成员选择器（M4-8）。输入框键入 `@` 时以半屏 sheet 卡片弹出，
//  与「文件」面板同一套呈现范式（PageSheet + 自定义 detent + 抓手 + 自持 Liquid Glass 标题栏）。
//
//  设计依据：IMServer/docs/GROUP_READ_UX_SKETCH.html §03。

#import <UIKit/UIKit.h>

@class IMGroupInfo, IMGroupMember;

NS_ASSUME_NONNULL_BEGIN

@interface IMMentionPickerViewController : UIViewController

/// group        群资料（成员表 + 我的角色；`myRole` 决定是否展示「@所有人」行）。
/// initialQuery 打开时的初始过滤词（输入框里 `@` 后已键入的部分，无则传 nil）。
/// onPickMember 选中某成员；回调参数为该成员（调用方据此回填 token）。
/// onPickAll    选中「@所有人」；仅群主/管理员可能触发（普通成员该行不渲染）。
/// 选中后本控制器自行 dismiss，调用方无需再关。
- (instancetype)initWithGroup:(IMGroupInfo *)group
                 initialQuery:(nullable NSString *)initialQuery
                 onPickMember:(void (^)(IMGroupMember *member))onPickMember
                    onPickAll:(void (^)(void))onPickAll;

/// 内联模式：作为**输入栏上方的下拉面板**嵌入聊天页（child VC），不弹 sheet、不抢键盘、无自带搜索框——
/// 过滤词由聊天输入框实时经 `updateQuery:` 驱动（对齐 Web 桌面端范式）。选中后由回调回填 token，宿主负责移除面板。
- (instancetype)initInlineWithGroup:(IMGroupInfo *)group
                       initialQuery:(nullable NSString *)initialQuery
                       onPickMember:(void (^)(IMGroupMember *member))onPickMember
                          onPickAll:(void (^)(void))onPickAll;

- (instancetype)initWithNibName:(nullable NSString *)n bundle:(nullable NSBundle *)b NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 外部（输入框）继续键入时同步过滤词，卡片内列表实时收敛。
- (void)updateQuery:(nullable NSString *)query;

/// 内联面板的建议高度（按当前过滤结果行数，封顶若干行）；返回 0 表示无内容、宿主应移除面板。
- (CGFloat)preferredInlineHeight;

/// 卡片彻底消失时回调一次（选中 / 点叉 / 下滑关闭都算）。
/// 调用方据此记住"用户已经把卡关掉了"，避免用户继续打字时卡片反复自动弹回来抢键盘。
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
