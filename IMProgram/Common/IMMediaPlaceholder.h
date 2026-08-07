//  IMMediaPlaceholder.h
//  未下载媒体的「磨砂占位」统一渲染器（M4-7）。
//
//  聊天气泡（IMImageCell）/ 详情宫格（IMChatDetailViewController）/ 引用缩略（IMBubbleCell、输入框引用条）
//  三处共用：输入随消息内嵌的极小模糊缩略 thumb（~20px JPEG 的 data URI），输出**高斯模糊后的磨砂图**，
//  观感对齐 Telegram 的 stripped-thumbnail 毛玻璃。结果按 dataURI 缓存，算一次全程复用、不随滚动重算。
//  设计前提：门控态**只用内嵌 thumb、零额外流量**——不为占位去拉服务器封面/原图（方案 A·纯净门控）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPlaceholder : NSObject

/// 磨砂占位：thumb dataURI → 高斯模糊 UIImage，**主线程**回调；入参空 / 解不了码 → 回调 nil（调用方留中性底）。
+ (void)frostedForThumb:(nullable NSString *)thumbDataURI
             completion:(void (^)(UIImage *_Nullable blurred))completion;

/// 同步取已缓存的磨砂图（cellForRow 内先行占位，避免"先闪灰再变磨砂"）；未命中 / 入参空 → nil。
+ (nullable UIImage *)cachedFrostedForThumb:(nullable NSString *)thumbDataURI;

@end

NS_ASSUME_NONNULL_END
