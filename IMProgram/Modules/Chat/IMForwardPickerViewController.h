//  IMForwardPickerViewController.h
//  转发/分享选择页（#6）：整页展示会话列表，右上「多选」切换单选/多选（多选最多 9 个）。
//  自身只负责选择，选中的会话由 onDone 回调交回调用方去转发（可复用于其它"选会话"场景）。

#import <UIKit/UIKit.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMForwardPickerViewController : UIViewController

/// host/token 用于拉取会话列表；onDone 回调选中的会话（单选=1 个，多选=1..9 个）；页面自身负责收起。
- (instancetype)initWithHost:(NSString *)host
                       token:(NSString *)token
                      onDone:(void (^)(NSArray<IMConversation *> *selected))onDone NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
