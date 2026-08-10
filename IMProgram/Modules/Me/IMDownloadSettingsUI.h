//  IMDownloadSettingsUI.h
//  数据和存储设置页三级 VC 共用的小工具（M4-7）：网络/类别取值、大小档位、低中高预设、汇总文案。

#import <Foundation/Foundation.h>
#import "IMDownloadSettings.h"
#import "IMAutoDownloadCategoryViewController.h" // IMDownloadNetworkKind / IMDownloadCategoryKind

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT IMDownloadNetworkPolicy *IMPolicyForNetwork(IMDownloadSettings *s, IMDownloadNetworkKind net);
FOUNDATION_EXPORT IMDownloadCategoryRule *IMRuleForCategory(IMDownloadNetworkPolicy *p, IMDownloadCategoryKind cat);
FOUNDATION_EXPORT NSString *IMDownloadCategoryName(IMDownloadCategoryKind cat);   // 图片 / 视频 / 文件
FOUNDATION_EXPORT NSString *IMDownloadNetworkTitle(IMDownloadNetworkKind net);    // 使用移动数据 / 使用 Wi-Fi

/// 大小上限档位：`[0, 512KB, 1MB, 3MB, 5MB, 10MB, 15MB, 30MB, 50MB, 100MB, 500MB, 1GB, 1.5GB]`（索引 0=关）。
FOUNDATION_EXPORT NSArray<NSNumber *> *IMDownloadSizeStops(void);
FOUNDATION_EXPORT NSInteger IMDownloadSizeStopIndex(int64_t bytes); // 最近档索引
FOUNDATION_EXPORT NSString *IMDownloadSizeLabel(int64_t bytes);     // "关" / "512 KB" / "15 MB" / "1.5 GB"

/// 流量档位：低/中/高为可套用的快捷预设；自定义为“已偏离任何预设”的只读指示（对齐 web「自定义」）。
typedef NS_ENUM(NSInteger, IMTrafficPreset) {
    IMTrafficPresetLow    = 0, // 视频/文件都手动(0)
    IMTrafficPresetMedium = 1, // 视频 10MB · 文件 1MB
    IMTrafficPresetHigh   = 2, // 视频 15MB · 文件 3MB
    IMTrafficPresetCustom = 3, // 视频/文件组合不等于任一预设
};

/// 套用低/中/高预设（0/1/2）：只改 video/file 上限（图片不动）。自定义(3)不可套用，传入按低处理。
FOUNDATION_EXPORT void IMApplyTrafficPreset(IMDownloadNetworkPolicy *p, NSInteger preset);
/// 精确反推档位（对齐 web tierOfPolicy）：视频+文件都恰好等于某预设→低/中/高；否则→自定义。
FOUNDATION_EXPORT IMTrafficPreset IMTrafficPresetForPolicy(IMDownloadNetworkPolicy *p);
FOUNDATION_EXPORT NSString *IMNetworkSummary(IMDownloadNetworkPolicy *p);         // "已停用" / "视频 15MB · 文件 3MB"

NS_ASSUME_NONNULL_END
