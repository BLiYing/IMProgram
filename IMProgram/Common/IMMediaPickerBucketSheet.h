//  IMMediaPickerBucketSheet.h
//  相册切换面板：盖在宫格上（顶栏之下）、背景遮罩点击收起；列表行 = 封面 48×48 + 名称 + 数量。
//  规格见 docs/design/MEDIA_PICKER_IOS_DESIGN.md §2.1「相册面板」。

#import <UIKit/UIKit.h>

@class IMMediaPickBucket;

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPickerBucketSheet : UIView
@property (nonatomic, copy, nullable) void (^onPick)(NSString *bucketID);
@property (nonatomic, copy, nullable) void (^onDismiss)(void);
- (void)setBuckets:(NSArray<IMMediaPickBucket *> *)buckets;
@end

NS_ASSUME_NONNULL_END
