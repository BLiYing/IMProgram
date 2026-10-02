//  IMDatabase+Archive.h
//  资料页「归档索引」的读取（单开 category：IMDatabase.m 已在体量红线上，CODING_STYLE §7）。

#import "IMDatabase.h"
#import "IMMessageModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase (Archive)

/// 资料页「归档索引」（媒体 / 文件 / 语音 / 链接 / 名片）要读的消息，升序。**不是全会话**：
/// 只取已上号、未撤回、非空的**非文本**消息，加上文本里带 `://` 的（链接页签的超集预筛，精确判据仍在
/// `IMChatDetailTabs message:matchesKind:`）。此前资料页读 `messagesForConv:` 全表，10 万条会话打开要把十万个对象全构造一遍。
- (NSArray<IMMessageModel *> *)archiveMessagesForConv:(NSString *)convID;

@end

NS_ASSUME_NONNULL_END
