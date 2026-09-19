//  IMRtcProfileResolver.h
//  通话界面的名字与头像来源：**读 IM 自己已有的数据**，不为通话另建缓存、不去刷新
//  （im-rtc-server docs/design/HOST_PROFILE_DISPLAY_DESIGN.md §9、§10.5）。
//
//  名字：备注 > 群昵称（群通话）> 昵称 > @句柄，与 IM 界面同一口径（IMRemarkStore / IMGroupMember / IMUserProfileCache）。
//  头像：同一份 avatarURL 经 IMMediaFullURL 补全，只读 IMImageLoader 的内存缓存；没有就触发一次异步加载，
//  加载完通知 Kit 补画。**通话不因拨号 / 来电发任何请求**：IMUserProfileCache 里一个名字都没有的人才由它兜底取一次。
//
//  宿主数据自己变了不需要通知 Kit：Kit 每次重画都会重新来问，下次自然就是新的。只有「兜底取回」才通知。

#import <Foundation/Foundation.h>
@import IMCallKit;

@class IMGroupInfo;

NS_ASSUME_NONNULL_BEGIN

@interface IMRtcProfileResolver : NSObject <IMProfileResolving>

/// 当前这通电话所属的群；单聊为空串。拨号 / 来电时由 IMRtcCall 设置。
@property (nonatomic, copy) NSString *groupID;

/// 兜底取回、头像图加载完成后，用它通知 Kit 重画。
@property (nonatomic, weak, nullable) IMCallKit *kit;

/// 群资料页加载完成时喂进来：群通话按这张成员表取群昵称与头像。只留最近一次。
- (void)putGroup:(IMGroupInfo *)group;

@end

NS_ASSUME_NONNULL_END
