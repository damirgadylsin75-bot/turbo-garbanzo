//
//  Tweak.xm
//  TGRestore — see deleted Telegram messages (local cache restore)
//
//  Hooks (all runtime-safe, no hard dependency on Telegram internals):
//   · UILabel/UITextView setText:/setAttributedText:  → capture message texts
//     as they are rendered (inside chat message bubbles only).
//   · UICollectionView performBatchUpdates:completion: → diff visible bubble
//     texts before/after each batch; restored overlays are shown for cached
//     texts that vanished (i.e. messages that were deleted).
//   · UICollectionView setContentOffset: → dismiss restored overlays on scroll.
//   · UIApplication didFinishLaunchingWithOptions: → install the floating
//     👁 button + viewer.
//

#import <UIKit/UIKit.h>

#import "TGRestore.h"
#import "TGRestoreStore.h"
#import "TGRestoreHooks.h"
#import "TGRestoreOverlay.h"
#import "TGRestoreViewer.h"

// Guards for the delayed deletion-detection block (see below).
static BOOL gTGScrolledSinceBatch = NO;
static CFAbsoluteTime gTGBatchStartTime = 0.0;

static double TGPointDistance(CGPoint a, CGPoint b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
}

%hook UILabel
- (void)setText:(NSString *)text {
    [TGRestore onTextSet:text view:self];
    %orig;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    [TGRestore onTextSet:attributedText.string view:self];
    %orig;
}
%end

%hook UITextView
- (void)setText:(NSString *)text {
    [TGRestore onTextSet:text view:self];
    %orig;
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    [TGRestore onTextSet:attributedText.string view:self];
    %orig;
}
%end

%hook UICollectionView
- (void)performBatchUpdates:(nullable void (^)(void))updates completion:(nullable void (^)(void))completion {
    BOOL chatCV = [TGRestore isTelegramChatCollectionView:self];
    NSArray *before = chatCV ? [TGRestoreHooks snapshotBubblesInCollectionView:self] : @[];

    gTGScrolledSinceBatch = NO;
    gTGBatchStartTime = CFAbsoluteTimeGetCurrent();

    %orig;

    if (chatCV && before.count > 0) {
        __weak UICollectionView *weakCV = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // Skip if the user scrolled during the deletion animation.
            if (gTGScrolledSinceBatch) {
                return;
            }
            if (weakCV == Nil || weakCV.window == Nil) {
                return;
            }
            NSArray *after = [TGRestoreHooks snapshotBubblesInCollectionView:weakCV];
            [TGRestoreOverlay clearAllInCollectionView:weakCV];
            [TGRestoreHooks detectAndRestore:weakCV before:before after:after];
        });
    }
}

- (void)setContentOffset:(CGPoint)contentOffset {
    if (CFAbsoluteTimeGetCurrent() - gTGBatchStartTime < 1.5) {
        if (TGPointDistance(self.contentOffset, contentOffset) > 40.0) {
            gTGScrolledSinceBatch = YES;
        }
    }
    [TGRestoreOverlay clearAllInCollectionView:self];
    %orig;
}
%end

%hook UIApplication
- (BOOL)didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    if ([TGRestore isTelegram]) {
        [TGRestoreViewer install];
    }
    return result;
}
%end
