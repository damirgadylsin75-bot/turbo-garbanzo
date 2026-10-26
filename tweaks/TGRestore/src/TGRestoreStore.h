//
//  TGRestoreStore.h
//  TGRestore — local on-device cache of message texts
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Persistent store for captured message texts.
///
/// Records are kept as JSON inside Telegram's own Documents directory so they
/// survive app restarts. Records are de-duplicated by text (one record per
/// distinct message text), keeping the most recent frame/timestamp.
@interface TGRestoreStore : NSObject

+ (instancetype)shared;

/// All records, sorted newest first.
- (NSArray<NSDictionary *> *)allRecords;

/// The cached record for a given text (the most recently seen one), or nil.
- (NSDictionary *)recordForText:(NSString *)text;

/// Insert/update a record for this text.
- (void)addMessageText:(NSString *)text chat:(NSString *)chat side:(NSString *)side frame:(CGRect)frame;

/// Mark a record as restored (shown back to the user).
- (void)markRestored:(NSString *)text;

/// Delete a single record (by text).
- (void)deleteRecordForText:(NSString *)text;

/// Delete every record.
- (void)clearAll;

/// Absolute path of the backing JSON file.
- (NSString *)storePath;

@end

NS_ASSUME_NONNULL_END
