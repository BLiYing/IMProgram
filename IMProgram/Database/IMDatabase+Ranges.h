#import "IMDatabase.h"
#import "IMMessageModel.h"
#import <FMDB/FMDB.h>

NS_ASSUME_NONNULL_BEGIN

/// 「本地有哪几段」区间清单的实现（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.2）。
///
/// 单开一个 category 而不是继续堆进 IMDatabase.m：一是那个文件已触体量红线（CODING_STYLE §7 ②），
/// 二是这组方法自成一个概念——**本地不再假装是服务端的完整副本**，而是「看过的页 + 一张目录」。
/// 它们与消息读写共用同一个 FMDatabaseQueue，但回答的是完全不同的问题：不是"给我消息"，
/// 而是"我到底有没有这一段"。
/// 在**已开启的事务**里登记一段区间（与重叠/相邻的既有段合并）。返回是否成功。
///
/// 做成 C 函数而不是方法：它要被三处复用——`registerRangeInConv:`（单段）、
/// `saveIncomingPage:`（整页）、以及 IMDatabase.m 里的实时单条落库——
/// 而后者在 `writeIncomingMessage:…inDB:` 的事务中间，拿不到也不该拿 self 的队列。
BOOL IMRegisterRangeInDB(FMDatabase *db, NSString *owner, NSString *convID, int64_t lo, int64_t hi);

@interface IMDatabase (Ranges)

/// 包含 seq 的那一段的**起点**；seq 不在任何段内返回 0。
///
/// 用途只有一个但很要紧：**判断"本地更早的一页"是否与当前这一页相接**。
/// 有缺口时 `messagesForConv:beforeConvSeq:` 会从缺口**另一侧**的旧岛捞出消息，
/// 直接接到窗口顶部就是把两段不相邻的历史静默拼在一起——界面照常、顺序看着也对，
/// 只是中间少了几万条且没有任何提示（OFFLINE_BACKLOG_DESIGN §4.7）。
- (int64_t)localSegmentStartInConv:(NSString *)convID containingSeq:(int64_t)seq;

/// 本地库里该会话 conv_seq > afterConvSeq 的**对端**消息条数（↓N 用）。
/// **仅在 `isConvComplete:` 为真时可信**——有缺口时缺口里的消息根本没下载，数出来必然偏小。
- (NSInteger)countIncomingInConv:(NSString *)convID afterConvSeq:(int64_t)afterConvSeq;

/// **整页**原子落库（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.8）：
/// 一页补拉消息 + 游标推进 + 区间登记全部在**同一个事务**里提交。
///
/// 不变量没变，只是粒度从"每条"降到"每页"：页内任一条写失败 → 整页回滚、整页重拉，
/// 「消息未落库则游标/区间绝不越过」照旧成立（那是 2026-08-25 seq=416 事故的根治约束）。
/// 换来的是补拉 10 万条时 10 万次事务变 500 次。
///
/// @param advanceTo 本页权威覆盖位点（服务端 covered_conv_seq）；0 = 不推进。
/// @param rangeLo 本页齐全区间的下界。
/// @param rangeHi 本页齐全区间的上界；rangeHi<rangeLo = 不登记。
/// @return 是否全部提交成功。NO 时游标与区间都没动，调用方应从原位重拉。
- (BOOL)saveIncomingPage:(NSArray<IMMessageModel *> *)messages
               advanceTo:(int64_t)advanceTo
                 rangeLo:(int64_t)rangeLo
                 rangeHi:(int64_t)rangeHi;

/// 本地**尾段**的最近 limit 条（进会话首窗 / 点 ↓ 回到末尾都走它）。
///
/// 与 `latestMessagesForConv:limit:` 只差一条，但很要紧：**先按区间清单圈出"包含本地最新一条的
/// 那一段"，段外的一律不要**。直接取最后 N 行，在有缺口的会话里会把缺口另一侧的旧岛一并取出——
/// 本地只剩 `{1}` 与 `[29802,30001]` 时首窗就横跨缺口，两段不相邻的历史被静默拼在一起；
/// 更糟的是窗口里最早一条成了 seq 1，`hasMoreAbove` 的 `earliest != 1` 判据据此认定"到会话开头了"，
/// 中间几万条从此**永久**翻不回来。（Web 侧同一个坑表现为首屏只剩一条系统消息，2026-09-03 实测。）
///
/// 清单为空（老库，没登记过任何区间）时退回 `latestMessagesForConv:`，行为与改造前逐字一致。
- (NSArray<IMMessageModel *> *)latestContiguousMessagesForConv:(NSString *)convID limit:(NSInteger)limit;

/// 段内向上翻一页：只取**与 beforeConvSeq 同属一段**的更早消息；该段之前没有了就返回空。
///
/// `messagesForConv:beforeConvSeq:limit:` 没有下界。段内剩余不足一页时它会径直翻过缺口，
/// 把缺口另一侧的旧岛捞回来接到窗口顶部——两段不相邻的历史被静默拼在一起，
/// 界面照常、时间戳看着也递增，只是中间少了几万条且没有任何提示（OFFLINE_BACKLOG_DESIGN §4.7）。
/// 调用方据「返回空」判断本段到头，改问服务端。
- (NSArray<IMMessageModel *> *)contiguousMessagesForConv:(NSString *)convID
                                           beforeConvSeq:(int64_t)beforeConvSeq
                                                   limit:(NSInteger)limit;

