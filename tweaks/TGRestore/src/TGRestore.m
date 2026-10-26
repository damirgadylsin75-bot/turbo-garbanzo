//
//  TGRestore.m
//  TGRestore — environment & hierarchy helpers
//

#import "TGRestore.h"
#import "TGRestoreStore.h"
#import <objc/runtime.h>

NSString * const TGRestoreKeyCaptureEnabled = @"tgrestore.captureEnabled";
NSString * const TGRestoreKeyRestoreEnabled = @"tgrestore.restoreEnabled";
NSString * const TGRestoreKeyButtonVisible  = @"tgrestore.buttonVisible";

// Telegram bubble-class name fragments. Telegram's chat UI is a mix of Swift
// nodes (ASDisplayNode-backed) whose view classes still carry these names.
static NSString * const TGClassFragments[] = {
    @"ChatMessage", @"BubbleContent", @"MessageItem", @"ChatHistory", @"MessageCell"
};
#define TG_CLASS_FRAGMENT_COUNT (sizeof(TGClassFragments) / sizeof(TGClassFragments[0]))

static BOOL TGClassNameContains(Class cls, NSString *needle) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        NSString *name = NSStringFromClass(c);
        if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL TGClassNameMatchesBubble(Class cls) {
    for (NSUInteger i = 0; i < TG_CLASS_FRAGMENT_COUNT; i++) {
        if (TGClassNameContains(cls, TGClassFragments[i])) {
            return YES;
        }
    }
    return NO;
}

static BOOL TGLooksStructurallyLikeBubble(UIView *v) {
    if (v == Nil) return NO;
    CGRect b = v.bounds;
    if (CGRectIsNull(b) || b.size.width < 60.0 || b.size.height < 28.0) return NO;
    CGFloat radius = v.layer.cornerRadius;
    UIColor *bg = v.backgroundColor;
    if (bg == Nil || radius < 4.0) return NO;
    return YES;
}

static BOOL TGInsideCollectionView(UIView *v, UICollectionView *cv) {
    UIView *x = v;
    int depth = 0;
    while (x && depth < 14) {
        if (x == cv) return YES;
        if ([x isKindOfClass:[UICollectionView class]]) return YES;
        x = [x superview];
        depth++;
    }
    return NO;
}

@implementation TGRestore

+ (BOOL)isTelegram {
    static BOOL cached = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        cached = [bundleId rangeOfString:@"telegram" options:NSCaseInsensitiveSearch].location != NSNotFound;
    });
    return cached;
}

+ (BOOL)boolDefaultingTo:(BOOL)def key:(NSString *)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value == nil) return def;
    return [value boolValue];
}

+ (BOOL)captureEnabled  { return [self boolDefaultingTo:YES key:TGRestoreKeyCaptureEnabled]; }
+ (BOOL)restoreEnabled  { return [self boolDefaultingTo:YES key:TGRestoreKeyRestoreEnabled]; }
+ (BOOL)buttonVisible   { return [self boolDefaultingTo:YES key:TGRestoreKeyButtonVisible]; }

+ (void)setCaptureEnabled:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:TGRestoreKeyCaptureEnabled];
}

+ (void)setRestoreEnabled:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:TGRestoreKeyRestoreEnabled];
}

+ (void)setButtonVisible:(BOOL)v {
    [[NSUserDefaults standardUserDefaults] setBool:v forKey:TGRestoreKeyButtonVisible];
}

+ (BOOL)isNoiseText:(NSString *)text {
    if (text == Nil || text.length == 0) return YES;
    if (text.length < 2) return YES; // single glyph = probably a button glyph
    if (text.length > 4000) return YES;

    NSString *lower = [text lowercaseString];

    // Time-only strings like "9:41 AM" / "12:30"
    static NSArray *timePatterns = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timePatterns = @[
            [NSRegularExpression regularExpressionWithPattern:@"^\\d{0,2}:\\d{2}(\\s?[ap]m)?$" options:NSRegularExpressionCaseInsensitive error:nil]
        ];
    });
    for (NSRegularExpression *re in timePatterns) {
        if ([re numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0) {
            return YES;
        }
    }

    // Common service/system phrases. Short words match exactly (so a real
    // message "ok" is not filtered); phrases match by substring.
    static NSArray *noiseExact = @[
        @"typing", @"online", @"deleted", @"ok", @"okay", @"added", @"left", @"joined",
        @"invited", @"today", @"yesterday"
    ];
    static NSArray *noiseContains = @[
        @"pinned message", @"pinned deleted message", @"message was deleted",
        @"this message was deleted", @"deleted message", @"last seen",
        @"has photo", @"has video", @"has document", @"has audio", @"has voice message",
        @"has sticker", @"has location", @"has contact", @"has poll", @"has giveaway",
        @"has wallet", @"has file", @"has round video", @"has text message",
        @"created group", @"forwarded message", @"no messages", @"no text"
    ];
    for (NSString *s in noiseExact) {
        if ([lower isEqualToString:s]) {
            return YES;
        }
    }
    for (NSString *s in noiseContains) {
        if ([lower containsString:s]) {
            return YES;
        }
    }

    return NO;
}

