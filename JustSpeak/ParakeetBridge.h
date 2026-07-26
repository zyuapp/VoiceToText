#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ParakeetBridge : NSObject

- (nullable instancetype)initWithEncoderPath:(NSString *)encoderPath
                                 decoderPath:(NSString *)decoderPath
                                  joinerPath:(NSString *)joinerPath
                                  tokensPath:(NSString *)tokensPath
                                       error:(NSError **)error;

- (nullable NSString *)transcribeSamples:(const float *)samples
                                   count:(NSInteger)count
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
