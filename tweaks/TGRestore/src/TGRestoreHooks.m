//
//  TGRestoreHooks.m
//  TGRestore — message bubble snapshot & deletion detection
//

#import "TGRestoreHooks.h"
#import "TGRestore.h"
#import "TGRestoreStore.h"
#import "TGRestoreOverlay.h"

@implementation TGRestoreHooks

+ (NSString *)textOfView:(UIView *)v {
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        if (l.attributedText && l.attributedText.string.length > 0) {
            return l.attributedText.string;
        }
        return l.text ?: @"";
    }
    if ([v isKindOfClass:[UITextView class]]) {
        UITextView *t = (UITextView *)v;
        if (t.attributedText && t.attributedText.string.length > 0) {
            return t.attributedText.string;
        }
        return t.text ?: @"";
    }
    return @"";
}

+ (void)enumerateLabelsInView:(UIView *)view
                       cv:(UICollectionView *)cv
                    depth:(int)depth
                      seen:(NSMutableSet *)seen
                        out:(NSMutableArray<NSDictionary *> *)out {
    if (depth > 8) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]] || [sub isKindOfClass:[UITextView class]]) {
            NSString *text = [self textOfView:sub];
            if (text.length >= 2) {
                UIView *bubble = [TGRestore messageBubbleAncestorOf:sub];
                if (bubble) {
                    id key = @((NSInteger)(uintptr_t)bubble);
                    if (![seen containsObject:key]) {
                        [seen addObject:key];
                        CGRect frame = [TGRestore frameOfBubble:bubble inCollectionView:cv];
                        if (!CGRectIsNull(frame)) {
                            NSString *side = [TGRestore sideOfBubble:bubble inCollectionView:cv];
                            [out addObject:@{
                                @"text": text,
                                @"frame": [NSValue valueWithCGRect:frame],
                                @"side": side ?: @"?"
                            }];
                        }
                    }
                }
            }
        }
        [self enumerateLabelsInView:sub cv:cv depth:depth + 1 seen:seen out:out];
    }
}

+ (NSArray<NSDictionary *> *)snapshotBubblesInCollectionView:(UICollectionView *)cv {
    if (cv == Nil) {
        return @[];
    }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [self enumerateLabelsInView:cv cv:cv depth:0 seen:seen out:out];
    return out;
}

+ (void)detectAndRestore:(UICollectionView *)cv
                   before:(NSArray<NSDictionary *> *)before
                   after:(NSArray<NSDictionary *> *)after
{
    if (cv == Nil || before.count == 0) {
        return;
    }
    if (![TGRestore restoreEnabled]) {
        return;
    }

    NSMutableSet *stillVisible = [NSMutableSet set];
    for (NSDictionary *a in after) {
        NSString *t = a[@"text"];
        if ([t isKindOfClass:NSString]) {
            [stillVisible addObject:t];
        }
    }

    for (NSDictionary *b in before) {
        NSString *text = b[@"text"];
        if (![text isKindOfClass:NSString]) {
            continue;
        }
        if ([TGRestore isNoiseText:text]) {
            continue;
        }
        if ([stillVisible containsObject:text]) {
            continue; // not deleted — just still there
        }

        // Only restore texts we actually captured before (i.e. the device
        // still had the content). Anything else was deleted server-side and
        // cannot be recovered client-side.
        NSDictionary *rec = [[TGRestoreStore shared] recordForText:text];
        if (rec == Nil) {
            continue;
        }

        // Pick a resting position: the old slot of the message directly below
        // the vanished one (that space becomes empty after the collapse).
        CGRect vanished = CGRectNull;
        NSValue *v = b[@"frame"];
        if (v) {
            vanished = [v CGRectValue];
        }
        CGRect target = vanished;
        CGFloat bestY = CGFLOAT_MAX;
        for (NSDictionary *other in before) {
            NSValue *ov = other[@"frame"];
            if (!ov) continue;
            CGRect f = [ov CGRectValue];
            if (CGRectGetMinY(f) >= CGRectGetMaxY(vanished) - 2.0 && CGRectGetMinY(f) < bestY) {
                bestY = CGRectGetMinY(f);
                target = f;
            }
        }

        [TGRestoreOverlay showRestoredText:text
                                       chat:rec[@"chat"] ?: @""
                                       side:rec[@"side"] ?: @"?"
                                      frame:target
                            inCollectionView:cv];
        [[TGRestoreStore shared] markRestored:text];
    }
}

@end
