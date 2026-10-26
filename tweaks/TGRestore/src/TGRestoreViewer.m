//
//  TGRestoreViewer.m
//  TGRestore — viewer UI & floating button
//

#import "TGRestoreViewer.h"
#import "TGRestore.h"
#import "TGRestoreStore.h"

static NSString * const TGRestoreCellIdentifier = @"TGRestoreCellIdentifier";

@interface TGRestoreViewer ()
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) TGRestoreStore *store;
@end

@implementation TGRestoreViewer

+ (instancetype)shared {
    static TGRestoreViewer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TGRestoreViewer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _store = [TGRestoreStore shared];
    }
    return self;
}

+ (void)install {
    TGRestoreViewer *s = [TGRestoreViewer shared];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:s
               selector:@selector(appDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:Nil];
    [s addButtonToKeyWindow];
}

- (void)appDidBecomeActive:(NSNotification *)notification {
    [self addButtonToKeyWindow];
}

- (void)addButtonToKeyWindow {
    if (![TGRestore isTelegram]) {
        return;
    }
    if (![TGRestore buttonVisible]) {
        [self removeButton];
        return;
    }
    UIWindow *w = [TGRestore keyWindow];
    if (w == Nil) {
        return;
    }
    [self addButtonToWindow:w];
}

- (void)addButtonToWindow:(UIWindow *)w {
    if (self.button && self.button.superview == w) {
        return;
    }
    [self removeButton];

    CGFloat topInset = 44.0;
    if (@available(iOS 11.0, *)) {
        topInset = w.safeAreaInsets.top + 8.0;
        if (topInset < 44.0) topInset = 44.0;
    }

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(w.bounds.size.width - 52.0, topInset, 44.0, 44.0);
    b.backgroundColor = [UIColor colorWithRed:0.13 green:0.55 blue:0.95 alpha:0.95];
    b.layer.cornerRadius = 22.0;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.25;
    b.layer.shadowRadius = 4.0;
    b.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    [b setTitle:@"👁" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(buttonTapped)];
    [b addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                              action:@selector(buttonLongPressed)];
    [b addGestureRecognizer:longPress];

    b.tag = 1;
    self.button = b;
    [w addSubview:b];
}

- (void)removeButton {
    if (self.button) {
        [self.button removeFromSuperview];
        self.button = Nil;
    }
}

- (void)buttonLongPressed {
    [self openViewer];
}

- (void)buttonTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TGRestore"
                                                                    message:@"👁 Restored messages come from your local on-device cache. Nothing is sent anywhere."
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Show restored messages"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self openViewer];
    }]];

    if ([TGRestore captureEnabled]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Pause capture"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [TGRestore setCaptureEnabled:NO];
            [self addButtonToKeyWindow];
        }]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:@"Resume capture"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [TGRestore setCaptureEnabled:YES];
        }]];
    }

    if ([TGRestore restoreEnabled]) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Hide restored bubbles"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [TGRestore setRestoreEnabled:NO];
        }]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:@"Show restored bubbles"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            [TGRestore setRestoreEnabled:YES];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Clear cache"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Clear cache?"
                                                                            message:@"All captured message texts stored by TGRestore on this device will be deleted."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:Nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Delete everything"
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction *action) {
            [[TGRestoreStore shared] clearAll];
        }]];
        UIViewController *vc = [self topViewController];
        if (vc) {
            if (@available(iOS 11.0, *) && [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
                confirm.popoverPresentationController.sourceView = self.button;
            }
            [vc presentViewController:confirm animated:YES completion:Nil];
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Hide button"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [TGRestore setButtonVisible:NO];
        [self removeButton];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:Nil]];

    if (@available(iOS 11.0, *) && [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.button;
    }

    UIViewController *vc = [self topViewController];
    if (vc) {
        [vc presentViewController:alert animated:YES completion:Nil];
    }
}

- (UIViewController *)topViewController {
    UIWindow *w = [TGRestore keyWindow];
    if (w == Nil) {
        return Nil;
    }
    UIViewController *vc = [TGRestore viewControllerForView:w];
    if (vc == Nil) {
        vc = w.rootViewController;
    }
    while (vc.presentedViewController && ![vc.presentedViewController isKindOfClass:[UIAlertController class]]) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = [(UINavigationController *)vc visibleViewController];
    }
    return vc;
}

- (void)overlayTapped {
    [self openViewer];
}

- (void)openViewer {
    UIViewController *vc = [self topViewController];
    if (vc == Nil) {
        return;
    }
    TGRestoreViewerController *viewer = [[TGRestoreViewerController alloc] initWithStore:[TGRestoreStore shared]];
    viewer.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [vc presentViewController:viewer animated:YES completion:Nil];
}

@end

// ---------------------------------------------------------------------------
// Viewer controller
// ---------------------------------------------------------------------------

@interface TGRestoreViewerController ()
@property (nonatomic, strong) TGRestoreStore *store;
- (void)exportAll;
- (void)clearAll;
@end

@implementation TGRestoreViewerController

