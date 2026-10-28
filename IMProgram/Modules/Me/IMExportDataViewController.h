//  IMExportDataViewController.h
//  导出我的数据二级页（隐私与安全 → 数据）。4 态：配置 / 进行中 / 完成 / 冷却·失败。
//  设计 IMServer/docs/design/DATA_EXPORT_DESIGN.md §1 §5；草图 sketches/DATA_EXPORT_UX_SKETCH.html。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMExportDataViewController : UIViewController
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID;
@end

NS_ASSUME_NONNULL_END
