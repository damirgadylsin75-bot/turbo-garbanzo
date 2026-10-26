//
//  TGRestoreHooks.h
//  TGRestore — message bubble snapshot & deletion detection
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGRestoreHooks : NSObject

/// Snapshot of all visible message bubbles in a collection view.
/// Each entry: @{@"text", @"frame", @"side"} (frame in cv coordinates).
+ (NSArray<NSDictionary *> *)snapshotBubblesInCollectionView:(UICollectionView *)cv;

/// Compare `before` and `after` snapshots; for every cached text that vanished
/// (a message was deleted), show a restored overlay in `cv`.
+ (void)detectAndRestore:(UICollectionView *)cv before:(NSArray<NSDictionary *> *)before after:(NSArray<NSDictionary *> *)after;

@end

NS_ASSUME_NONNULL_END
