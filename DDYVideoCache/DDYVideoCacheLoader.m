//
//  DDYVideoCacheLoader.m
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import "DDYVideoCacheLoader.h"
#import "DDYVideoCacheHelper.h"
#import "DDYVideoCacheDBManager.h"
#import <objc/runtime.h>

static NSString *DDYCacheHeaderKey = @"header";
static NSString *DDYCacheZoneKey = @"zone";
static NSString *DDYCacheSizeKey = @"size";
static NSString *DDYContentRangeKey = @"Content-Range";
static NSRange DDYInvalidRange = {NSNotFound, 0};

@interface DDYVideoCacheLoader () <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSDictionary *responseHeader;
@property (nonatomic, strong) NSMutableArray<NSValue *> *rangesArray;
@property (nonatomic, assign) NSUInteger fileLength;
@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) NSOperationQueue *workQueue;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, strong) NSMutableArray *pendingRequest;

@property (nonatomic, strong) NSHTTPURLResponse *response;
@property (nonatomic, copy) NSString *cachePath;

@property (nonatomic, assign) NSInteger updateTime;

@end

@implementation DDYVideoCacheLoader

- (NSString *)urlKey {
    return [self.currentURL.absoluteString ddy_md5];
}

// MARK: - life cycle
- (instancetype)initWithURL:(NSURL *)URL {
    if ([URL isFileURL]) return nil;
    if (self = [super init]) {
        _underlyingQueue = dispatch_queue_create("com.weiguan.cache.queue", DISPATCH_QUEUE_SERIAL);
        self.workQueue = [[NSOperationQueue alloc] init];
        self.workQueue.underlyingQueue = self.underlyingQueue;
        self.currentURL = URL;
        self.updateTime = (NSInteger)[[NSDate date] timeIntervalSince1970];
        self.cachePath = [DDYVideoCacheFilePath() stringByAppendingPathComponent:[self urlKey]];
        self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:self.workQueue];
        [[DDYVideoCacheDBManager sharedManager] checkRemoveRedundantCache];
        if (![self checkInitFile]) return nil;
    }
    return self;
}

- (void)cancelLoader {
    [_session invalidateAndCancel];
    _session = nil;
    // 等待写入操作完成释放
    if (self.workQueue.isSuspended) {
        [self.workQueue setSuspended:NO];
    }
    [self.workQueue waitUntilAllOperationsAreFinished];
}

- (void)setSuspend:(BOOL)suspend {
    _suspend = suspend;
    [self.workQueue setSuspended:suspend];
}

- (NSMutableArray<NSValue *> *)rangesArray {
    if (!_rangesArray) {
        _rangesArray = [NSMutableArray array];
    }
    return _rangesArray;
}

- (NSMutableArray *)pendingRequest {
    if (!_pendingRequest) {
        _pendingRequest = [NSMutableArray array];
    }
    return _pendingRequest;
}

// MARK: - file
- (BOOL)checkInitFile {
    BOOL fileExist = [[NSFileManager defaultManager] fileExistsAtPath:self.cachePath];
    BOOL infoExist = [[DDYVideoCacheDBManager sharedManager] selectWithKey:[self urlKey]].length > 0;
    if (!fileExist) {
        fileExist = [[NSFileManager defaultManager] createFileAtPath:self.cachePath contents:nil attributes:nil];
    }
    if (!infoExist) {
        infoExist = [[DDYVideoCacheDBManager sharedManager] updateWithKey:[self urlKey] value:@"" time:self.updateTime];
    }
    return fileExist && infoExist;
}

/// 构建本地响应
- (void)constructResponseWithRange:(NSRange)range {
    if (!self.response && self.responseHeader.count > 0) {
        if (range.length == NSUIntegerMax) {
            range.length = self.fileLength - range.location;
        }
        
        NSMutableDictionary *responseHeaders = [self.responseHeader mutableCopy];
        BOOL supportRange = responseHeaders[DDYContentRangeKey] != nil;
        if (supportRange && DDYValidByteRange(range)) {
            responseHeaders[DDYContentRangeKey] = DDYHTTPRangeReponseHeaderFromRange(range, _fileLength);
        } else {
            [responseHeaders removeObjectForKey:DDYContentRangeKey];
        }
        responseHeaders[@"Content-Length"] = [NSString stringWithFormat:@"%tu", range.length];
        
        NSInteger statusCode = supportRange ? 206 : 200;
        self.response = [[NSHTTPURLResponse alloc] initWithURL:self.currentURL statusCode:statusCode HTTPVersion:@"HTTP/1.1" headerFields:responseHeaders];
    }
}


