//  IMFilePickerViewController.h
//  文件选择面板（Telegram 式，#文件选择）：从相册选择 / 从文件中选择 + 「最近发送的文件」列表。
//  自身只做选择，动作经回调交回聊天页执行（复用其上传/发送逻辑）。以 sheet 形式呈现。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMFilePickerViewController : UIViewController

/// recentFiles：@[@{@"url",@"name"}]（新→旧）。
/// onFromPhotos / onFromFiles：选「从相册/从文件」的回调；onPickRecent：点最近文件（url,name）复发。
/// 三个回调触发前面板已自行关闭。
- (instancetype)initWithRecentFiles:(NSArray<NSDictionary *> *)recentFiles
                        onFromPhotos:(dispatch_block_t)onFromPhotos
                         onFromFiles:(dispatch_block_t)onFromFiles
                        onPickRecent:(void (^)(NSString *url, NSString *name))onPickRecent NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
