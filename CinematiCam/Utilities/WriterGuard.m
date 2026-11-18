#import "WriterGuard.h"
#import <stdatomic.h>

static atomic_long caught = 0;

/// Writes the reason down (the first few only, so a repeating problem cannot flood the log)
static void note(NSString *step, NSException *problem) {
    long count = atomic_fetch_add(&caught, 1) + 1;
    if (count <= 20) {
        NSLog(@"WriterGuard: %@ was refused: %@ (%@)", step, problem.reason, problem.name);
    }
}

@implementation WriterGuard

+ (NSInteger)problemCount {
    return (NSInteger)atomic_load(&caught);
}

+ (nullable AVAssetWriterInput *)makeInput:(AVMediaType)mediaType
                                  settings:(nullable NSDictionary<NSString *, id> *)settings {
    @try {
        return [AVAssetWriterInput assetWriterInputWithMediaType:mediaType outputSettings:settings];
    } @catch (NSException *problem) {
        note(@"making an input", problem);
        return nil;
    }
}

+ (BOOL)startWriting:(AVAssetWriter *)writer {
    @try {
        return [writer startWriting];
    } @catch (NSException *problem) {
        note(@"starting the file", problem);
        return NO;
    }
}

+ (BOOL)startSession:(AVAssetWriter *)writer at:(CMTime)time {
    @try {
        [writer startSessionAtSourceTime:time];
        return YES;
    } @catch (NSException *problem) {
        note(@"starting the clip", problem);
        return NO;
    }
}

+ (BOOL)appendSample:(CMSampleBufferRef)sample to:(AVAssetWriterInput *)input {
    @try {
        return [input appendSampleBuffer:sample];
    } @catch (NSException *problem) {
        note(@"adding sound", problem);
        return NO;
    }
}

+ (BOOL)appendPixels:(CVPixelBufferRef)pixels
                  at:(CMTime)time
                  to:(AVAssetWriterInputPixelBufferAdaptor *)adaptor {
    @try {
        return [adaptor appendPixelBuffer:pixels withPresentationTime:time];
    } @catch (NSException *problem) {
        note(@"adding a frame", problem);
        return NO;
    }
}

+ (void)finishInput:(AVAssetWriterInput *)input {
    @try {
        [input markAsFinished];
    } @catch (NSException *problem) {
        note(@"closing an input", problem);
    }
}

+ (void)finishWriting:(AVAssetWriter *)writer then:(void (^)(void))handler {
    @try {
        [writer finishWritingWithCompletionHandler:handler];
    } @catch (NSException *problem) {
        note(@"finishing the file", problem);
        // The writer never took the handler, so it is still ours to run
        handler();
    }
}

+ (void)cancel:(AVAssetWriter *)writer {
    @try {
        [writer cancelWriting];
    } @catch (NSException *problem) {
        note(@"cancelling the file", problem);
    }
}

+ (BOOL)attempt:(NS_NOESCAPE void (^)(void))work {
    @try {
        work();
        return YES;
    } @catch (NSException *problem) {
        note(@"a camera call", problem);
        return NO;
    }
}

@end
