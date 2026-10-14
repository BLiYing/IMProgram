//  IMChatFolder.h
//  会话文件夹（聊天文件夹）：用户自建的手动分类，一个会话可在多个文件夹内、仍留在「全部」。
//  服务端口径见 IMServer/docs/PROTOCOL.md §6.15、设计见 IMServer/docs/design/CHAT_FOLDERS_DESIGN.md。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMChatFolder : NSObject

@property (nonatomic, copy, readonly) NSString *folderID;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) NSInteger position;
/// 成员会话 id（按加入先后；永不为 nil）。
@property (nonatomic, copy, readonly) NSArray<NSString *> *convIDs;

- (instancetype)initWithID:(NSString *)folderID name:(NSString *)name position:(NSInteger)position
                   convIDs:(NSArray<NSString *> *)convIDs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 从服务端 JSON（`{id,name,position,conv_ids[]}`）解析；缺 id / name 视为非法返回 nil。
+ (nullable instancetype)folderFromJSON:(id)json;
- (NSDictionary *)toJSON;

- (BOOL)containsConv:(NSString *)convID;

@end

NS_ASSUME_NONNULL_END
