//  IMRtcInviteProvider.h
//  通话中「添加成员」的候选人：**读 IM 自己的群成员接口**，不为通话另建名单
//  （im-rtc-server docs/design/HOST_INTEGRATION_DESIGN.md §3.4）。
//
//  用 groupMembersPage（服务端分页 + 搜索）：普通群、超级群同一条路，也不依赖「这个群的资料页有没有打开过」
//  ——被叫在没进过群资料页的情况下也能加人。没有群号（不属于某个群的临时通话）时回空名单，绝不悬空不回调。

#import <Foundation/Foundation.h>
@import IMCallKit;

NS_ASSUME_NONNULL_BEGIN

@interface IMRtcInviteProvider : NSObject <IMInviteMemberProvider>
/// 当前登录用户：从候选人里排除自己。
@property (nonatomic, copy) NSString *selfUID;
@end

NS_ASSUME_NONNULL_END
