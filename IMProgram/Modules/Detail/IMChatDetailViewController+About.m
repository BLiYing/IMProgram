//
//  IMChatDetailViewController+About.m
//  群资料页的「公告 / 简介 / 大群说明」卡（全员只读，G1 修·决策 17）。
//
//  从主文件抽出：加这张卡的第三行（大群说明）时主文件触了 1500 行门禁（CODING_STYLE §7）。
//  这张卡本就是个自洽单元——行类型、组装、渲染、点击展开都在一处，抽出来反而更好读。
//  主文件只保留分区骨架里的调用点（sectionLayout / 行数 / 行高 / 出 cell / 点击分发）。
//

#import "IMChatDetailViewController+Private.h"
#import "IMGroupInfo.h"          // 私有头里 IMGroupInfo 只是前向声明，本文件要读它的属性
#import "IMGroupTextViewController.h"

/// 卡内行类型（顺序即展示顺序）。
typedef NS_ENUM(NSInteger, IMDetailAboutRow) {
    IMDetailAboutRowAnnouncement = 0, ///< 群公告（非空才显）
    IMDetailAboutRowIntro,            ///< 群简介（非空才显）
    IMDetailAboutRowSuper,            ///< 大群说明（is_super 恒显；文案见 SUPERGROUP_DESIGN §4.1）
};

@implementation IMChatDetailViewController (About)

- (NSArray<NSNumber *> *)aboutRowKinds {
    NSMutableArray<NSNumber *> *rows = [NSMutableArray array];
    if (!self.isGroup) { return rows; }
    if (self.group.announcement.length > 0) { [rows addObject:@(IMDetailAboutRowAnnouncement)]; }
    if (self.group.intro.length > 0) { [rows addObject:@(IMDetailAboutRowIntro)]; }
    // 大群说明：**只要是大群就恒显**，不像公告/简介那样"非空才显"。
    // 头部副标题的「· 大群」只让人**察觉**，这一行才**解释**为什么已读双勾/正在输入没了。
    // 它同时把整个 About 区撑起来了——一个既没公告也没简介的大群，靠公告/简介的条件
    // 这张卡根本不出现，而那恰恰是最需要解释的场景。
    if (self.group.isSuper) { [rows addObject:@(IMDetailAboutRowSuper)]; }
    return rows;
}

/// 大群说明全文（**升级后**时态）。三条与 docs/design/SUPERGROUP_DESIGN.md §4.1 同源——
/// 那一节是三端唯一真相源（后台确认框 / iOS 满员告知行 / Web 满员告知块 / 本行 / Web 对应行）。
/// 改文案时按该节搜一圈，几处一起改。
///
/// **不写具体人数**：上限是部署级配置，本行拿不到 server-config 的真值（详情页不依赖它），
/// 硬编码就会与服务端口径分叉。满员告知行能写数字，是因为它本来就要判 serverConfig 才显示。
- (NSString *)superGroupNoticeBody {
    return @"1. 成员上限为超级群配额；成员列表分页加载，搜索走服务端（不是本地过滤）\n"
           @"2. 已读回执、「正在输入」、成员在线态已关闭\n"
           @"3. 成员进出不再产生群消息（「X 加入了群聊」「A 将 B 移出群聊」等）\n"
           @"4. 群规模所致，无法改回普通群";
}

/// 折行/连续空白压成单行预览（详情页卡与横幅一致）。
- (NSString *)aboutSingleLinePreview:(NSString *)text {
    NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *part in parts) { if (part.length > 0) { [kept addObject:part]; } }
    return [kept componentsJoinedByString:@" "];
}

- (UITableViewCell *)aboutCell:(UITableView *)tv row:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self aboutRowKinds];
    IMDetailAboutRow kind = (row < (NSInteger)kinds.count) ? (IMDetailAboutRow)kinds[row].integerValue : IMDetailAboutRowAnnouncement;
    UITableViewCell *cell = [self dequeueStyledCell:UITableViewCellStyleSubtitle reuseID:@"dSub" inTable:tv];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (kind == IMDetailAboutRowAnnouncement) {
        cell.imageView.image = [UIImage systemImageNamed:@"megaphone"];
        cell.textLabel.text = @"群公告";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.announcement];
    } else if (kind == IMDetailAboutRowSuper) {
        cell.imageView.image = [UIImage systemImageNamed:@"person.3.sequence"]; // 与满员告知行同图标
        cell.textLabel.text = @"大群";
        // N 数的是**被关掉的能力**：已读回执 / 正在输入 / 在线态 / 进出群消息 = 4。
        // 全文里的第 1、4 条（上限、不可撤销）不是"关闭"，不计入。
        // 改 superGroupNoticeBody 的列表时**记得同步这个数**（前身写死 3，加第 3 条时就对不上了）。
        cell.detailTextLabel.text = @"已关闭 4 项能力";
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"];
        cell.textLabel.text = @"群简介";
        cell.detailTextLabel.text = [self aboutSingleLinePreview:self.group.intro];
    }
    return cell;
}

/// 卡内点击：三行都展开成**同一个**全文视图。
/// 刻意不给大群说明用 alert——同一张卡里两种展开方式会让人以为是两类东西。
- (void)handleAboutTapAtRow:(NSInteger)row {
    NSArray<NSNumber *> *kinds = [self aboutRowKinds];
    if (row >= (NSInteger)kinds.count) { return; }
    switch ((IMDetailAboutRow)kinds[row].integerValue) {
        case IMDetailAboutRowAnnouncement:
            [IMGroupTextViewController presentFrom:self title:@"群公告"
                                          subtitle:[IMGroupTextViewController announceSubtitleForMillis:self.group.announcementAt]
                                              body:self.group.announcement];
            break;
        case IMDetailAboutRowSuper:
            [IMGroupTextViewController presentFrom:self title:@"大群"
                                          subtitle:@"本群成员规模较大，部分实时能力已关闭"
                                              body:[self superGroupNoticeBody]];
            break;
        case IMDetailAboutRowIntro:
            [IMGroupTextViewController presentFrom:self title:@"群简介" subtitle:nil body:self.group.intro];
            break;
    }
}

@end
