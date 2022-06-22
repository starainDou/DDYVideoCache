//
//  DDYVideoCacheDBManager.h
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// 视频边播边下缓存信息数据库
@interface DDYVideoCacheDBManager : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (id)copy NS_UNAVAILABLE;
- (id)mutableCopy NS_UNAVAILABLE;

/// 单例
+ (instancetype)sharedManager;

/// 通过key查询
/// @param key URL.absoluteString.MD5
- (NSString *)selectWithKey:(NSString *)key;

/// 增加或更新
/// @param key URL.absoluteString.MD5
/// @param value HeaderDictionaryToString
- (BOOL)updateWithKey:(NSString *)key value:(NSString *)value time:(NSInteger)time;

/// 删除
/// @param key URL.absoluteString.MD5
- (BOOL)deleteWithKey:(NSString *)key;

/// 事务批量删除
/// @param keyArray key数组
- (void)deleteWithKeyArray:(NSArray<NSString *> *)keyArray;

/// 获取数量
- (NSInteger)getCacheCount;

/// 获取所有缓存key
- (NSArray<NSString *> *)getAllCacheKeys;

/// 获取超出数量不再需要的缓存key
- (NSArray<NSString *> *)getRedundantCacheKeys;

/// 获取过期不再需要的缓存key
- (NSArray<NSString *> *)getOverdueCacheKeys;

/// 检查移除超出数量的缓存
- (void)checkRemoveRedundantCache;

/// 移除过期缓存
- (void)removeOverdueCache;

/// 移除所有缓存
- (void)removeAllCache;

@end

NS_ASSUME_NONNULL_END
