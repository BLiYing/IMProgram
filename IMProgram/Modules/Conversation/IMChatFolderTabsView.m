//  IMChatFolderTabsView.m

#import "IMChatFolderTabsView.h"
#import "IMLiquidSegmentedControl.h"
#import "IMChatFolder.h"
#import "IMChatFolderLogic.h"
#import "IMConversation.h"
#import "IMUnreadBadge.h"
#import "IMTimeUtil.h"
#import "IMLocalization.h"

// 控件 40 + 下留白 6；上留白 0——搜索入口容器自带 6pt 底部留白，于是「搜索框↔Tab」与「Tab↔首行」间距相等（各 6）。
const CGFloat kIMChatFolderTabsHeight = 46;

@implementation IMChatFolderTabsView {
    IMLiquidSegmentedControl *_segmented;
    NSArray<IMChatFolder *> *_folders;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.systemBackgroundColor; // 吸顶时盖住下面滚动的会话行
        _segmented = [IMLiquidSegmentedControl new];
        [_segmented addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_segmented];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        lp.minimumPressDuration = 0.45;
        [_segmented addGestureRecognizer:lp];
        _folders = @[];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 控件占满行宽（左右 16），底轨贴合内容并在其中居中（IMLiquidSegmentedControl 内部处理）。
    _segmented.frame = CGRectMake(16, 0, MAX(0, CGRectGetWidth(self.bounds) - 32), kIMChatFolderTabsHeight - 6);
}

- (void)configureWithFolders:(NSArray<IMChatFolder *> *)folders
               conversations:(NSArray<IMConversation *> *)convs
               selectedIndex:(NSInteger)selectedIndex {
    _folders = [folders copy] ?: @[];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:IMLocalized(@"folder.tab.all")];
    NSMutableArray<NSString *> *badges = [NSMutableArray array];
    NSMutableArray<NSNumber *> *muted = [NSMutableArray array];
    int64_t now = IMNowMillis();
    IMChatFolderBadge all = [IMChatFolderLogic badgeForConversations:convs inFolder:nil nowMillis:now];
    [badges addObject:IMUnreadBadgeText(all.count, NO)];
    [muted addObject:@(all.muted)];
    for (IMChatFolder *f in _folders) {
        [titles addObject:f.name];
        IMChatFolderBadge b = [IMChatFolderLogic badgeForConversations:convs inFolder:f nowMillis:now];
        [badges addObject:IMUnreadBadgeText(b.count, NO)];
        [muted addObject:@(b.muted)];
    }
    if (![_segmented.titles isEqualToArray:titles]) { _segmented.titles = titles; }
    [_segmented setBadgeTexts:badges muted:muted];
    [_segmented setSelectedIndex:MAX(0, MIN(selectedIndex, (NSInteger)titles.count - 1)) animated:NO];
    [self setNeedsLayout];
}

- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated {
    [_segmented setSelectedIndex:index animated:animated];
}

- (void)segmentChanged:(IMLiquidSegmentedControl *)sender {
    if (self.onSelect) { self.onSelect(sender.selectedIndex); }
}

- (void)longPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) { return; }
    NSInteger idx = [_segmented segmentIndexAtPoint:[gr locationInView:_segmented]];
    if (idx == NSNotFound || idx <= 0) { return; } // 「全部」不可编辑 / 删除
    NSInteger folderIndex = idx - 1;
    if (folderIndex >= (NSInteger)_folders.count) { return; }
    CGRect r = CGRectMake([gr locationInView:self].x - 1, 0, 2, kIMChatFolderTabsHeight - 6);
    if (self.onLongPressFolder) { self.onLongPressFolder(folderIndex, r); }
}

@end
