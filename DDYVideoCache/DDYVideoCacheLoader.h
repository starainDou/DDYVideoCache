//
//  DDYVideoCacheLoader.h
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface DDYVideoCacheLoader : NSObject <AVAssetResourceLoaderDelegate>

@property (nonatomic, readonly) dispatch_queue_t underlyingQueue;

@property (nonatomic, assign, getter=isSuspend) BOOL suspend;

- (instancetype)initWithURL:(NSURL *)URL;

- (void)cancelLoader;

@end
