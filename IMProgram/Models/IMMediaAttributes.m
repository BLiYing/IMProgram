//  IMMediaAttributes.m

#import "IMMediaAttributes.h"

@implementation IMMediaAttributes

+ (instancetype)attributesWithGroupID:(NSString *)groupID poster:(NSString *)poster {
    IMMediaAttributes *a = [IMMediaAttributes new];
    a.groupID = groupID;
    a.poster = poster;
    return a;
}

@end
