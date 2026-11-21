//  IMJSONValue.h
//  JSON 字段的类型安全取值（服务端字段缺失 / 类型不对时给空值，不崩）。
//  布尔只认 JSON 数字 / true·false（NSNumber），字符串 "1" / "false" 一律当 NO——与 IMConfigBool 等同口径。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 字符串；不是字符串返回 @""。
FOUNDATION_EXPORT NSString *IMJSONString(id _Nullable value);
/// 字典；不是字典返回 nil。
FOUNDATION_EXPORT NSDictionary *_Nullable IMJSONDict(id _Nullable value);
/// 数组里的字典项（其余类型的项丢掉）；不是数组返回空数组。
FOUNDATION_EXPORT NSArray<NSDictionary *> *IMJSONDicts(id _Nullable value);
/// 布尔：只认 NSNumber。
FOUNDATION_EXPORT BOOL IMJSONBool(id _Nullable value);

NS_ASSUME_NONNULL_END
