//  IMChatFolderConvPickerViewController.h
//  聊天文件夹「添加聊天」的会话多选页：全部会话（含搜索），已在夹内的预勾选，右上「完成」交回最终选中集。
//  不复用 IMForwardPickerViewController：它是「转发」语义（≤9 个、无预选、选完即发）。

#import <UIKit/UIKit.h>

@class IMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface IMChatFolderConvPickerViewController : UIViewController

/// conversations：可选的全部会话；selectedIDs：预选（已在文件夹内）；maxCount：选中上限（服务端 limits.max_convs）。
/// onDone 回调最终选中的 conv_id 集合（保持 conversations 里的顺序）；本页负责收起。
- (instancetype)initWithConversations:(NSArray<IMConversation *> *)conversations
                          selectedIDs:(NSArray<NSString *> *)selectedIDs
                             maxCount:(NSInteger)maxCount
                               onDone:(void (^)(NSArray<NSString *> *selectedIDs))onDone NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
