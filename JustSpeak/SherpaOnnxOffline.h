#ifndef SherpaOnnxOffline_h
#define SherpaOnnxOffline_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t sample_rate;
    int32_t feature_dim;
} SherpaOnnxFeatureConfig;

typedef struct {
    const char *dict_dir;
    const char *lexicon;
    const char *rule_fsts;
} SherpaOnnxHomophoneReplacerConfig;

typedef struct {
    const char *encoder;
    const char *decoder;
    const char *joiner;
} SherpaOnnxOfflineTransducerModelConfig;

typedef struct { const char *model; } SherpaOnnxOfflineParaformerModelConfig;
typedef struct { const char *model; } SherpaOnnxOfflineNemoEncDecCtcModelConfig;

typedef struct {
    const char *encoder;
    const char *decoder;
    const char *language;
    const char *task;
    int32_t tail_paddings;
    int32_t enable_token_timestamps;
    int32_t enable_segment_timestamps;
} SherpaOnnxOfflineReservedEncoderDecoderModelConfig;

typedef struct { const char *model; } SherpaOnnxOfflineTdnnModelConfig;

typedef struct {
    const char *model;
    const char *language;
    int32_t use_itn;
} SherpaOnnxOfflineSenseVoiceModelConfig;

typedef struct {
    const char *preprocessor;
    const char *encoder;
    const char *uncached_decoder;
    const char *cached_decoder;
    const char *merged_decoder;
} SherpaOnnxOfflineMoonshineModelConfig;

typedef struct {
    const char *encoder;
    const char *decoder;
} SherpaOnnxOfflineFireRedAsrModelConfig;

typedef struct { const char *model; } SherpaOnnxOfflineDolphinModelConfig;
typedef struct { const char *model; } SherpaOnnxOfflineZipformerCtcModelConfig;

typedef struct {
    const char *encoder;
    const char *decoder;
    const char *src_lang;
    const char *tgt_lang;
    int32_t use_pnc;
} SherpaOnnxOfflineCanaryModelConfig;

typedef struct { const char *model; } SherpaOnnxOfflineWenetCtcModelConfig;
typedef struct { const char *model; } SherpaOnnxOfflineOmnilingualAsrCtcModelConfig;
typedef struct { const char *model; } SherpaOnnxOfflineMedAsrCtcModelConfig;

typedef struct {
    const char *encoder_adaptor;
    const char *llm;
    const char *embedding;
    const char *tokenizer;
    const char *system_prompt;
    const char *user_prompt;
    int32_t max_new_tokens;
    float temperature;
    float top_p;
    int32_t seed;
    const char *language;
    int32_t itn;
    const char *hotwords;
} SherpaOnnxOfflineFunASRNanoModelConfig;

typedef struct { const char *model; } SherpaOnnxOfflineFireRedAsrCtcModelConfig;

typedef struct {
    const char *conv_frontend;
    const char *encoder;
    const char *decoder;
    const char *tokenizer;
    int32_t max_total_len;
    int32_t max_new_tokens;
    float temperature;
    float top_p;
    int32_t seed;
    const char *hotwords;
} SherpaOnnxOfflineQwen3ASRModelConfig;

typedef struct {
    const char *encoder;
    const char *decoder;
    const char *language;
    int32_t use_punct;
    int32_t use_itn;
} SherpaOnnxOfflineCohereTranscribeModelConfig;

typedef struct {
    SherpaOnnxOfflineTransducerModelConfig transducer;
    SherpaOnnxOfflineParaformerModelConfig paraformer;
    SherpaOnnxOfflineNemoEncDecCtcModelConfig nemo_ctc;
    SherpaOnnxOfflineReservedEncoderDecoderModelConfig reserved_encoder_decoder;
    SherpaOnnxOfflineTdnnModelConfig tdnn;
    const char *tokens;
    int32_t num_threads;
    int32_t debug;
    const char *provider;
    const char *model_type;
    const char *modeling_unit;
    const char *bpe_vocab;
    const char *telespeech_ctc;
    SherpaOnnxOfflineSenseVoiceModelConfig sense_voice;
    SherpaOnnxOfflineMoonshineModelConfig moonshine;
    SherpaOnnxOfflineFireRedAsrModelConfig fire_red_asr;
    SherpaOnnxOfflineDolphinModelConfig dolphin;
    SherpaOnnxOfflineZipformerCtcModelConfig zipformer_ctc;
    SherpaOnnxOfflineCanaryModelConfig canary;
    SherpaOnnxOfflineWenetCtcModelConfig wenet_ctc;
    SherpaOnnxOfflineOmnilingualAsrCtcModelConfig omnilingual;
    SherpaOnnxOfflineMedAsrCtcModelConfig medasr;
    SherpaOnnxOfflineFunASRNanoModelConfig funasr_nano;
    SherpaOnnxOfflineFireRedAsrCtcModelConfig fire_red_asr_ctc;
    SherpaOnnxOfflineQwen3ASRModelConfig qwen3_asr;
    SherpaOnnxOfflineCohereTranscribeModelConfig cohere_transcribe;
} SherpaOnnxOfflineModelConfig;

typedef struct {
    const char *model;
    float scale;
} SherpaOnnxOfflineLMConfig;

typedef struct {
    SherpaOnnxFeatureConfig feat_config;
    SherpaOnnxOfflineModelConfig model_config;
    SherpaOnnxOfflineLMConfig lm_config;
    const char *decoding_method;
    int32_t max_active_paths;
    const char *hotwords_file;
    float hotwords_score;
    const char *rule_fsts;
    const char *rule_fars;
    float blank_penalty;
    SherpaOnnxHomophoneReplacerConfig hr;
} SherpaOnnxOfflineRecognizerConfig;

typedef struct SherpaOnnxOfflineRecognizer SherpaOnnxOfflineRecognizer;
typedef struct SherpaOnnxOfflineStream SherpaOnnxOfflineStream;

typedef struct {
    const char *text;
    float *timestamps;
    int32_t count;
    const char *tokens;
    const char *const *tokens_arr;
    const char *json;
    const char *lang;
    const char *emotion;
    const char *event;
    float *durations;
    float *ys_log_probs;
    const float *segment_timestamps;
    const float *segment_durations;
    const char *segment_texts;
    const char *const *segment_texts_arr;
    int32_t segment_count;
} SherpaOnnxOfflineRecognizerResult;

const SherpaOnnxOfflineRecognizer *SherpaOnnxCreateOfflineRecognizer(
    const SherpaOnnxOfflineRecognizerConfig *config
);
void SherpaOnnxDestroyOfflineRecognizer(const SherpaOnnxOfflineRecognizer *recognizer);
const SherpaOnnxOfflineStream *SherpaOnnxCreateOfflineStream(
    const SherpaOnnxOfflineRecognizer *recognizer
);
void SherpaOnnxDestroyOfflineStream(const SherpaOnnxOfflineStream *stream);
void SherpaOnnxAcceptWaveformOffline(
    const SherpaOnnxOfflineStream *stream,
    int32_t sample_rate,
    const float *samples,
    int32_t count
);
void SherpaOnnxDecodeOfflineStream(
    const SherpaOnnxOfflineRecognizer *recognizer,
    const SherpaOnnxOfflineStream *stream
);
const SherpaOnnxOfflineRecognizerResult *SherpaOnnxGetOfflineStreamResult(
    const SherpaOnnxOfflineStream *stream
);
void SherpaOnnxDestroyOfflineRecognizerResult(
    const SherpaOnnxOfflineRecognizerResult *result
);

#ifdef __cplusplus
}
#endif

#endif
