//  IMDatabase.m

#import "IMDatabase.h"
#import "IMMessageModel.h"
#import "IMLog.h"

@implementation IMDatabase {
    NSURL *_fileURL;
    NSMutableDictionary<NSString *, NSMutableArray<IMMessageModel *> *> *_byConv; // conv_id -> 消息
}

+ (instancetype)sharedDatabase {
    static IMDatabase *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
        instance = [[IMDatabase alloc] initWithFileURL:[docs URLByAppendingPathComponent:@"im_store.archive"]];
    });
    return instance;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _fileURL = fileURL;
        _byConv = [NSMutableDictionary dictionary];
        [self load];
    }
    return self;
}

#pragma mark - 读写

- (void)saveMessage:(IMMessageModel *)message {
    if (message.convID.length == 0) { return; }
    @synchronized (self) {
        NSMutableArray<IMMessageModel *> *list = _byConv[message.convID];
        if (!list) {
            list = [NSMutableArray array];
            _byConv[message.convID] = list;
        }
        NSInteger idx = [self indexOfMessageMatching:message in:list];
        if (idx == NSNotFound) {
            [list addObject:message];
        } else {
            list[idx] = message; // upsert：sending→sent 覆盖，或重复入站覆盖
        }
        [self persist];
    }
}

- (NSArray<IMMessageModel *> *)messagesForConv:(NSString *)convID {
    @synchronized (self) {
        return [_byConv[convID] copy] ?: @[];
    }
}

- (int64_t)maxConvSeqForConv:(NSString *)convID {
    @synchronized (self) {
        int64_t maxSeq = 0;
        for (IMMessageModel *m in _byConv[convID]) {
            if (m.convSeq > maxSeq) { maxSeq = m.convSeq; }
        }
        return maxSeq;
    }
}

#pragma mark - 内部

/// 出站消息按 clientMsgID 匹配；入站（无 clientMsgID）按 conv_seq 匹配。返回 NSNotFound 表示新消息。
- (NSInteger)indexOfMessageMatching:(IMMessageModel *)message in:(NSArray<IMMessageModel *> *)list {
    for (NSInteger i = 0; i < (NSInteger)list.count; i++) {
        IMMessageModel *m = list[i];
        if (message.clientMsgID.length > 0 && [m.clientMsgID isEqualToString:message.clientMsgID]) {
            return i;
        }
        if (message.clientMsgID.length == 0 && message.convSeq > 0 && m.convSeq == message.convSeq) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)persist {
    NSMutableDictionary *tree = [NSMutableDictionary dictionary];
    [_byConv enumerateKeysAndObjectsUsingBlock:^(NSString *conv, NSMutableArray<IMMessageModel *> *list, BOOL *stop) {
        NSMutableArray *dicts = [NSMutableArray arrayWithCapacity:list.count];
        for (IMMessageModel *m in list) { [dicts addObject:[m dictionaryRepresentation]]; }
        tree[conv] = dicts;
    }];
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:tree requiringSecureCoding:YES error:&error];
    if (!data) {
        IMLog(@"[db] 归档失败: %@", error.localizedDescription);
        return;
    }
    if (![data writeToURL:_fileURL options:NSDataWritingAtomic error:&error]) {
        IMLog(@"[db] 写盘失败: %@", error.localizedDescription);
    }
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfURL:_fileURL];
    if (!data) { return; }
    NSSet *classes = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, nil];
    NSError *error = nil;
    NSDictionary *tree = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:&error];
    if (![tree isKindOfClass:[NSDictionary class]]) {
        IMLog(@"[db] 读盘/解档失败: %@", error.localizedDescription);
        return;
    }
    [tree enumerateKeysAndObjectsUsingBlock:^(NSString *conv, NSArray *dicts, BOOL *stop) {
        if (![dicts isKindOfClass:[NSArray class]]) { return; }
        NSMutableArray<IMMessageModel *> *list = [NSMutableArray arrayWithCapacity:dicts.count];
        for (id d in dicts) {
            if ([d isKindOfClass:[NSDictionary class]]) {
                [list addObject:[IMMessageModel messageFromDictionary:d]];
            }
        }
        self->_byConv[conv] = list;
    }];
}

@end
