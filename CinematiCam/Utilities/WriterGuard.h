#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The video file writer (AVAssetWriter) reports misuse by throwing an Objective-C error.
/// Swift cannot catch that kind of error, so it closes the app and the recording is lost.
/// Every writer call that can throw goes through here instead: a throw becomes a plain "no",
/// so the worst that can happen is a clip that is not written, never a crash.
@interface WriterGuard : NSObject

/// How many throws have been caught since the app started (0 in normal use)
@property (class, readonly) NSInteger problemCount;

+ (nullable AVAssetWriterInput *)makeInput:(AVMediaType)mediaType
                                  settings:(nullable NSDictionary<NSString *, id> *)settings
    NS_SWIFT_NAME(makeInput(_:settings:));
+ (BOOL)startWriting:(AVAssetWriter *)writer NS_SWIFT_NAME(startWriting(_:));
+ (BOOL)startSession:(AVAssetWriter *)writer at:(CMTime)time NS_SWIFT_NAME(startSession(_:at:));
+ (BOOL)appendSample:(CMSampleBufferRef)sample to:(AVAssetWriterInput *)input
    NS_SWIFT_NAME(appendSample(_:to:));
+ (BOOL)appendPixels:(CVPixelBufferRef)pixels
                  at:(CMTime)time
                  to:(AVAssetWriterInputPixelBufferAdaptor *)adaptor
    NS_SWIFT_NAME(appendPixels(_:at:to:));
+ (void)finishInput:(AVAssetWriterInput *)input NS_SWIFT_NAME(finishInput(_:));
/// `handler` always runs exactly once, also when the writer refuses to finish
+ (void)finishWriting:(AVAssetWriter *)writer then:(void (^)(void))handler
    NS_SWIFT_NAME(finishWriting(_:then:));
+ (void)cancel:(AVAssetWriter *)writer NS_SWIFT_NAME(cancel(_:));
/// Any other camera call that could throw. NO when it was refused.
+ (BOOL)attempt:(NS_NOESCAPE void (^)(void))work NS_SWIFT_NAME(attempt(_:));

@end

NS_ASSUME_NONNULL_END