- (BOOL)serializeIndex:(NSDictionary *)map {
    if (!map[DDYCacheSizeKey] || !map[DDYCacheZoneKey]) return NO;
    self.fileLength = [map[DDYCacheSizeKey] unsignedIntegerValue];
    if (self.fileLength == 0) return NO;
    
    [self.rangesArray removeAllObjects];
    NSMutableArray<NSString *> *rangeArray = map[DDYCacheZoneKey];
    if (!rangeArray.count) return NO;
    
    for (NSString *rangeStr in rangeArray) {
        [self.rangesArray addObject:[NSValue valueWithRange:NSRangeFromString(rangeStr)]];
    }
    self.responseHeader = map[DDYCacheHeaderKey];
    return YES;
}

- (NSString *)unserializeInfo {
    NSMutableArray *rangeArray = [NSMutableArray array];
    for (NSValue *range in self.rangesArray) {
        [rangeArray addObject:NSStringFromRange([range rangeValue])];
    }
    NSMutableDictionary *dict = [@{DDYCacheSizeKey: @(self.fileLength), DDYCacheZoneKey: rangeArray} mutableCopy];
    if (self.responseHeader) {
        dict[DDYCacheHeaderKey] = self.responseHeader;
    }
    return [DDYVideoCacheHelper stringFormDictionary:dict];
}

- (void)synchronizeInfo {
    [[DDYVideoCacheDBManager sharedManager] updateWithKey:[self urlKey] value:[self unserializeInfo] time:self.updateTime];
}

// MARK: - AVAssetResourceLoaderDelegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    [self handleLoadingRequest:loadingRequest];
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    for (NSURLSessionDataTask *task in self.pendingRequest) {
        if (task.ddy_loadingRequest.isCancelled) {
            [task cancel];
        }
    }
}

// MARK: - HandleLoadingRequest
- (void)handleLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSDictionary *map = [DDYVideoCacheHelper getMapFromString:[[DDYVideoCacheDBManager sharedManager] selectWithKey:[self urlKey]]];
    NSRange range = DDYInvalidRange;
    NSRange reqRange = NSMakeRange(loadingRequest.dataRequest.requestedOffset, loadingRequest.dataRequest.requestedLength);
    if ([self serializeIndex:map]) {
        range = [self cachedRangeForRange:reqRange];
        if (!DDYValidByteRange(range)) {
            range = reqRange;
            goto cacheRemote;
        }
        goto cacheLocal;
    } else {
        goto cacheRemote;
    }
    
cacheRemote: // 请求网络资源
    [self sendRemoteRequest:loadingRequest withRange:range];
    return;
    
cacheLocal: // 读取本地资源
    [self getLocalRequest:loadingRequest withRange:range];
    if (NSMaxRange(range) < NSMaxRange(reqRange)) {
        range = NSMakeRange(NSMaxRange(range), NSMaxRange(reqRange) - NSMaxRange(range));
        goto cacheRemote;
    }
}

- (NSRange)cachedRangeForRange:(NSRange)range {
    NSRange cachedRange = [self cachedRangeContainsPosition:range.location];
    NSRange ret = NSIntersectionRange(cachedRange, range);
    if (ret.length > 0) {
        return ret;
    } else {
        return DDYInvalidRange;
    }
}

- (NSRange)cachedRangeContainsPosition:(NSUInteger)pos {
    if (pos >= _fileLength) {
        return DDYInvalidRange;
    }
    
    for (int i = 0; i < self.rangesArray.count; ++i) {
        NSRange range = [self.rangesArray[i] rangeValue];
        if (NSLocationInRange(pos, range)) {
            return range;
        }
    }
    return DDYInvalidRange;
}

- (void)addRange:(NSRange)range {
    if (range.length == 0 || range.location >= _fileLength) {
        return;
    }
    
    BOOL inserted = NO;
    for (int i = 0; i < self.rangesArray.count; ++i) {
        NSRange currentRange = [self.rangesArray[i] rangeValue];
        if (currentRange.location >= range.location) {
            [self.rangesArray insertObject:[NSValue valueWithRange:range] atIndex:i];
            inserted = YES;
            break;
        }
    }
    if (!inserted) {
        [self.rangesArray addObject:[NSValue valueWithRange:range]];
    }
    [self mergeRanges];
}

