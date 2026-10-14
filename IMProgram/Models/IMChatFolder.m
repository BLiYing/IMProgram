//  IMChatFolder.m

#import "IMChatFolder.h"

@implementation IMChatFolder {
    NSSet<NSString *> *_convSet; // 成员判定走集合：列表过滤每次刷新都要对全部会话各查一次
}

- (instancetype)initWithID:(NSString *)folderID name:(NSString *)name position:(NSInteger)position
                   convIDs:(NSArray<NSString *> *)convIDs {
    self = [super init];
    if (self) {
        _folderID = [folderID copy];
        _name = [name copy];
        _position = position;
        _convIDs = [convIDs copy] ?: @[];
        _convSet = [NSSet setWithArray:_convIDs];
    }
    return self;
}

+ (nullable instancetype)folderFromJSON:(id)json {
    if (![json isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *d = json;
    NSString *fid = [d[@"id"] isKindOfClass:NSString.class] ? d[@"id"] : nil;
    NSString *name = [d[@"name"] isKindOfClass:NSString.class] ? d[@"name"] : nil;
    if (fid.length == 0 || name.length == 0) { return nil; }
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    if ([d[@"conv_ids"] isKindOfClass:NSArray.class]) {
        for (id v in d[@"conv_ids"]) {
            if ([v isKindOfClass:NSString.class] && [(NSString *)v length] > 0) { [ids addObject:v]; }
        }
    }
    return [[self alloc] initWithID:fid name:name position:[d[@"position"] integerValue] convIDs:ids];
}

- (NSDictionary *)toJSON {
    return @{ @"id": self.folderID, @"name": self.name, @"position": @(self.position), @"conv_ids": self.convIDs };
}

- (BOOL)containsConv:(NSString *)convID {
    return convID.length > 0 && [_convSet containsObject:convID];
}

@end
