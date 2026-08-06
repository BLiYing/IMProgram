//  IMMediaAttributes.h
//  媒体消息随发送上行的元数据（M4+）。对应协议 send_msg 的
//  group_id / poster / media_w / media_h / duration / file_size（见 IMServer docs/PROTOCOL.md §4.1）。
//
//  约定：尺寸与时长**由发送端量出**（服务端只透传 + 范围校验，不解码媒体）；
//  收端据此按原比例渲染气泡、在视频封面左上角显 mm:ss、并用字节数做上传进度分母。
//  全部可选，0/nil 表示未知——收端回退「加载完再自适应 + 不显时长角标」。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMediaAttributes : NSObject

@property (nonatomic, copy, nullable) NSString *groupID; ///< 相册分组 ID：同批多图/视频共享，收发两端聚簇渲染宫格
@property (nonatomic, copy, nullable) NSString *poster;  ///< 视频封面首帧图 URL：收端直显封面免解码原视频
@property (nonatomic, assign) NSInteger pixelWidth;      ///< 媒体像素宽（0=未知）
@property (nonatomic, assign) NSInteger pixelHeight;     ///< 媒体像素高（0=未知）
@property (nonatomic, assign) int64_t durationMillis;    ///< 视频时长，毫秒（0=未知/非视频）
@property (nonatomic, assign) int64_t fileSize;          ///< 原始字节数（0=未知）
@property (nonatomic, copy, nullable) NSString *thumb;   ///< 极小模糊预览（~20px 缩略 JPEG 的 data URI，M4-7）：收端未下载时放大+模糊显占位，免先下原图

/// 便捷构造：仅带相册分组与封面（老调用路径）。
+ (instancetype)attributesWithGroupID:(nullable NSString *)groupID poster:(nullable NSString *)poster;

@end

NS_ASSUME_NONNULL_END
