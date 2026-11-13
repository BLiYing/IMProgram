//  IMIdentityProofSheet.h
//  「确认是你本人」弹层（PHONE_AUTH_DESIGN §7.2、交互稿 1-9）：密码 / 短信验证码二选一，替换注销、导出、邮箱、两步验证、
//  绑定 / 更换手机号里的密码输入。UISheetPresentationController：自定义 detent 高 320 + large、grabber、圆角 20；
//  分段 IMLiquidSegmentedControl（高 34，只有一种方式时不显示）；主按钮 systemBlue 高 50 圆角 12。
//
//  宿主页面持有一个 IMProofSession（随页面释放 = 离开页面即清空）：
//  - 安全状态（GET /users/me/security）：宿主有现成的就 seed；没有时弹层先取（转圈、确认不可点），取不到且没有旧值 → proof.load_failed，
//    **不**退化成「只有密码」（没设密码的账号会被卡死）。有旧值时立即用旧值、后台重取校正页签。
//    状态已知但没有可用方式（没设密码又不能发短信）：不显示输入框与分段，提示 proof.sms_unavailable，确认不可点（可取消）。
//  - 没用掉的短信验证码（IMProofCodeCache）：下次预填并落在短信页签。规则见 IMProofCodeCache。
//  - 本人号码 verify 验证码的倒计时：同一页面里多次打开弹层共用一份。
//  错误落点（IMProofErrorStaysInSheet）：证明本身的错留在弹层里重输；其余收起弹层交给页面（completion 带 pageError）。
//  取 token 失败（如重登回 200002）不进这条判定：证明根本没送到服务端，一律收起交给页面、不作废缓存的验证码。
//  提交中不可关闭（下滑 / 点外部都忽略）。**日志不写密码、验证码、号码。**

#import <UIKit/UIKit.h>
#import "IMPhoneAuth.h"

@class IMSMSCodeField, IMLiquidSegmentedControl;

NS_ASSUME_NONNULL_BEGIN

/// 宿主的提交：拿到 proof 发请求，结束时调 finish(error)（nil = 成功）。
typedef void (^IMProofSubmitBlock)(IMIdentityProof *proof, void (^finish)(NSError *_Nullable error));
/// 弹层收尾：succeeded=YES 操作成功；NO + pageError 交给页面显示；NO + nil = 用户取消。
typedef void (^IMProofCompletion)(BOOL succeeded, NSError *_Nullable pageError);
/// 便捷入口的宿主请求：token 已取好，拿 proof 发请求，结束时调 finish(error)（nil = 成功）。
typedef void (^IMProofTokenRequest)(NSString *token, IMIdentityProof *proof, void (^finish)(NSError *_Nullable error));

@interface IMProofSession : NSObject

- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 宿主已有的安全状态（如隐私与安全页刚取到的）；弹层仍会后台重取校正。
@property (nonatomic, strong, nullable) IMSecurityState *security;
@property (nonatomic, strong, readonly) IMProofCodeCache *codeCache;
@property (nonatomic, strong, readonly) IMResendClock *verifyClock;
/// 弹层在屏。
@property (nonatomic, assign, readonly, getter=isPresenting) BOOL presenting;

/// 弹出确认身份弹层。已在屏时忽略（返回 NO）。
- (BOOL)presentFrom:(UIViewController *)host submit:(IMProofSubmitBlock)submit completion:(IMProofCompletion)completion;

/// 便捷入口：弹出弹层，用户交出 proof 后先取 token（同 withToken:），取不到 → finish(取 token 的错误，没有时统一兜底)
/// 交弹层按「交给页面」处理；取到再调 request。completion 同 presentFrom:submit:completion:。
- (BOOL)presentFrom:(UIViewController *)host request:(IMProofTokenRequest)request completion:(IMProofCompletion)completion;

/// 取一枚可用 token（缓存命中不发请求）。
- (void)withToken:(void (^)(NSString *_Nullable token, NSError *_Nullable error))block;

@end

/// 测试 / 截图用：弹层本体（一般经 IMProofSession 弹出）。
@interface IMIdentityProofSheet : UIViewController
@property (nonatomic, strong, readonly) UITextField *passwordField;
@property (nonatomic, strong, readonly) IMSMSCodeField *codeField;
@property (nonatomic, strong, readonly) UIButton *confirmButton;
@property (nonatomic, strong, readonly) IMLiquidSegmentedControl *segmentedControl;
@property (nonatomic, strong, readonly) UILabel *errorLabel;
/// 灰色说明行：短信模式下「验证码已发送至 …」；没有可用方式时 proof.sms_unavailable。
@property (nonatomic, strong, readonly) UILabel *noticeLabel;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *tabs;
@property (nonatomic, assign, readonly) IMProofTab tab;
@property (nonatomic, assign, readonly, getter=isSubmitting) BOOL submitting;
@end

NS_ASSUME_NONNULL_END
