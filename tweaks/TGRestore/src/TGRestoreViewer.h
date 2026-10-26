//
//  TGRestoreViewer.h
//  TGRestore — viewer UI & floating button
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGRestoreStore;

/// Table controller listing captured/restored messages.
@interface TGRestoreViewerController : UITableViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *records;
- (instancetype)initWithStore:(TGRestoreStore *)store;
@end

/// Entry point: installs the floating button + notification observers.
@interface TGRestoreViewer : NSObject

+ (instancetype)shared;

/// Call once from UIApplication didFinishLaunchingWithOptions.
+ (void)install;

/// Tap on a restored bubble — open the viewer.
- (void)overlayTapped;

/// Present the viewer from the current context.
- (void)openViewer;

@end

NS_ASSUME_NONNULL_END
