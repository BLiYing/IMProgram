//  IMMediaPickerViewController.h
//  自建相册多选页（宫格 + 编号选中 + 相册切换 + 原图勾选 + 长按预览 + 权限三态）。
//  交互与 Android `:media-picker` 对齐，规格 / 草图见 docs/design/MEDIA_PICKER_IOS_DESIGN.md。
//  **不引用聊天业务**：选完只回调 PHAsset 列表与「原图」开关，由入口（IMMediaPickerEntry）包成句柄。

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaPickerViewController : UIViewController

/// 结束回调（主线程）：assets 按选中顺序；取消 = 空数组。回调时本页尚未 dismiss，由回调方负责。
@property (nonatomic, copy, nullable) void (^onFinish)(NSArray<PHAsset *> *assets, BOOL sendOriginal);

@end

NS_ASSUME_NONNULL_END
