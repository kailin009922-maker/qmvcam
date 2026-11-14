//
//  vcam_source.h
//
#ifndef VCAM_SOURCE_H
#define VCAM_SOURCE_H
#import "vcam_common.h"

@interface QMFrameSource : NSObject
- (instancetype)initWithPath:(NSString *)path kind:(NSString *)kind;
- (void)start;
- (void)stop;
- (CVPixelBufferRef)copyLatestFrame CF_RETURNS_RETAINED;   // caller 负责 CFRelease
@property (nonatomic, readonly) CGSize size;
@property (nonatomic, readonly) BOOL isVideo;
@property (nonatomic, assign, getter=isPaused) BOOL paused;
@property (nonatomic, readonly) NSString *path;
@end

#endif
