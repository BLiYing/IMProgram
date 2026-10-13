//  IMViewedMediaStore.h
//  「用户在查看器里主动看过」的图片/视频登记（对齐 Web `optedIn.ts` / Android `ViewedMediaStore`）。
//
//  语义：点开查看器 = 允许拉原件。登记后，聊天页 / 会话详情 / 媒体库 / 收藏 / 聊天记录里的同一条媒体
//  不再显示磨砂 + ↓（看都看过了，再要一次「点下载」没有意义）。**看过 ≠ 已下载**：本机没有原件时
//  视频仍是流式播放，下载态不受影响。
//
//  - key = 查看器同款的完整 URL（IMMediaFullURL 补 host 后）：各入口手里都有它，不必各自还原 content；
//  - 进程内一份 + 按账号落 NSUserDefaults（重启仍在），末 500 条封顶；
//  - 纯本机状态，**不进账号级设置**、不跨设备同步（与 Web 同）；
//  - 「数据与存储 ▸ 清除缓存」要一并清（回到没看过，门控按策略重判）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 登记有变化（新增一条或清空）。userInfo：新增时 `@{ @"url": 完整 URL }`；清空时为空。主线程发。
FOUNDATION_EXPORT NSNotificationName const IMViewedMediaDidChangeNotification;

@interface IMViewedMediaStore : NSObject

+ (instancetype)shared;

/// 测试注入隔离的 defaults（`shared` 用 standardUserDefaults）。
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;

/// 当前账号 uid。默认取本地库当前账号；测试可覆盖。空 uid = 不登记也不命中（未登录不记）。
@property (nonatomic, copy, nullable) NSString *_Nullable (^userIDProvider)(void);

- (BOOL)isViewedURL:(nullable NSString *)url;
/// 幂等：已登记不重复写、不重复通知。
- (void)markViewedURL:(nullable NSString *)url;
/// 清掉当前账号的全部登记并通知。
- (void)clearCurrentUser;

@end

NS_ASSUME_NONNULL_END
