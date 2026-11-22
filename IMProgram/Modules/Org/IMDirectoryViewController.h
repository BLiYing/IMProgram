//  IMDirectoryViewController.h
//  组织架构（TENANT_DESIGN v2 §8.2，交互稿 TENANT_CLIENT_UX_SKETCH I-7 / I-8）。
//  一个类两种页：公司列表，或某家公司下的部门页（子部门 + 直属成员，可递归 push）。
//  可见范围由服务端按身份裁剪（客服 / 客户视角只出客服），本页不再过滤。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDirectoryViewController : UIViewController

/// 入口：先拉单位；只有 1 个单位时直接显示它的顶层部门（不经过单位列表）。
- (instancetype)initRootWithHost:(NSString *)host userID:(NSString *)userID;

/// 部门页；deptID 传 "root" = 单位顶层。title 为空时用服务端回的名字。
- (instancetype)initWithHost:(NSString *)host userID:(NSString *)userID
                      unitID:(NSString *)unitID deptID:(NSString *)deptID title:(nullable NSString *)title;

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// 部门页面包屑的一段（单位名 + 各级部门），点了回到那一级。
@property (nonatomic, copy, readonly) NSString *unitID;
@property (nonatomic, copy, readonly) NSString *deptID;

@end

/// 纯函数（单测）：部门页响应 → 面包屑 [(dept_id, name)]，首段是单位顶层（dept_id = "root"）。
FOUNDATION_EXPORT NSArray<NSArray<NSString *> *> *IMDirectoryCrumbs(NSDictionary *page);

/// 点组织架构 / 集团搜索里的成员 → 资料页（免好友直聊时资料页自己会给「消息」）。
FOUNDATION_EXPORT UIViewController *IMDirectoryProfileController(NSString *host, NSString *userID, NSDictionary *member);

@class IMContactCell;

/// 成员行尾的「客服」小标。
FOUNDATION_EXPORT UIView *IMDirectoryCSTagView(void);

/// 成员行（组织架构与集团搜索共用）：名字、头像、副标题（空则无）、客服小标。
FOUNDATION_EXPORT void IMDirectoryConfigureMemberCell(IMContactCell *cell, NSDictionary *member, NSString *_Nullable subtitle);

NS_ASSUME_NONNULL_END
