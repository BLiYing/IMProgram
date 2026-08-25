//
//  IMFavoriteVoiceCell.h
//  收藏页语音行（2026-08-26 拍板：内嵌迷你波形播放器）：
//    [▶/⏸] ▁▃▅▇▅▃ 0:12
//    来自X · 2026年8月26日 14:02
//  播放状态跟随 IMVoicePlayer 单例广播（与聊天气泡同一套通知）；点击播放由宿主经 onPlayTap 编排
//  （宿主负责"缓存命中直接播 / 未缓存先下载"，本 cell 只做展示与点击转发）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class IMMessageModel;

@interface IMFavoriteVoiceCell : UITableViewCell

/// 点播放键 / 点行（宿主 didSelect 也会走同一入口）。
@property (nonatomic, copy, nullable) void (^onPlayTap)(void);

- (void)configureWithMessage:(IMMessageModel *)message
                  sourceText:(NSString *)sourceText
                    timeText:(NSString *)timeText;

@end

NS_ASSUME_NONNULL_END