- (void)mergeRanges {
    for (int i = 0; i < self.rangesArray.count; ++i) {
        if ((i + 1) < self.rangesArray.count) {
            NSRange currentRange = [self.rangesArray[i] rangeValue];
            NSRange nextRange = [self.rangesArray[i + 1] rangeValue];
            if (DDYRangeCanMerge(currentRange, nextRange)) {
                [self.rangesArray removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, 2)]];
                [self.rangesArray insertObject:[NSValue valueWithRange:NSUnionRange(currentRange, nextRange)] atIndex:i];
                i -= 1;
            }
        }
    }
}


- (void)sendRemoteRequest:(AVAssetResourceLoadingRequest *)loadingRequest withRange:(NSRange)range {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:self.currentURL
                                                                cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                            timeoutInterval:20.f];
    NSRange requestRange = range;
    if (!DDYValidByteRange(range) && loadingRequest) {
        requestRange = NSMakeRange(loadingRequest.dataRequest.requestedOffset, loadingRequest.dataRequest.requestedLength);
    }
    [request setValue:DDYHTTPRangeRequestHeaderFromRange(requestRange) forHTTPHeaderField:@"Range"];
    if (![_session.delegate isEqual:self] || !_session) {
        return;
    }

    NSURLSessionTask *dataTask = [_session dataTaskWithRequest:request];
    dataTask.ddy_loadingRequest = loadingRequest;
    dataTask.ddy_offset = [NSNumber numberWithUnsignedInteger:requestRange.location];
    [dataTask resume];
    [self.pendingRequest addObject:dataTask];
}

- (void)getLocalRequest:(AVAssetResourceLoadingRequest *)loadingRequest withRange:(NSRange)range {
    [self constructResponseWithRange:range];
    NSData *data = [NSData dataWithContentsOfFile:self.cachePath options:NSDataReadingMappedIfSafe error:nil];
    [loadingRequest ddy_fillContentInfo:self.response];
    [loadingRequest.dataRequest respondWithData:[data subdataWithRange:range]];
    if (loadingRequest.dataRequest.requestedOffset + loadingRequest.dataRequest.requestedLength <= NSMaxRange(range)) {
        [loadingRequest finishLoading];
    }
}

// MARK: - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (![response respondsToSelector:@selector(statusCode)] || (httpResponse.statusCode < 400 && httpResponse.statusCode != 304)) {;
        [dataTask.ddy_loadingRequest ddy_fillContentInfo:httpResponse];
        self.response = httpResponse;
        self.responseHeader = [[httpResponse allHeaderFields] copy];
        self.fileLength = httpResponse.ddy_fileLength;
        self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.cachePath];
        @try {
            [self.fileHandle truncateFileAtOffset:self.fileLength];
        } @catch (NSException *exception) {
            NSLog(@"truncateFileAtOffset exception %@", exception.description);
        } @finally {
            completionHandler(NSURLSessionResponseAllow);
        }
    } else {
        completionHandler(NSURLSessionResponseCancel);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSUInteger offset = [dataTask.ddy_offset unsignedIntegerValue];
    NSMutableData *currentData = [NSMutableData data];
    [data enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        [currentData appendBytes:bytes length:byteRange.length];
    }];
    [dataTask.ddy_loadingRequest.dataRequest respondWithData:currentData];
    [self.fileHandle seekToFileOffset:offset];
    [self addRange:NSMakeRange(offset, [currentData length])];
    
    offset += currentData.length;
    [self.fileHandle writeData:currentData];
    [self.fileHandle synchronizeFile];
    [self synchronizeInfo];
    dataTask.ddy_offset = [NSNumber numberWithUnsignedInteger:offset];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        [task.ddy_loadingRequest finishLoadingWithError:error];
    } else {
        [task.ddy_loadingRequest finishLoading];
    }
    [self.pendingRequest removeObject:task];    
}

- (void)dealloc {
    [self synchronizeInfo];
    [self.fileHandle closeFile];
}

@end

// Vito的猫屋 https://mp.weixin.qq.com/s/v1sw_Sb8oKeZ8sWyjBUXGA?##
// seek https://blog.csdn.net/qq_34534179/article/details/109180909
