//  IMFilePickerViewController.h
//  文件选择面板（Telegram 式，#文件选择）：从相册选择 / 从文件中选择 + 「最近发送的文件」列表。
//  自身只做选择，动作经回调交回聊天页执行（复用其上传/发送逻辑）。以 sheet 形式呈现。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMSentFilePageCompletion)(NSArray<NSDictionary *> *_Nullable files, BOOL hasMore, NSError *_Nullable error);
typedef void (^IMSentFilePageLoader)(BOOL nextPage, IMSentFilePageCompletion completion);

@interface IMFilePickerViewController : UIViewController

/// 创建系统文件浏览器。改由聊天页在面板关闭后直接呈现，保持 Files / File Provider 的完整内部导航栈。
+ (UIDocumentPickerViewController *)systemDocumentPicker;

/// recentFiles：@[@{@"url",@"name",@"size",@"timestamp"}]（新→旧）。
/// onFromPhotos：选择相册入口；onFromFiles：进入系统文件浏览器；
/// onPickRecent：点最近文件（url,name,size）复发。所有入口回调触发前面板已自行关闭，
/// 系统文件浏览器由聊天页承载，点叉叉/选完直接回到聊天页，不再回落面板。
- (instancetype)initWithRecentFiles:(NSArray<NSDictionary *> *)recentFiles
                        onFromPhotos:(dispatch_block_t)onFromPhotos
                         onFromFiles:(dispatch_block_t)onFromFiles
                        onPickRecent:(void (^)(NSString *url, NSString *name, int64_t size))onPickRecent
                            loadPage:(IMSentFilePageLoader)loadPage NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nib bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