- (instancetype)initWithStore:(TGRestoreStore *)store {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _store = store;
        self.title = @"TGRestore";
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                          target:self
                                                                                          action:@selector(exportAll)];
        UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                target:Nil
                                                                                action:Nil];
        UIBarButtonItem *trash = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                              target:self
                                                                              action:@selector(clearAll)];
        self.navigationItem.rightBarButtonItems = @[flexible, trash, flexible, self.navigationItem.rightBarButtonItem];
        [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:TGRestoreCellIdentifier];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.records = [self.store allRecords];
    [self.tableView reloadData];
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.records.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, tableView.bounds.size.width, 70.0)];
    header.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1.0];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 10.0, tableView.bounds.size.width - 32.0, 22.0)];
    title.text = @"TGRestore — captured & restored messages";
    title.font = [UIFont boldSystemFontOfSize:15.0];
    title.textColor = UIColor.blackColor;
    [header addSubview:title];

    NSUInteger captured = self.records.count;
    NSUInteger restored = 0;
    for (NSDictionary *rec in self.records) {
        if ([rec[@"restored"] boolValue]) {
            restored++;
        }
    }
    UILabel *stats = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 34.0, tableView.bounds.size.width - 32.0, 20.0)];
    stats.text = [NSString stringWithFormat:@"Cached: %lu · Restored: %lu", (unsigned long)captured, (unsigned long)restored];
    stats.font = [UIFont systemFontOfSize:12.0];
    stats.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.45 alpha:1.0];
    [header addSubview:stats];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 54.0, tableView.bounds.size.width - 32.0, 16.0)];
    hint.text = @"Restored = shown back to you after deletion";
    hint.font = [UIFont italicSystemFontOfSize:11.0];
    hint.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
    [header addSubview:hint];

    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 70.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:TGRestoreCellIdentifier];
    if (cell == Nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:TGRestoreCellIdentifier];
    }

    NSDictionary *rec = self.records[indexPath.row];
    NSString *text = rec[@"text"] ?: @"";
    NSString *chat = rec[@"chat"] ?: @"Unknown chat";
    NSString *side = rec[@"side"] ?: @"?";
    NSNumber *ts = rec[@"ts"];

    NSString *arrow = [side isEqualToString:@"out"] ? @"▶" : [side isEqualToString:@"in"] ? @"◀" : @"•";
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@ · %@", arrow, chat, [self stringForTimestamp:ts]];
    cell.textLabel.font = [UIFont systemFontOfSize:14.0];

    NSString *preview = text;
    if (preview.length > 80) {
        preview = [preview substringToIndex:80] + @"…";
    }
    cell.detailTextLabel.text = preview;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if ([rec[@"restored"] boolValue]) {
        UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 72.0, 20.0)];
        badge.backgroundColor = [UIColor colorWithRed:0.13 green:0.55 blue:0.95 alpha:0.9];
        badge.layer.cornerRadius = 10.0;
        UILabel *badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 72.0, 20.0)];
        badgeLabel.text = @"RESTORED";
        badgeLabel.textColor = UIColor.whiteColor;
        badgeLabel.font = [UIFont boldSystemFontOfSize:9.0];
        badgeLabel.textAlignment = NSTextAlignmentCenter;
        [badge addSubview:badgeLabel];
        cell.accessoryView = badge;
    } else {
        cell.accessoryView = Nil;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *rec = self.records[indexPath.row];
    NSString *text = rec[@"text"] ?: @"";
    NSString *chat = rec[@"chat"] ?: @"";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:chat
                                                                    message:text
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Copy"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:text ?: @"" forPasteboardType:@"public.plain-text"];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Share…"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        NSString *shareText = [NSString stringWithFormat:@"[TGRestore] %@\n%@", chat, text];
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[shareText]
                                                                               applicationActivities:Nil];
        share.popoverPresentationController.sourceView = self.view;
        [self presentViewController:share animated:YES completion:Nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Delete from cache"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *action) {
        [[TGRestoreStore shared] deleteRecordForText:text];
        self.records = [self.store allRecords];
        [self.tableView reloadData];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:Nil]];

    if (@available(iOS 11.0, *) && [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
    }

    [self presentViewController:alert animated:YES completion:Nil];
}

#pragma mark - Toolbar

- (void)exportAll {
    NSMutableString *report = [NSMutableString string];
    for (NSDictionary *rec in self.records) {
        NSNumber *ts = rec[@"ts"];
        [report appendFormat:@"[%@] %@ %@: %@\n",
         [self stringForTimestamp:ts], rec[@"side"] ?: @"?", rec[@"chat"] ?: @"", rec[@"text"] ?: @""];
    }
    if (report.length == 0) {
        report = @"No messages captured yet.";
    }
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[report]
                                                                               applicationActivities:Nil];
    share.popoverPresentationController.sourceView = self.view;
    [self presentViewController:share animated:YES completion:Nil];
}

- (void)clearAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear TGRestore cache?"
                                                                    message:@"Every captured message text will be deleted from this device."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:Nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete everything"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *action) {
        [[TGRestoreStore shared] clearAll];
        self.records = [self.store allRecords];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:Nil];
}

- (NSString *)stringForTimestamp:(NSNumber *)ts {
    if (ts == Nil) {
        return @"";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts.doubleValue];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"MM/dd HH:mm";
    return [fmt stringFromDate:date];
}

@end
