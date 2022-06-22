//
//  AVPlayerItem+DDYVideoCache.h
//  OverSeas
//
//  Created by RainDou on 2022/4/18.
//  Copyright © 2022 ZhuYu.ltd. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface AVPlayerItem (DDYVideoCache)

+ (AVPlayerItem *)ddy_playerItemWithURL:(NSURL *)URL;

/// 播放器释放之前必须调用
- (void)cancelPendings;

- (void)setSuspend:(BOOL)suspend;

@end
