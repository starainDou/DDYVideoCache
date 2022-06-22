//
//  DDYVideoCacheHelper.m
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import "DDYVideoCacheHelper.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
@import MobileCoreServices;

const NSInteger DDYCacheCount = 200;
const NSInteger DDYCacheTime = 7 * 24 * 60 * 60;

BOOL DDYValidByteRange(NSRange range) {
    return (range.location != NSNotFound || range.length > 0);
}

BOOL DDYValidFileRange(NSRange range) {
    return (range.location != NSNotFound && range.length > 0 && range.length != NSUIntegerMax);
}

BOOL DDYRangeCanMerge(NSRange range1,NSRange range2) {
    return (NSMaxRange(range1) == range2.location) || (NSMaxRange(range2) == range1.location) || NSIntersectionRange(range1, range2).length > 0;
}

NSString *DDYHTTPRangeRequestHeaderFromRange(NSRange range) {
    if (!DDYValidByteRange(range)) {
        return nil;
    } else if (range.location == NSNotFound) {
        return [NSString stringWithFormat:@"bytes=-%tu", range.length];
    } else if (range.length == NSUIntegerMax) {
        return [NSString stringWithFormat:@"bytes=%tu-", range.location];
    } else {
        return [NSString stringWithFormat:@"bytes=%tu-%tu", range.location, NSMaxRange(range) - 1];
    }
}

NSString *DDYHTTPRangeReponseHeaderFromRange(NSRange range,NSUInteger length) {
    if (!DDYValidByteRange(range)) return nil;
    NSUInteger start = range.location;
    NSUInteger end = NSMaxRange(range) - 1;
    if (range.location == NSNotFound) {
        start = range.location;
    } else if (range.length == NSUIntegerMax) {
        start = length - range.length;
        end = start + range.length - 1;
    }
    return [NSString stringWithFormat:@"bytes %tu-%tu/%tu", start, end, length];
}

NSString *DDYVideoCachePath(NSString *pathComponent) {
    NSString *documentPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *cachePath = [documentPath stringByAppendingPathComponent:pathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cachePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return cachePath;
}

NSString *DDYVideoCacheFilePath(void) {
    return DDYVideoCachePath(@"DDYVideoCacheFile");
}

NSString *DDYVideoCacheDBPath(NSString *pathComponent) {
    return [DDYVideoCachePath(@"DDYVideoCacheFile") stringByAppendingPathComponent:pathComponent];
}


@implementation NSString (DDYCacheSupport)

- (NSString *)ddy_md5 {
    const char *cStr = [self UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *result = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [result appendFormat:@"%02x", digest[i]];
    return result;
}

@end

@implementation NSURLRequest (DDYCacheSupport)
- (NSRange)ddy_range {
    NSRange range = NSMakeRange(NSNotFound, 0);
    NSString *rangeString = [self allHTTPHeaderFields][@"Range"];
    if ([rangeString hasPrefix:@"bytes="]) {
        NSArray* components = [[rangeString substringFromIndex:6] componentsSeparatedByString:@","];
        if (components.count == 1) {
            components = [[components firstObject] componentsSeparatedByString:@"-"];
            if (components.count == 2) {
                NSString* startString = [components objectAtIndex:0];
                NSInteger startValue = [startString integerValue];
                NSString* endString = [components objectAtIndex:1];
                NSInteger endValue = [endString integerValue];
                if (startString.length && (startValue >= 0) && endString.length && (endValue >= startValue)) {  // The second 500 bytes: "500-999"
                    range.location = startValue;
                    range.length = endValue - startValue + 1;
                } else if (startString.length && (startValue >= 0)) {  // The bytes after 9500 bytes: "9500-"
                    range.location = startValue;
                    range.length = NSUIntegerMax;
                } else if (endString.length && (endValue > 0)) {  // The final 500 bytes: "-500"
                    range.location = NSNotFound;
                    range.length = endValue;
                }
            }
        }
    }
    return range;
}
@end

@implementation NSHTTPURLResponse (DDYCacheSupport)

- (long long)ddy_fileLength {
    NSString *range = [self allHeaderFields][@"Content-Range"];
    if (range) {
        NSArray *ranges = [range componentsSeparatedByString:@"/"];
        if (ranges.count > 0) {
            NSString *lengthString = [[ranges lastObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [lengthString longLongValue];
        } else {
            return 0;
        }
    } else {
        return [self expectedContentLength];
    }
}

- (BOOL)ddy_supportRange {
    return [self allHeaderFields][@"Content-Range"] != nil;
}

@end

@implementation AVAssetResourceLoadingRequest (DDYCacheSupport)
- (void)ddy_fillContentInfo:(NSHTTPURLResponse *)response {
    if (!response) return;
    if (!self.contentInformationRequest) return;
    self.response = response;
    NSString *mimeType = [response MIMEType];
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    self.contentInformationRequest.byteRangeAccessSupported = [response ddy_supportRange];
    self.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    self.contentInformationRequest.contentLength = [response ddy_fileLength];
}
@end

@implementation NSURLSessionTask (DDYVideoCache)

- (void)setDdy_loadingRequest:(AVAssetResourceLoadingRequest *)ddy_loadingRequest {
    objc_setAssociatedObject(self, @selector(ddy_loadingRequest), ddy_loadingRequest, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (AVAssetResourceLoadingRequest *)ddy_loadingRequest {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setDdy_offset:(NSNumber *)ddy_offset {
    objc_setAssociatedObject(self, @selector(ddy_offset), ddy_offset, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)ddy_offset {
    return objc_getAssociatedObject(self, _cmd);
}

@end


@implementation DDYVideoCacheHelper

+ (NSString *)stringFormDictionary:(NSDictionary *)dictionary {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    return [data base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
}

+ (NSDictionary *)getMapFromString:(NSString *)string {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:string options:NSDataBase64DecodingIgnoreUnknownCharacters];
    return [NSJSONSerialization JSONObjectWithData:data
                                           options:NSJSONReadingMutableContainers | NSJSONReadingAllowFragments
                                             error:nil];
}

@end