/// 段内向下翻一页：只取**与 afterConvSeq 同属一段**的更新消息；该段之后没有了就返回空。
/// 与 `contiguousMessagesForConv:beforeConvSeq:limit:` 对称，理由同——本地按段存，
/// 无上界的查询会径直翻过缺口把下一段接上来，两段不相邻的历史被静默拼在一起。
/// 调用方据「返回空」判断本段到头，改问服务端。
- (NSArray<IMMessageModel *> *)contiguousMessagesForConv:(NSString *)convID
                                            afterConvSeq:(int64_t)afterConvSeq
                                                   limit:(NSInteger)limit;

/// 以下这组原先声明在 IMDatabase.h（主类接口）里，实现却在本分类——编译器据此判定
/// 「category 实现了一个主类也会实现的方法」（-Wobjc-protocol-method-implementation），
/// 而这种重复在运行期谁生效是未定义的。声明与实现放同一处才对。
/// 「本地有哪几段」目录（IMServer/docs/design/OFFLINE_BACKLOG_DESIGN.md §4.2）。
///
/// 本地库从「整本账的副本」变成「看过的页的复印件 + 一张目录」之后，
/// **「本地齐不齐」第一次成为一个可以查询的事实**——此前代码只能默认它齐全，
/// 而那个默认在离线积压被留成缺口后就是错的（且不报错，只是答案悄悄不对）。
///
/// 返回按 lo 升序、互不相交、相邻已合并的区间数组；每项是 `@[@(lo), @(hi)]`（闭区间）。
- (NSArray<NSArray<NSNumber *> *> *)rangesForConv:(NSString *)convID;

/// 登记一段「这段我已齐全」，返回合并后的新清单。
///
/// **调用契约**：只在这一段消息**全部落库成功之后**才调用。区间断言的是"这段我齐全"，
/// 提前登记等于宣称拿到了其实没拿到的消息，上层据此跳过补拉、那段就永久漏了。
/// 与 `synced_conv_seq` 的老约束是同一条，只是从「一个位点」推广到「一组区间」。
- (NSArray<NSArray<NSNumber *> *> *)registerRangeInConv:(NSString *)convID from:(int64_t)lo to:(int64_t)hi;

/// 服务端会话最新位点的本地快照（sync_resp.head_conv_seq / conv_bump.latest_seq）。
/// 判「本地齐不齐」要拿它当上界；↓N 计数也用它，不数本地。
///
/// **两个坑**（2026-09-03 首次真跑单测才暴露，此前一直静默失效）：
/// ① 存在 `im_conversation_local` 行上，而 `writeCachedConversations` 是 DELETE 全表再 INSERT，
///    列表每刷新一次就走一遍——那边必须把 head 一起保下来，否则它永远回到 0；
/// ② 写入是 UPDATE 不是 UPSERT，会话缓存行还没建时这次 head 就丢了（只留日志）。刻意不插占位行：
///    会话列表是 `SELECT * FROM im_conversation_local` 直出，凭空一行会变成界面上的无名空会话。
/// head 回到 0 的后果不报错也不崩：`isConvComplete:` 因"上界未知"一律判齐全，
/// 「有缺口」那条分支从此不生效——↓N 永远数本地（必然偏小）、进会话也不会去补那一页。
- (int64_t)headConvSeqForConv:(NSString *)convID;
- (void)updateHeadConvSeq:(int64_t)head forConv:(NSString *)convID;

/// 区间清单是否**用同一段**完整覆盖 [lo, hi]（跨两段说明中间有缺口，不算覆盖）。
///
/// 与 `isConvComplete:` 的区别是**问的范围不同**：那个问"从 1 到 head 全有吗"，
/// 这个问"我关心的这一段全有吗"。↓N 要的正是后者——"已滚入位点到 head 之间还缺不缺东西"，
/// 会话开头缺几万条与这个问题无关。
- (BOOL)conv:(NSString *)convID coversFrom:(int64_t)lo to:(int64_t)hi;

/// 本地对该会话是否**齐全**：区间清单从 1 一路连续覆盖到 head。
/// head 未知（0）时按齐全处理——没有上界就无从判断缺什么，宁可保持改造前的行为。
- (BOOL)isConvComplete:(NSString *)convID;
@end

/// 内部访问器（ivar 对 category 不可见）。仅供本类的分文件实现使用。
@interface IMDatabase (RangesPrivate)
- (FMDatabaseQueue *)dbQueue;
- (NSString *)ownerUserID;   ///< 当前账号（本地库按 owner 隔离，所有查询都要带它）
- (BOOL)writeIncomingMessage:(IMMessageModel *)message
                       owner:(NSString *)owner
      advancingSyncedConvSeq:(int64_t)syncedConvSeq
                        inDB:(FMDatabase *)db;
@end

NS_ASSUME_NONNULL_END
