//
//  AVPlayerItem+DDYVideoCache.m
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//


#import "AVPlayerItem+DDYVideoCache.h"
#import "DDYVideoCacheLoader.h"
#import <objc/runtime.h>
#import "DDYVideoCacheHelper.h"
#import "DDYVideoCacheDBManager.h"

@implementation AVPlayerItem (DDYVideoCache)

+ (AVPlayerItem *)ddy_playerItemWithURL:(NSURL *)URL {
    DDYVideoCacheLoader *loader = [[DDYVideoCacheLoader alloc] initWithURL:URL];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[self valideURL:URL]  options:nil];
    [asset.resourceLoader setDelegate:loader queue:loader.underlyingQueue];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    objc_setAssociatedObject(item, @selector(ddy_playerItemWithURL:), loader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}

- (void)cancelPendings {
    DDYVideoCacheLoader *loader = objc_getAssociatedObject(self, @selector(ddy_playerItemWithURL:));
    [loader cancelLoader];
}

- (void)setSuspend:(BOOL)suspend {
    DDYVideoCacheLoader *loader = objc_getAssociatedObject(self, @selector(ddy_playerItemWithURL:));
    [loader setSuspend:suspend];
}

+ (NSURL *)valideURL:(NSURL *)URL {
    if ([URL isFileURL]) {
        return URL;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    components.scheme = @"stream";
    return components.URL;
}

@end
