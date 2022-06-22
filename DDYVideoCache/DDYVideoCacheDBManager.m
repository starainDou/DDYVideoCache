//
//  DDYVideoCacheDBManager.m
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import "DDYVideoCacheDBManager.h"
#import "DDYVideoCacheHelper.h"
#import <FMDB/FMDB.h>

@interface DDYVideoCacheDBManager ()

@property (nonatomic, strong) FMDatabaseQueue *dbQueue;

@end

@implementation DDYVideoCacheDBManager

- (FMDatabaseQueue *)dbQueue {
    if (!_dbQueue) {
        _dbQueue = [FMDatabaseQueue databaseQueueWithPath:DDYVideoCacheDBPath(@"info.db")]; // 已有open操作
    }
    return _dbQueue;
}

+ (instancetype)sharedManager {
    static DDYVideoCacheDBManager *videoCacheDBManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        videoCacheDBManager = [[self alloc] init];
    });
    return videoCacheDBManager;
}

- (instancetype)init {
    if (self = [super init]) {
        __unused BOOL result = [self checkCreatTable];
        NSAssert(result, @"Init Database fail");
    }
    return self;
}

- (BOOL)executeUpdate:(NSString *)sqlStr {
    __block BOOL result = NO;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        result = [db executeUpdate:sqlStr];
    }];
    return result;
}

- (BOOL)checkCreatTable {
    return [self executeUpdate:@"CREATE TABLE IF NOT EXISTS DDYVideoCache(key TEXT primary key, value TEXT, time integer)"];
}

/// 查
- (NSString *)selectWithKey:(NSString *)key {
    __block NSString *result = @"";
    NSString *sqlStr = [NSString stringWithFormat:@"SELECT * FROM DDYVideoCache WHERE key = '%@' LIMIT 1", key];
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        FMResultSet *set = [db executeQuery:sqlStr];
        while ([set next]) {
            result = [set objectForColumn:@"value"];
        }
    }];
    return result;
}

/// 增、改 URL.absoluteString.ddy_MD5
- (BOOL)updateWithKey:(NSString *)key value:(NSString *)value time:(NSInteger)time {
    NSString *sqlStr = [NSString stringWithFormat:@"REPLACE INTO DDYVideoCache (key, value, time) VALUES ('%@', '%@', '%ld')", key, value, time];
    return [self executeUpdate:sqlStr];
}

/// 删除
- (BOOL)deleteWithKey:(NSString *)key {
    return [self executeUpdate:[NSString stringWithFormat:@"DELETE FROM DDYVideoCache WHERE key = '%@'", key]];
}

/// 事务批量删除
- (void)deleteWithKeyArray:(NSArray<NSString *> *)keyArray {
    [self.dbQueue inTransaction:^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        for (NSString *key in keyArray) {
            [db executeUpdate: [NSString stringWithFormat:@"DELETE FROM DDYVideoCache WHERE key = '%@'", key]];
        }
    }];
}

/// 获取数量
- (NSInteger)getCacheCount {
    __block NSInteger count = 0;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        count = [db intForQuery:@"SELECT COUNT(*) FROM DDYVideoCache"];
    }];
    return count;
}

/// 获取所有缓存key
- (NSArray<NSString *> *)getAllCacheKeys {
    __block NSMutableArray *keyArray = [NSMutableArray array];;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        NSString *sqlStr = [NSString stringWithFormat:@"SELECT * FROM DDYVideoCache"];
        FMResultSet *resultSet = [db executeQuery:sqlStr];
        while ([resultSet next]) {
            [keyArray addObject:[resultSet stringForColumn:@"key"]];
        }
    }];
    return keyArray;
}

/// 获取超出数量不再需要的缓存key
- (NSArray<NSString *> *)getRedundantCacheKeys {
    __block NSMutableArray *keyArray = [NSMutableArray array];;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        int count = [db intForQuery:@"SELECT COUNT(*) FROM DDYVideoCache"];
        if (count - DDYCacheCount > 10) {
            NSString *sqlStr = [NSString stringWithFormat:@"SELECT * FROM DDYVideoCache ORDER BY time DESC LIMIT 0, 10"];
            FMResultSet *resultSet = [db executeQuery:sqlStr];
            while ([resultSet next]) {
                [keyArray addObject:[resultSet stringForColumn:@"key"]];
            }
        }
    }];
    return keyArray;
}

/// 获取过期不再需要的缓存key
- (NSArray<NSString *> *)getOverdueCacheKeys {
    __block NSMutableArray *keyArray = [NSMutableArray array];;
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        NSInteger deadline = (NSInteger)[[NSDate date] timeIntervalSince1970] - DDYCacheTime;
        NSString *sqlStr = [NSString stringWithFormat:@"SELECT * FROM DDYVideoCache WHERE time < %ld", deadline];
        FMResultSet *resultSet = [db executeQuery:sqlStr];
        while ([resultSet next]) {
            [keyArray addObject:[resultSet stringForColumn:@"key"]];
        }
    }];
    return keyArray;
}

/// 检查移除超出数量的缓存
- (void)checkRemoveRedundantCache {
    [self removeCacheWithKeyArray:[[DDYVideoCacheDBManager sharedManager] getRedundantCacheKeys]];
}

/// 移除过期缓存
- (void)removeOverdueCache {
    [self removeCacheWithKeyArray:[[DDYVideoCacheDBManager sharedManager] getOverdueCacheKeys]];
}

/// 移除所有缓存
- (void)removeAllCache {
    [self removeCacheWithKeyArray:[[DDYVideoCacheDBManager sharedManager] getAllCacheKeys]];
}

/// 根据key数组移除文件和数据
- (void)removeCacheWithKeyArray:(NSArray *)keyArray {
    if (keyArray.count > 0) {
        [[DDYVideoCacheDBManager sharedManager] deleteWithKeyArray:keyArray];
        for (NSString *keyStr in keyArray) {
            NSString *filePath = [DDYVideoCacheFilePath() stringByAppendingPathComponent:keyStr];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    }
}

/// 暂时不用遍历文件夹形式
+ (void)removeVideoCache NS_UNAVAILABLE {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:DDYVideoCacheFilePath()];
        NSString *fileName;
        while (fileName = [enumerator nextObject]) {
            NSString *filePath = [DDYVideoCacheFilePath() stringByAppendingPathComponent:fileName];
            [[DDYVideoCacheDBManager sharedManager] deleteWithKey:fileName];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    });
}

/// 暂时不用遍历文件夹形式
+ (void)excuteSchedule NS_UNAVAILABLE {
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:DDYVideoCacheFilePath()];
    NSString *fileName;
    while (fileName = [enumerator nextObject]) {
        NSString *filePath = [DDYVideoCacheFilePath() stringByAppendingPathComponent:fileName];
        NSDate *date = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil].fileModificationDate;
        
        if ([[NSDate date] timeIntervalSinceDate:date] > DDYCacheTime) {
            NSString *filePath = [DDYVideoCacheFilePath() stringByAppendingPathComponent:fileName];
            [[DDYVideoCacheDBManager sharedManager] deleteWithKey:fileName];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        }
    }
}

@end

// @throw [NSException exceptionWithName:@"db初始化失败" reason:@"FMDB没告诉原因" userInfo:nil];
