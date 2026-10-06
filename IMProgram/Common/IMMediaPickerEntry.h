//  IMMediaPickerEntry.h
//  聊天相册入口（➕ → 照片）的呈现 + 回调：弹出自建选择器，选完把 PHAsset 包成 IMPickedMediaHandle。
//  下游「选完秒上屏 → 压缩/转码 → 上传」链路与旧 PHPicker 入口共用，一行不改。

#import <UIKit/UIKit.h>

@class IMPickedMediaHandle;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPickerEntry : NSObject

/// 弹出自建相册选择器（全屏）。选完（≤9，按选中顺序）**立即**回调惰性句柄（主线程）；
/// 取消 → 空数组。权限被拒 = 选择器内的空状态（说明 + 去设置），**不降级**到系统选择器。
+ (void)presentFromViewController:(UIViewController *)host
                handlesCompletion:(void (^)(NSArray<IMPickedMediaHandle *> *handles))completion;

@end

NS_ASSUME_NONNULL_END
