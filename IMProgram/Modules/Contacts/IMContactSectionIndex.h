//  IMContactSectionIndex.h
//  联系人 A–Z 分组索引（纯数据）：把 IMUserCard 列表按姓名拼音首字母分桶，
//  产出分组结果 + 右侧索引尺标题 + 标题↔section 映射。通讯录页与选好友页共用，
//  只复用「分桶/拼音/索引标题」这层计算；各页表格 plumbing（section 偏移）各写各的。

#import <Foundation/Foundation.h>

@class IMUserCard;

NS_ASSUME_NONNULL_BEGIN

@interface IMContactSectionIndex : NSObject

/// 按 displayName 拼音首字母分桶（A–Z 升序，非字母/取不到归 "#" 排最后），组内按名字本地化升序。
- (instancetype)initWithCards:(nullable NSArray<IMUserCard *> *)cards;

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
