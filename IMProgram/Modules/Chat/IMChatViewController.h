//  IMChatViewController.h
//  极简聊天页：连上 IMSocketManager，与对方 uid 互发文本。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatViewController : UIViewController

/// host 形如 "localhost:8080"；userID 我方 uid；peerID 对方 uid。
/// readSeq：进入前的已读位点（定位未读分割线 + 可见即读的起点，首条未读=conv_seq>readSeq）；unread：进入时未读数。
- (instancetype)initWithHost:(NSString *)host
                      userID:(NSString *)userID
                      peerID:(NSString *)peerID
                     readSeq:(int64_t)readSeq
                      unread:(NSInteger)unread NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
