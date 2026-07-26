#import "ParakeetBridge.h"
#import "SherpaOnnxOffline.h"

#include <algorithm>
#include <thread>

static NSString *const ParakeetBridgeErrorDomain = @"com.zyu.just-speak.parakeet";

typedef NS_ENUM(NSInteger, ParakeetBridgeErrorCode) {
    ParakeetBridgeErrorInvalidModel = 1,
    ParakeetBridgeErrorInitializationFailed = 2,
    ParakeetBridgeErrorInvalidAudio = 3,
    ParakeetBridgeErrorTranscriptionFailed = 4,
};

@interface ParakeetBridge () {
    const SherpaOnnxOfflineRecognizer *_recognizer;
}
@end

@implementation ParakeetBridge

- (nullable instancetype)initWithEncoderPath:(NSString *)encoderPath
                                 decoderPath:(NSString *)decoderPath
                                  joinerPath:(NSString *)joinerPath
                                  tokensPath:(NSString *)tokensPath
                                       error:(NSError **)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSArray<NSString *> *files = @[encoderPath, decoderPath, joinerPath, tokensPath];

    for (NSString *file in files) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
            if (error) {
                *error = [self errorWithCode:ParakeetBridgeErrorInvalidModel
                                description:[NSString stringWithFormat:@"Missing Parakeet model file %@", file.lastPathComponent]];
            }
            return nil;
        }
    }

    SherpaOnnxOfflineRecognizerConfig config = {};
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoderPath.fileSystemRepresentation;
    config.model_config.transducer.decoder = decoderPath.fileSystemRepresentation;
    config.model_config.transducer.joiner = joinerPath.fileSystemRepresentation;
    config.model_config.tokens = tokensPath.fileSystemRepresentation;
    config.model_config.num_threads = static_cast<int32_t>(
        std::clamp(std::thread::hardware_concurrency(), 2u, 8u)
    );
    config.model_config.provider = "cpu";
    config.model_config.model_type = "nemo_transducer";
    config.decoding_method = "greedy_search";

    _recognizer = SherpaOnnxCreateOfflineRecognizer(&config);
    if (!_recognizer) {
        if (error) {
            *error = [self errorWithCode:ParakeetBridgeErrorInitializationFailed
                            description:@"Failed to initialize the Parakeet model."];
        }
        return nil;
    }

    return self;
}

- (void)dealloc {
    if (_recognizer) {
        SherpaOnnxDestroyOfflineRecognizer(_recognizer);
    }
}

- (nullable NSString *)transcribeSamples:(const float *)samples
                                   count:(NSInteger)count
                                   error:(NSError **)error {
    if (!samples || count <= 0 || count > INT32_MAX) {
        if (error) {
            *error = [self errorWithCode:ParakeetBridgeErrorInvalidAudio
                            description:@"Audio samples are invalid."];
        }
        return nil;
    }

    const SherpaOnnxOfflineStream *stream = SherpaOnnxCreateOfflineStream(_recognizer);
    if (!stream) {
        if (error) {
            *error = [self errorWithCode:ParakeetBridgeErrorTranscriptionFailed
                            description:@"Failed to create a Parakeet transcription stream."];
        }
        return nil;
    }

    SherpaOnnxAcceptWaveformOffline(stream, 16000, samples, static_cast<int32_t>(count));
    SherpaOnnxDecodeOfflineStream(_recognizer, stream);

    const SherpaOnnxOfflineRecognizerResult *result =
        SherpaOnnxGetOfflineStreamResult(stream);
    NSString *text = nil;
    if (result && result->text) {
        text = [NSString stringWithUTF8String:result->text];
    }

    if (result) {
        SherpaOnnxDestroyOfflineRecognizerResult(result);
    }
    SherpaOnnxDestroyOfflineStream(stream);

    if (!text) {
        if (error) {
            *error = [self errorWithCode:ParakeetBridgeErrorTranscriptionFailed
                            description:@"Parakeet returned an invalid transcription result."];
        }
        return nil;
    }

    return text;
}

- (NSError *)errorWithCode:(ParakeetBridgeErrorCode)code
               description:(NSString *)description {
    return [NSError errorWithDomain:ParakeetBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

@end
