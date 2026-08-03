//  IMPendingMediaStore.m

#import "IMPendingMediaStore.h"
#import "IMLog.h"

NSString * const kIMPendingMediaScheme = @"im-pending://";

@implementation IMPendingMediaStore {
    NSString *_dir;
}

+ (instancetype)shared {
    static IMPendingMediaStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [IMPendingMediaStore new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Application Support 而非 Caches：Caches 会被系统在空间紧张时清掉，待发文件丢了就永远发不出去。
        NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        _dir = [base stringByAppendingPathComponent:@"im_pending_media"];
        NSError *err = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:_dir withIntermediateDirectories:YES attributes:nil error:&err]) {
            IMLogErrorWithTag(IMLogTagMedia, @"pending_dir_create_failed error=%@", err.localizedDescription ?: @"-");
        }
        [self excludeFromBackup];
    }
    return self;
}

/// 待发文件是可重建的中间产物，不该占用户的 iCloud 备份空间。
- (void)excludeFromBackup {
    NSURL *url = [NSURL fileURLWithPath:_dir];
    NSError *err = nil;
    if (![url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&err]) {
        IMLogWarnWithTag(IMLogTagMedia, @"pending_dir_backup_flag_failed error=%@", err.localizedDescription ?: @"-");
    }
}

+ (BOOL)isLocalRef:(NSString *)value {
    return value.length > kIMPendingMediaScheme.length && [value hasPrefix:kIMPendingMediaScheme];
}

- (NSString *)storeData:(NSData *)data forClientMsgID:(NSString *)clientMsgID extension:(NSString *)extension {
    if (data.length == 0 || clientMsgID.length == 0) { return nil; }
    NSString *name = extension.length > 0 ? [clientMsgID stringByAppendingPathExtension:extension] : clientMsgID;
    NSString *path = [_dir stringByAppendingPathComponent:name];
    NSError *err = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        IMLogErrorWithTag(IMLogTagMedia, @"pending_store_failed client_msg_id=%@ bytes=%lu error=%@",
                          clientMsgID, (unsigned long)data.length, err.localizedDescription ?: @"-");
        return nil;
    }
    IMLogDebugWithTag(IMLogTagMedia, @"pending_stored client_msg_id=%@ bytes=%lu", clientMsgID, (unsigned long)data.length);
    return [kIMPendingMediaScheme stringByAppendingString:name];
}

- (NSString *)storeFileAtURL:(NSURL *)fileURL forClientMsgID:(NSString *)clientMsgID extension:(NSString *)extension {
    if (!fileURL || clientMsgID.length == 0) { return nil; }
    NSString *name = extension.length > 0 ? [clientMsgID stringByAppendingPathExtension:extension] : clientMsgID;
    NSString *path = [_dir stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL]; // 覆盖旧残留，copyItem 遇到已存在会失败
    NSError *err = nil;
    if (![NSFileManager.defaultManager copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:path] error:&err]) {
        IMLogErrorWithTag(IMLogTagMedia, @"pending_copy_failed client_msg_id=%@ error=%@",
                          clientMsgID, err.localizedDescription ?: @"-");
        return nil;
    }
    return [kIMPendingMediaScheme stringByAppendingString:name];
}

- (NSString *)storeByMovingFileAtURL:(NSURL *)fileURL forClientMsgID:(NSString *)clientMsgID extension:(NSString *)extension {
    if (!fileURL || clientMsgID.length == 0) { return nil; }
    NSString *name = extension.length > 0 ? [clientMsgID stringByAppendingPathExtension:extension] : clientMsgID;
    NSString *path = [_dir stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    NSError *err = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:fileURL toURL:[NSURL fileURLWithPath:path] error:&err]) {
        // 跨卷 move 会失败（tmp 与 Application Support 一般同卷，属兜底）——回落 copy。
        if ([NSFileManager.defaultManager copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:path] error:&err]) {
            [NSFileManager.defaultManager removeItemAtURL:fileURL error:NULL];
        } else {
            IMLogErrorWithTag(IMLogTagMedia, @"pending_move_failed client_msg_id=%@ error=%@",
                              clientMsgID, err.localizedDescription ?: @"-");
            return nil;
        }
    }
    return [kIMPendingMediaScheme stringByAppendingString:name];
}

- (int64_t)byteSizeForLocalRef:(NSString *)localRef {
    NSString *path = [self filePathForLocalRef:localRef];
    if (!path) { return 0; }
    return (int64_t)[[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL][NSFileSize] unsignedLongLongValue];
}

/// upload_id 存成同名 `.uploadid` 旁挂文件：与待发字节同生共死，删本地副本时一并清理。
- (NSString *)uploadIDSidecarPathForLocalRef:(NSString *)localRef {
    NSString *path = [self filePathForLocalRef:localRef];
    return path ? [path stringByAppendingPathExtension:@"uploadid"] : nil;
}

- (void)setUploadID:(NSString *)uploadID forLocalRef:(NSString *)localRef {
    NSString *sidecar = [self uploadIDSidecarPathForLocalRef:localRef];
    if (!sidecar) { return; }
    if (uploadID.length == 0) { [NSFileManager.defaultManager removeItemAtPath:sidecar error:NULL]; return; }
    [[uploadID dataUsingEncoding:NSUTF8StringEncoding] writeToFile:sidecar options:NSDataWritingAtomic error:NULL];
}

- (NSString *)uploadIDForLocalRef:(NSString *)localRef {
    NSString *sidecar = [self uploadIDSidecarPathForLocalRef:localRef];
    if (!sidecar) { return nil; }
    NSData *raw = [NSData dataWithContentsOfFile:sidecar];
    NSString *value = raw ? [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] : nil;
    return value.length > 0 ? value : nil;
}

- (NSString *)filePathForLocalRef:(NSString *)localRef {
    if (![IMPendingMediaStore isLocalRef:localRef]) { return nil; }
    NSString *name = [localRef substringFromIndex:kIMPendingMediaScheme.length];
    // 防路径穿越：只接受纯文件名。
    if ([name containsString:@"/"] || [name containsString:@".."]) { return nil; }
    NSString *path = [_dir stringByAppendingPathComponent:name];
    return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}

- (NSData *)dataForLocalRef:(NSString *)localRef {
    NSString *path = [self filePathForLocalRef:localRef];
    return path ? [NSData dataWithContentsOfFile:path] : nil;
}

- (void)removeLocalRef:(NSString *)localRef {
    NSString *sidecar = [self uploadIDSidecarPathForLocalRef:localRef]; // 必须先取：删了主文件就找不到路径了
    NSString *path = [self filePathForLocalRef:localRef];
    if (sidecar) { [NSFileManager.defaultManager removeItemAtPath:sidecar error:NULL]; }
    if (path) { [NSFileManager.defaultManager removeItemAtPath:path error:NULL]; }
}

@end
