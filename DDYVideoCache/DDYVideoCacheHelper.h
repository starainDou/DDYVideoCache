//
//  DDYVideoCacheHelper.h
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVAssetResourceLoader.h>

extern const NSInteger DDYCacheCount;
extern const NSInteger DDYCacheTime;

BOOL DDYValidByteRange(NSRange range);

BOOL DDYValidFileRange(NSRange range);

BOOL DDYRangeCanMerge(NSRange range1,NSRange range2);

NSString* DDYHTTPRangeRequestHeaderFromRange(NSRange range);

NSString* DDYHTTPRangeReponseHeaderFromRange(NSRange range,NSUInteger length);
/// 文件缓存路径
NSString *DDYVideoCacheFilePath(void);
/// 数据库缓存路径
NSString *DDYVideoCacheDBPath(NSString *pathComponent);


@interface NSString (DDYCacheSupport)
- (NSString *)ddy_md5;
@end

@interface NSURLRequest (DDYCacheSupport)
@property (nonatomic, readonly) NSRange ddy_range;
@end

@interface NSHTTPURLResponse (DDYCacheSupport)
- (long long)ddy_fileLength;
- (BOOL)ddy_supportRange;
@end

@interface AVAssetResourceLoadingRequest (DDYCacheSupport)
- (void)ddy_fillContentInfo:(NSHTTPURLResponse *)response;
@end

@interface NSURLSessionTask (DDYVideoCache)
@property (nonatomic, strong) AVAssetResourceLoadingRequest *ddy_loadingRequest;
@property (nonatomic, strong) NSNumber *ddy_offset;
@end


@interface DDYVideoCacheHelper : NSObject

+ (NSString *)stringFormDictionary:(NSDictionary *)dictionary;

+ (NSDictionary *)getMapFromString:(NSString *)string;

@end
