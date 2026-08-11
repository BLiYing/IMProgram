//  IMDownloadSettings.h
//  账号级**媒体自动下载策略**的客户端模型（M4-7），对应服务端 GET /api/v1/download-settings
//  与 internal/downloadsettings 的 JSON。两网络（移动数据 / Wi-Fi）× 图片/视频/文件 × 单聊/群聊
//  开关 + 大小上限。语义解释两端一致（见 docs/DOWNLOAD_DATA_STORAGE_PLAN.md）。
//
//  默认值与服务端 Defaults() 逐字对齐：移动数据中档（视频 10MB / 文件 1MB）、Wi-Fi 高档
//  （视频 15MB / 文件 3MB）、图片无上限、两网络开、单聊群聊均开。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单一类别（图片/视频/文件）在某网络下的规则。maxBytes=0：图片=无上限（恒自动）；视频/文件=不自动（手动）。
@interface IMDownloadCategoryRule : NSObject
@property (nonatomic, assign) BOOL single;    ///< 单聊是否自动下载
@property (nonatomic, assign) BOOL group;     ///< 群聊是否自动下载
@property (nonatomic, assign) int64_t maxBytes; ///< 自动下载大小上限（字节）
@end

/// 某网络（移动数据 / Wi-Fi）下的整套策略。
@interface IMDownloadNetworkPolicy : NSObject
@property (nonatomic, assign) BOOL enabled;                   ///< 该网络自动下载总开关
@property (nonatomic, strong) IMDownloadCategoryRule *image;
@property (nonatomic, strong) IMDownloadCategoryRule *video;
@property (nonatomic, strong) IMDownloadCategoryRule *file;
@end

@interface IMDownloadSettings : NSObject
@property (nonatomic, assign) int64_t version; ///< 服务端版本号（capabilities_update 去重用）
@property (nonatomic, strong) IMDownloadNetworkPolicy *cellular;
@property (nonatomic, strong) IMDownloadNetworkPolicy *wifi;

/// 出厂默认（与服务端 Defaults() 对齐）。服务端未下发 / 解析失败时的兜底。
+ (instancetype)defaultSettings;

/// 从服务端响应解析。root 可为 `{version, settings:{cellular,wifi}}`（GET 返回体的 data），
/// 也可直接是 `{cellular,wifi}`；缺字段回退默认，容错不崩。
+ (instancetype)fromJSON:(nullable NSDictionary *)root;

/// 序列化为 `{cellular:{...}, wifi:{...}}`（PUT body 用；不含 version，服务端只认结构）。
- (NSDictionary *)toSettingsDictionary;

/// 深拷贝（设置页编辑副本，避免直接改 store 的活对象）。
- (instancetype)deepCopy;

/// 策略是否等价（按 toSettingsDictionary 逐字段比较，忽略 version）。
/// 供各设置页判定「与本地副本/出厂默认是否一致」，避免各处重复 dict 比较。
- (BOOL)isEquivalentTo:(nullable IMDownloadSettings *)other;

@end

NS_ASSUME_NONNULL_END
