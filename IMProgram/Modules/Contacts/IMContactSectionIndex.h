//  IMContactSectionIndex.h
//  联系人 A–Z 分组索引（纯数据）：把 IMUserCard 列表按姓名拼音首字母分桶，
//  产出分组结果 + 右侧索引尺标题 + 标题↔section 映射。通讯录页与选好友页共用，
//  只复用「分桶/拼音/索引标题」这层计算；各页表格 plumbing（section 偏移）各写各的。

#import <Foundation/Foundation.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMContactSectionIndex : NSObject

/// 按 displayName 拼音首字母分桶（A–Z 升序，非字母/取不到归 "#" 排最后），组内按名字本地化升序。
/// **同步**计算：名单小（选人页搜索结果）用它；上千人的全量名单请用 `buildWithCards:completion:`。
- (instancetype)initWithCards:(nullable NSArray<IMUserCard *> *)cards;

/// 异步构建：显示名在**调用线程**取快照（应在主线程调用），拼音分组在后台串行队列算，completion 回主线程。
/// 为什么要有：拼音转换约 65µs/人（Mac 实测），2000 人的通讯录整表重建会把主线程占住数百毫秒，
/// 表现为切 Tab 卡顿。拼音结果进程内缓存，名字没变的重建几乎零成本。
/// 调用方连发时须自行丢弃过期结果（队列串行，结果按发起顺序回来）。
+ (void)buildWithCards:(nullable NSArray<IMUserCard *> *)cards
            completion:(void (^)(IMContactSectionIndex *index))completion;

/// 分组字母（如 @[@"A", @"B", @"#"]），与右侧纵向索引尺一一对应；无好友时为空数组。
@property (nonatomic, readonly) NSArray<NSString *> *titles;

- (NSInteger)numberOfSections;
- (NSInteger)numberOfRowsInSection:(NSInteger)section;
- (NSString *)titleForSection:(NSInteger)section;
- (nullable IMUserCard *)cardAtSection:(NSInteger)section row:(NSInteger)row;

/// 名字 → 分组首字母（拼音转拉丁取首字母大写；非 A–Z 归 "#"）。公开供复用/测试。
+ (NSString *)sectionKeyForName:(nullable NSString *)name;

@end

NS_ASSUME_NONNULL_END
