//  IMRecentFiles.h
//  「最近发送的文件」本地记录（NSUserDefaults，按 owner 隔离，capped）。用于 iOS 文件选择面板复选最近文件。
//  只存元数据（url + name），不存文件内容；服务器文件仍在，重发直接复用同一 URL（无需重新上传）。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMRecentFiles : NSObject

/// 记录一次发送的文件（url=服务器相对/绝对地址，name=显示名）。同 url 去重并置顶，最多保留 20 条。
+ (void)recordForOwner:(NSString *)ownerID url:(NSString *)url name:(NSString *)name;

/// 该 owner 的最近文件（新→旧），每项 @{@"url":..,@"name":..}。
+ (NSArray<NSDictionary *> *)listForOwner:(NSString *)ownerID;

@end

NS_ASSUME_NONNULL_END
