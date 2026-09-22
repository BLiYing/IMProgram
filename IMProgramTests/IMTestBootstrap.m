//  IMTestBootstrap.m
//  单测默认固定简体中文：模拟器系统语言常是 en，会让「跟随系统」解析成英文，
//  打破全部既有的中文断言（会话时间「昨天」、提示文案等）。要测别的语言的用例自行 setPreference: 并在 tearDown 还原。

#import <Foundation/Foundation.h>
#import "IMLocalization.h"

@interface IMTestBootstrap : NSObject
@end

@implementation IMTestBootstrap
+ (void)load {
    [IMLocalization.shared setPreference:IMLanguagePrefZhHans];
}
@end
