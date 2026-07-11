//  IMFavoritesViewController.m

#import "IMFavoritesViewController.h"
#import "IMHTTPService.h"

@implementation IMFavoritesViewController {
    NSArray<NSDictionary *> *_items; // 每项含 id/content/content_type/...
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { self.title = @"收藏消息"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _items = @[];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"fav"];
    [self reload];
}

- (void)reload {
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (token.length == 0) { return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService favoritesWithToken:token completion:^(NSArray<NSDictionary *> *favorites, NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { return; }
        self->_items = error ? @[] : (favorites ?: @[]);
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"fav" forIndexPath:indexPath];
    NSDictionary *f = _items[(NSUInteger)indexPath.row];
    NSString *content = [f[@"content"] isKindOfClass:[NSString class]] ? f[@"content"] : @"";
    cell.textLabel.text = content;
    cell.textLabel.numberOfLines = 2;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"删除" handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        [ws deleteAt:indexPath done:completionHandler];
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

- (void)deleteAt:(NSIndexPath *)indexPath done:(void (^)(BOOL))done {
    if (indexPath.row >= (NSInteger)_items.count) { done(NO); return; }
    NSDictionary *f = _items[(NSUInteger)indexPath.row];
    int64_t fid = [f[@"id"] respondsToSelector:@selector(longLongValue)] ? [f[@"id"] longLongValue] : 0;
    NSString *token = IMHTTPService.sharedService.currentToken;
    if (fid <= 0 || token.length == 0) { done(NO); return; }
    __weak typeof(self) ws = self;
    [IMHTTPService.sharedService deleteFavoriteWithToken:token favoriteID:fid completion:^(NSError *error) {
        __strong typeof(ws) self = ws;
        if (!self) { done(NO); return; }
        if (error) { done(NO); return; }
        NSMutableArray *m = [self->_items mutableCopy];
        if (indexPath.row < (NSInteger)m.count) { [m removeObjectAtIndex:(NSUInteger)indexPath.row]; }
        self->_items = m;
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        done(YES);
    }];
}

@end
