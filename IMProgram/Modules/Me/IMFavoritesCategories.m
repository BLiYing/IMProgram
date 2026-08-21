//  IMFavoritesCategories.m

#import "IMFavoritesCategories.h"
#import "IMMediaUtil.h" // IMMediaLooksLikeURL（与详情页/聊天页同一 URL 口径）

@implementation IMFavoriteCategoryTab
@end

@implementation IMFavoritesCategories

/// 取收藏字典的 content_type（缺省 text）。
static NSString *favContentType(NSDictionary *f) {
    NSString *ct = [f[@"content_type"] isKindOfClass:NSString.class] ? f[@"content_type"] : nil;
    return ct.length > 0 ? ct : @"text";
}

/// 取收藏字典的 content。
static NSString *favContent(NSDictionary *f) {
    return [f[@"content"] isKindOfClass:NSString.class] ? f[@"content"] : @"";
}

+ (NSString *)titleForCategory:(IMFavoriteCategory)kind {
    switch (kind) {
        case IMFavoriteCategoryAll:   return @"全部";
        case IMFavoriteCategoryMedia: return @"媒体";
        case IMFavoriteCategoryFiles: return @"文件";
        case IMFavoriteCategoryLinks: return @"链接";
        case IMFavoriteCategoryVoice: return @"语音";
        case IMFavoriteCategoryText:  return @"文本";
        case IMFavoriteCategoryRecord: return @"聊天记录";
    }
    return @"";
}

+ (BOOL)favorite:(NSDictionary *)favorite matchesCategory:(IMFavoriteCategory)kind {
    if (![favorite isKindOfClass:NSDictionary.class]) { return NO; }
    NSString *content = favContent(favorite);
    if (content.length == 0) { return NO; } // 空内容不计入任何类别
    if (kind == IMFavoriteCategoryAll) { return YES; }
    NSString *ct = favContentType(favorite);
    BOOL isRecord = [ct isEqualToString:@"chat_record"] || IMLooksLikeChatRecordJSON(content);
    switch (kind) {
        case IMFavoriteCategoryRecord:
            return isRecord;
        case IMFavoriteCategoryMedia:
            return [ct isEqualToString:@"image"] || [ct isEqualToString:@"video"];
        case IMFavoriteCategoryFiles:
            return [ct isEqualToString:@"file"];
        case IMFavoriteCategoryLinks:
            if ([ct isEqualToString:@"link"]) { return YES; }
            return [ct isEqualToString:@"text"] && IMMediaLooksLikeURL(content);
        case IMFavoriteCategoryVoice:
            return [ct isEqualToString:@"audio"] || [ct isEqualToString:@"voice"];
        case IMFavoriteCategoryText:
            return [ct isEqualToString:@"text"] && !isRecord && !IMMediaLooksLikeURL(content);
        case IMFavoriteCategoryAll:
            return YES;
    }
    return NO;
}

+ (NSArray<IMFavoriteCategoryTab *> *)categoriesForFavorites:(NSArray<NSDictionary *> *)favorites {
    return [self categoriesForFavorites:favorites includeAll:YES];
}

+ (NSArray<IMFavoriteCategoryTab *> *)categoriesForFavorites:(NSArray<NSDictionary *> *)favorites includeAll:(BOOL)includeAll {
    // 「全部」（可选）恒第一；其余按固定顺序仅存在者。
    IMFavoriteCategoryTab *(^tab)(IMFavoriteCategory) = ^(IMFavoriteCategory k) {
        IMFavoriteCategoryTab *t = [IMFavoriteCategoryTab new];
        t.kind = k;
        t.title = [self titleForCategory:k];
        return t;
    };
    NSMutableArray<IMFavoriteCategoryTab *> *out = [NSMutableArray array];
    if (includeAll) { [out addObject:tab(IMFavoriteCategoryAll)]; }
    NSArray<NSNumber *> *ordered = @[ @(IMFavoriteCategoryMedia), @(IMFavoriteCategoryFiles),
                                      @(IMFavoriteCategoryLinks), @(IMFavoriteCategoryVoice),
                                      @(IMFavoriteCategoryText), @(IMFavoriteCategoryRecord) ];
    for (NSNumber *n in ordered) {
        IMFavoriteCategory k = (IMFavoriteCategory)n.integerValue;
        BOOL exists = NO;
        for (NSDictionary *f in favorites) {
            if ([self favorite:f matchesCategory:k]) { exists = YES; break; }
        }
        if (exists) { [out addObject:tab(k)]; }
    }
    return out;
}

@end
