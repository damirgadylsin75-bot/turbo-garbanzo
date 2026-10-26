//
//  TGRestoreStore.m
//  TGRestore — local on-device cache of message texts
//

#import "TGRestoreStore.h"

static const NSInteger TGStoreMaxRecords = 3000;       // hard cap
static const NSTimeInterval TGStoreRetentionDays = 30; // prune older entries
static const NSTimeInterval TGStoreWriteDebounce = 2.0;

@interface TGRestoreStore ()

@property (nonatomic, strong, readonly) NSMutableArray<NSMutableDictionary *> *records;
@property (nonatomic, strong) NSTimer *writeTimer;

@end

@implementation TGRestoreStore

+ (instancetype)shared {
    static TGRestoreStore *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TGRestoreStore alloc] init];
        [instance load];
        [[NSNotificationCenter defaultCenter] addObserver:instance
                                                 selector:@selector(flush)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:Nil];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSMutableArray array];
    }
    return self;
}

- (void)load {
    NSString *path = [self storePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return;
    }
    NSError *error = Nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path]
                                                 options:0
                                                   error:&error];
    if (error || ![parsed isKindOfClass:[NSArray class]]) {
        return;
    }
    for (id item in parsed) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *rec = [item mutableCopy];
            [self.records addObject:rec];
        }
    }
}

- (NSString *)storePath {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"TGRestore"];
    NSString *file = [dir stringByAppendingPathComponent:@"messages.json"];
    return file;
}

- (void)scheduleWrite {
    if (self.writeTimer) {
        [self.writeTimer invalidate];
    }
    self.writeTimer = [NSTimer scheduledTimerWithTimeInterval:TGStoreWriteDebounce
                                                       repeats:NO
                                                         block:^(NSTimer *timer) {
        [self flush];
    }];
}

- (void)flush {
    [self.writeTimer invalidate];
    self.writeTimer = Nil;

    NSString *path = [self storePath];
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSError *error = Nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                             withIntermediateDirectories:YES
                                                            attributes:Nil
                                                                 error:&error]) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@(self.records)
                                                  options:0
                                                    error:&error];
    if (error || data == Nil) {
        return;
    }
    [data writeToFile:path atomically:YES];
}

- (void)prune {
    if (self.records.count <= TGStoreMaxRecords) {
        return;
    }
    // Sort in place oldest-first, then drop the oldest excess entries.
    [self.records sortUsingComparator:^NSComparisonResult(NSMutableDictionary *a, NSMutableDictionary *b) {
        NSNumber *ta = a[@"ts"];
        NSNumber *tb = b[@"ts"];
        if (!ta || !tb) return NSOrderedSame;
        return [ta compare:tb];
    }];
    NSUInteger excess = self.records.count - TGStoreMaxRecords;
    for (NSUInteger i = 0; i < excess; i++) {
        [self.records removeObjectAtIndex:0];
    }

    // also drop records older than the retention window
    NSTimeInterval cutoff = [NSDate date].timeIntervalSince1970 - TGStoreRetentionDays * 86400;
    [self.records removeObjectsPassingTest:^BOOL(NSMutableDictionary *rec, NSUInteger idx, BOOL *stop) {
        NSNumber *ts = rec[@"ts"];
        return !ts || ts.doubleValue < cutoff;
    }];
}

- (NSArray<NSDictionary *> *)allRecords {
    NSMutableArray<NSMutableDictionary *> *sorted = [self.records copy];
    [sorted sortUsingComparator:^NSComparisonResult(NSMutableDictionary *a, NSMutableDictionary *b) {
        NSNumber *ta = a[@"ts"];
        NSNumber *tb = b[@"ts"];
        if (!ta || !tb) return NSOrderedSame;
        return [tb compare:ta]; // newest first
    }];
    return sorted;
}

- (NSDictionary *)recordForText:(NSString *)text {
    if (text == Nil) return Nil;
    for (NSUInteger i = self.records.count; i-- > 0;) {
        NSMutableDictionary *rec = self.records[i];
        if ([rec[@"text"] isEqualToString:text]) {
            return rec;
        }
    }
    return Nil;
}

- (void)addMessageText:(NSString *)text chat:(NSString *)chat side:(NSString *)side frame:(CGRect)frame {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 4000) {
        return;
    }

    NSMutableDictionary *existing = Nil;
    for (NSUInteger i = self.records.count; i-- > 0;) {
        NSMutableDictionary *rec = self.records[i];
        if ([rec[@"text"] isEqualToString:trimmed]) {
            existing = rec;
            break;
        }
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSMutableDictionary *rec = existing ?: [NSMutableDictionary dictionary];
    rec[@"text"] = trimmed;
    rec[@"chat"] = chat ?: @"";
    rec[@"side"] = side ?: @"?";
    rec[@"ts"] = @(now);
    if (CGRectIsNull(frame)) {
        rec[@"frameX"] = @0;
        rec[@"frameY"] = @0;
        rec[@"frameW"] = @0;
        rec[@"frameH"] = @0;
    } else {
        rec[@"frameX"] = @(frame.origin.x);
        rec[@"frameY"] = @(frame.origin.y);
        rec[@"frameW"] = @(frame.size.width);
        rec[@"frameH"] = @(frame.size.height);
    }
    if (![rec[@"restored"] isKindOfClass:[NSNumber class]]) {
        rec[@"restored"] = @NO;
    }
    if (!existing) {
        [self.records addObject:rec];
    }

    [self prune];
    [self scheduleWrite];
}

- (void)markRestored:(NSString *)text {
    for (NSUInteger i = self.records.count; i-- > 0;) {
        NSMutableDictionary *r = self.records[i];
        if ([r[@"text"] isEqualToString:text]) {
            r[@"restored"] = @YES;
            r[@"restoredTs"] = @([NSDate date].timeIntervalSince1970);
            break;
        }
    }
    [self flush];
}

- (void)deleteRecordForText:(NSString *)text {
    if (text == Nil) return;
    [self.records removeObjectsPassingTest:^BOOL(NSMutableDictionary *rec, NSUInteger idx, BOOL *stop) {
        return [rec[@"text"] isEqualToString:text];
    }];
    [self flush];
}

- (void)clearAll {
    [self.records removeAllObjects];
    [self flush];
}

@end
