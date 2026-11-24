//  IMTenantStore.h
//  「我的集团与身份」的进程内快照：GET /api/v1/directory/me（TENANT_DESIGN v2 §8.1）。
//
//  客户端不自己判定可见性——通讯录、搜索、资料、直聊全按服务端结果展示；这里只决定
//  入口显不显示（有没有集团、是不是客户 / 员工）与审计告知弹不弹。
//  刷新时机：每次连上、回前台、收到好友事件 org_changed（调岗）/ org_exit（脱离集团时推给本人：删了好友按好友各一帧，没有好友也给本人一帧；集团停用不推，靠回前台 / 重连兜底），绑码成功后由调用方喂回结果。
//  换号：快照记着属于哪个账号，不是当前账号就当没拉到过。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 快照内容变化（含首次拉到）时在主线程发出。
FOUNDATION_EXPORT NSNotificationName const IMTenantStoreDidChangeNotification;

/// 一家公司的引用（各公司平等，TENANT_EQUAL_UNITS_OPS_DESIGN §1）。
@interface IMTenantUnit : NSObject
@property (nonatomic, copy) NSString *unitID;
@property (nonatomic, copy) NSString *name;
/// 客户 bindings 里该公司当前可用的邀请码；停用 / 员工的单位为空串（BACKLOG R1：填写邀请码页展示与复制）。
@property (nonatomic, copy) NSString *inviteCode;
+ (NSArray<IMTenantUnit *> *)unitsFromArray:(nullable id)array;
@end

@interface IMTenantStore : NSObject

+ (instancetype)shared;

/// 拿到过当前账号的 directory/me。没拿到前不能当「无集团」（依赖它的填码入口一律先不显示，免得员工被引去填码）。
@property (nonatomic, assign, readonly) BOOL loaded;
/// 我在启用中的集团里。
@property (nonatomic, assign, readonly) BOOL hasTenant;
/// 集团全称。
@property (nonatomic, copy, readonly) NSString *tenantName;
/// 身份：客户（否则是员工）。
@property (nonatomic, assign, readonly) BOOL isCustomer;
/// 员工是客服。
@property (nonatomic, assign, readonly) BOOL isCS;
/// 员工所在单位、部门名（客户为空）。
@property (nonatomic, copy, readonly) NSString *unitName;
@property (nonatomic, copy, readonly) NSString *deptName;
/// 客户所绑的启用中子公司。
@property (nonatomic, copy, readonly) NSArray<IMTenantUnit *> *bindings;
/// 后台添加的成员还没确认审计告知。
@property (nonatomic, assign, readonly) BOOL noticePending;

/// 开始观察连接 / 回前台 / org_exit 并首次拉取（App 启动时调一次，幂等）。
- (void)start;
/// 拉一次：在途不重发；刚拉过（几秒内）也不拉——合并「回前台」与随后的「Connected」。
- (void)refresh;
/// 忽略合并窗口立即拉（身份刚变：收到 org_exit / org_changed）。
- (void)refreshNow;
/// 写入一份 me 响应（refresh 成功、绑码成功都走这里；单测直接喂字典）。返回是否有变化。
- (BOOL)applyMe:(NSDictionary *)data;
/// 审计告知已确认（notice-ack 成功后调）。
- (void)markNoticeAcked;

@end

NS_ASSUME_NONNULL_END
