//
//  TGRestoreOverlay.m
//  TGRestore — restored-message bubble overlays
//

#import "TGRestoreOverlay.h"
#import "TGRestoreViewer.h"

static NSTimeInterval TGOverlayLifetime = 30.0;

@interface UIView (TGRestoreAnimate)
- (void)animateIn;
@end

@interface TGRestoreOverlay ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NSMutableDictionary *> *> *overlays;
@end

@implementation TGRestoreOverlay

+ (instancetype)shared {
    static TGRestoreOverlay *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TGRestoreOverlay alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _overlays = [NSMutableDictionary dictionary];
    }
    return self;
}

+ (void)showRestoredText:(NSString *)text
                   chat:(NSString *)chat
                   side:(NSString *)side
                  frame:(CGRect)frame
           inCollectionView:(UICollectionView *)cv
{
    if (text == Nil || text.length == 0 || cv == Nil) {
        return;
    }

    // Pick a size that fits the collection view and the text.
    CGFloat maxWidth = CGRectGetWidth(cv.bounds) - 24.0;
    CGFloat width = CGRectGetWidth(frame);
    if (!(width > 0)) width = 120.0;
    width = MIN(width, maxWidth);
    width = MAX(width, 80.0);

    UILabel *measure = [UILabel new];
    measure.font = [UIFont systemFontOfSize:15.0];
    measure.numberOfLines = 0;
    measure.lineBreakMode = NSLineBreakModeByWordWrapping;
    measure.text = text;
    CGSize fit = [measure sizeThatFits:CGSizeMake(width - 24.0, CGFLOAT_MAX)];
    CGFloat height = MIN(fit.height + 24.0, 140.0);
    if (!(height > 0)) height = 40.0;

    // Clamp into the collection view bounds.
    CGFloat x = CGRectGetMinX(frame);
    if (x < 4.0) x = 4.0;
    CGFloat y = CGRectGetMinY(frame);
    if (y < 4.0) y = 4.0;
    CGFloat maxY = CGRectGetHeight(cv.bounds) - height - 4.0;
    if (y > maxY) y = maxY;

    CGRect bubbleRect = CGRectMake(x, y, width, height);

    BOOL outgoing = [side isEqualToString:@"out"];

    UIView *bubble = [UIView new];
    bubble.frame = bubbleRect;
    bubble.backgroundColor = outgoing
        ? [UIColor colorWithRed:0.204 green:0.722 blue:1.000 alpha:1.0]
        : [UIColor whiteColor];
    bubble.layer.cornerRadius = 16.0;
    bubble.layer.borderWidth = outgoing ? 0.0 : 0.5;
    bubble.layer.borderColor = [UIColor colorWithRed:0.80 green:0.80 blue:0.80 alpha:1.0].CGColor;
    bubble.layer.shadowColor = UIColor.blackColor.CGColor;
    bubble.layer.shadowOpacity = 0.12;
    bubble.layer.shadowRadius = 4.0;
    bubble.layer.shadowOffset = CGSizeMake(0.0, 1.0);

    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:15.0];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakModeByWordWrapping;
    label.text = text;
    label.textColor = outgoing ? [UIColor whiteColor] : UIColor.blackColor;
    label.frame = UIEdgeInsetsInsetRect(bubble.bounds, UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0));
    [bubble addSubview:label];

    // Badge "👁 restored"
    UILabel *badge = [UILabel new];
    badge.font = [UIFont boldSystemFontOfSize:9.0];
    badge.text = [NSString stringWithFormat:@"👁 %@", chat.length > 0 ? chat : @"restored"];
    badge.textColor = UIColor.whiteColor;
    badge.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:0.92];
    badge.layer.cornerRadius = 10.0;
    CGSize badgeSize = [badge sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    badge.frame = CGRectMake(bubbleRect.maxX - badgeSize.width - 2.0, bubbleRect.minY - badgeSize.height - 6.0,
                              badgeSize.width + 12.0, badgeSize.height);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[TGRestoreViewer shared]
                                                                        action:@selector(overlayTapped)];
    tap.numberOfTapsRequired = 1;
    [bubble addGestureRecognizer:tap];

    [cv addSubview:bubble];
    [cv addSubview:badge];

    [bubble animateIn];
    [badge animateIn];

    // Register + auto-dismiss
    NSNumber *key = @((NSInteger)(uintptr_t)cv);
    NSMutableArray *list = self.overlays[key] ?: [NSMutableArray array];
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"bubble"] = bubble;
    entry[@"badge"] = badge;
    NSNumber *capturedKey = key;
    entry[@"timer"] = [NSTimer scheduledTimerWithTimeInterval:TGOverlayLifetime
                                                      repeats:NO
                                                        block:^(NSTimer *timer) {
                                        TGRestoreOverlay *s = [TGRestoreOverlay shared];
                                        NSMutableArray *l = s.overlays[capturedKey];
                                        if (l) {
                                            [s removeEntry:l];
                                            [s.overlays removeObjectForKey:capturedKey];
                                        }
                                    }];
    [list addObject:entry];
    self.overlays[key] = list;
}

- (void)removeEntry:(NSMutableArray *)list {
    for (NSDictionary *entry in list) {
        UIView *bubble = entry[@"bubble"];
        UIView *badge = entry[@"badge"];
        NSTimer *timer = entry[@"timer"];
        if (timer) [timer invalidate];
        if ([bubble isKindOfClass:[UIView class]]) {
            [bubble removeFromSuperview];
        }
        if ([badge isKindOfClass:[UIView class]]) {
            [badge removeFromSuperview];
        }
    }
    [list removeAllObjects];
}

+ (void)clearAllInCollectionView:(UICollectionView *)cv {
    if (cv == Nil) return;
    TGRestoreOverlay *s = [TGRestoreOverlay shared];
    NSNumber *key = @((NSInteger)(uintptr_t)cv);
    NSMutableArray *list = s.overlays[key];
    if (list) {
        [s removeEntry:list];
        [s.overlays removeObjectForKey:key];
    }
}

+ (void)clearAll {
    TGRestoreOverlay *s = [TGRestoreOverlay shared];
    for (NSNumber *key in [s.overlays allKeys]) {
        NSMutableArray *list = s.overlays[key];
        [s removeEntry:list ?: [NSMutableArray array]];
    }
    [s.overlays removeAllObjects];
}

@end

@implementation UIView (TGRestoreAnimate)
- (void)animateIn {
    self.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1.0;
    }];
}
@end
