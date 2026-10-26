//
//  TGRestore.h
//  TGRestore — see deleted Telegram messages (local cache restore tweak)
//
//  Environment helpers shared by all TGRestore modules.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Settings keys stored in NSUserDefaults (Telegram's defaults domain).
extern NSString * const TGRestoreKeyCaptureEnabled;
extern NSString * const TGRestoreKeyRestoreEnabled;
extern NSString * const TGRestoreKeyButtonVisible;

@interface TGRestore : NSObject

// ---- environment / settings ----

/// Is the current process the Telegram iOS app?
+ (BOOL)isTelegram;

/// Capture incoming/outgoing message texts into the local cache? (default YES)
+ (BOOL)captureEnabled;
+ (void)setCaptureEnabled:(BOOL)v;

/// Show restored bubbles when a cached message disappears? (default YES)
+ (BOOL)restoreEnabled;
+ (void)setRestoreEnabled:(BOOL)v;

/// Show the floating 👁 button in Telegram? (default YES)
+ (BOOL)buttonVisible;
+ (void)setButtonVisible:(BOOL)v;

// ---- text filtering ----

/// Filter out chrome text: dates, "typing", "pinned", "Message was deleted", etc.
+ (BOOL)isNoiseText:(NSString *)text;

// ---- hierarchy helpers ----

/// The nearest ancestor that looks like a chat message bubble (class name or
/// rounded-background structure), or nil if `view` is not inside a message bubble.
+ (UIView *)messageBubbleAncestorOf:(UIView *)view;

/// The UICollectionView (ASCollectionView) this view sits inside, if any.
+ (UICollectionView *)chatCollectionViewFor:(UIView *)view;

/// Is this collection view the one inside a Telegram chat?
+ (BOOL)isTelegramChatCollectionView:(UICollectionView *)cv;

/// Best-effort chat title (navigation item title) for a view.
+ (NSString *)chatTitleFor:(UIView *)view;

/// Frame of the bubble, expressed in `cv` coordinates (CGRectNull if not found).
+ (CGRect)frameOfBubble:(UIView *)bubble inCollectionView:(UICollectionView *)cv;

/// "in" / "out" / "?" — bubble side relative to the collection view center.
+ (NSString *)sideOfBubble:(UIView *)bubble inCollectionView:(UICollectionView *)cv;

/// The UIViewController that owns (or presents) the given view.
+ (UIViewController *)viewControllerForView:(UIView *)view;

/// The currently key window, if any.
+ (UIWindow *)keyWindow;

// ---- capture entry point ----

/// Called from UILabel/UITextView setText:/setAttributedText: hooks.
+ (void)onTextSet:(NSString *)text view:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
