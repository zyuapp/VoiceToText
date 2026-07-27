# Third-party notices

## Parakeet TDT 0.6B v2

- Creator: NVIDIA Corporation
- Source: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- License: Creative Commons Attribution 4.0 International
- License text: https://creativecommons.org/licenses/by/4.0/legalcode

JustSpeak downloads an INT8 ONNX conversion packaged for sherpa-onnx. The
conversion and packaging differ from NVIDIA's original distribution. NVIDIA
does not endorse JustSpeak.

## Native runtime

JustSpeak statically links the sherpa-onnx 1.13.4 macOS arm64 runtime and its
runtime dependencies:

- sherpa-onnx, Kaldi decoder, kaldi-native-fbank, kaldifst, OpenFST, and
  simple-sentencepiece: Apache License 2.0
- ONNX Runtime: MIT License with third-party notices
- KissFFT: BSD 3-Clause License

Source and license materials:

- https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.4
- https://github.com/microsoft/onnxruntime

The full license and third-party notice texts shipped with the app are in this
directory.
