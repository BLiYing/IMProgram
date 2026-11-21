//  IMJSONValue.m

#import "IMJSONValue.h"

NSString *IMJSONString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

NSDictionary *IMJSONDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : nil; }

NSArray<NSDictionary *> *IMJSONDicts(id value) {
    if (![value isKindOfClass:NSArray.class]) { return @[]; }
    NSMutableArray *out = [NSMutableArray array];
    for (id item in (NSArray *)value) { if ([item isKindOfClass:NSDictionary.class]) { [out addObject:item]; } }
    return out;
}

BOOL IMJSONBool(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
