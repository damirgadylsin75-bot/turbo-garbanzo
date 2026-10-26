//
//  TGRestoreOverlay.h
//  TGRestore — restored-message bubble overlays
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Shows a bubble-like overlay with a restored (deleted) message text inside
/// a Telegram chat collection view. Overlays auto-dismiss on scroll, on the
/// next batch update, or after a timeout.
@interface TGRestoreOverlay : NSObject

/// Show an overlay for a restored message. `frame` is in `cv` coordinates
/// (the caller picks a good resting position). `side` is "in"/"out".
+ (void)showRestoredText:(NSString *)text
                   chat:(NSString *)chat
                   side:(NSString *)side
                  frame:(CGRect)frame
           inCollectionView:(UICollectionView *)cv;

/// Remove overlays belonging to one collection view.
+ (void)clearAllInCollectionView:(UICollectionView *)cv;

/// Remove all overlays everywhere.
+ (void)clearAll;

@end

NS_ASSUME_NONNULL_END