+ (UIView *)messageBubbleAncestorOf:(UIView *)view {
    UIView *v = [view superview];
    int depth = 0;
    while (v && depth < 12) {
        if (TGClassNameMatchesBubble(object_getClass(v))) {
            return v;
        }
        if (TGLooksStructurallyLikeBubble(v)) {
            // structural bubble: must be inside a collection view to count as chat bubble
            UICollectionView *cv = [self chatCollectionViewFor:v];
            if (cv && TGInsideCollectionView(v, cv)) {
                return v;
            }
        }
        v = [v superview];
        depth++;
    }
    return Nil;
}

+ (UICollectionView *)chatCollectionViewFor:(UIView *)view {
    UIView *v = view;
    int depth = 0;
    while (v && depth < 14) {
        if ([v isKindOfClass:[UICollectionView class]]) {
            return (UICollectionView *)v;
        }
        v = [v superview];
        depth++;
    }
    return Nil;
}

+ (BOOL)isTelegramChatCollectionView:(UICollectionView *)cv {
    if (cv == Nil) return NO;
    if (![cv isKindOfClass:[UICollectionView class]]) return NO;
    if (![self isTelegram]) return NO;
    // ASCollectionView (AsyncDisplayKit) carries "Collection" in its class name.
    NSString *name = NSStringFromClass([cv class]);
    return [name rangeOfString:@"Collection" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (NSString *)chatTitleFor:(UIView *)view {
    UIViewController *vc = [self viewControllerForView:view];
    if (vc) {
        NSString *t = vc.navigationItem.title ?: vc.title;
        if (t && t.length > 0) return t;
    }
    return @"";
}

+ (CGRect)frameOfBubble:(UIView *)bubble inCollectionView:(UICollectionView *)cv {
    if (bubble == Nil || cv == Nil) return CGRectNull;
    UIView *v = bubble;
    int depth = 0;
    while (v && depth < 14) {
        if (v == cv) {
            return CGRectIntegral([cv convertRect:bubble.bounds fromView:bubble]);
        }
        v = [v superview];
        depth++;
    }
    return CGRectNull;
}

+ (NSString *)sideOfBubble:(UIView *)bubble inCollectionView:(UICollectionView *)cv {
    if (bubble == Nil || cv == Nil) return @"?";
    CGPoint center = CGPointMake(bubble.center.x, bubble.center.y);
    CGPoint cvCenter = CGPointMake(cv.bounds.size.width / 2.0, cv.bounds.size.height / 2.0);
    return center.x > cvCenter.x ? @"out" : @"in";
}

+ (UIViewController *)viewControllerForView:(UIView *)view {
    if (view == Nil) return Nil;

    id responder = [view nextResponder];
    int depth = 0;
    while (responder && depth < 30) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
        depth++;
    }

    UIWindow *window = view.window;
    UIViewController *root = window.rootViewController;
    while (root) {
        UIViewController *next = root.presentedViewController;
        if (!next && [root isKindOfClass:[UINavigationController class]]) {
            next = [(UINavigationController *)root visibleViewController];
        }
        if (next == root) break;
        root = next;
    }
    return root;
}

+ (UIWindow *)keyWindow {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) return w;
    }
    for (UIWindow *w in app.windows) {
        if (w.isHidden == NO && w.rootViewController != Nil) return w;
    }
    return [app windows].lastObject;
}

+ (void)onTextSet:(NSString *)text view:(UIView *)view {
    if (![self isTelegram]) return;
    if (![self captureEnabled]) return;
    if ([self isNoiseText:text]) return;

    UIView *bubble = [self messageBubbleAncestorOf:view];
    if (bubble == Nil) return;

    UICollectionView *cv = [self chatCollectionViewFor:bubble];

    NSString *chat = [self chatTitleFor:bubble];
    if (chat.length == 0) chat = @"Unknown chat";

    NSString *side = [self sideOfBubble:bubble inCollectionView:cv];
    CGRect frame = CGRectNull;
    if (cv) {
        frame = [self frameOfBubble:bubble inCollectionView:cv];
    }

    [TGRestoreStore.shared addMessageText:text chat:chat side:side frame:frame];
}

@end
