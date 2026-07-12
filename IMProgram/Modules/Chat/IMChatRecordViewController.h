//  IMChatRecordViewController.h
//  合并转发「聊天记录」详情页（#3）：解析 chat_record 的 JSON，按顺序列出全部消息；
//  文本直显，图片/视频显缩略图并可点击复用 IMMediaViewerViewController 查看。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatRecordViewController : UIViewController

/// host 用于把相对媒体 URL 补成绝对地址；recordJSON 为 chat_record 消息的 content。
- (instancetype)initWithHost:(NSString *)host recordJSON:(NSString *)recordJSON NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
