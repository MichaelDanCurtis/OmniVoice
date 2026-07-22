from __future__ import annotations

from .sherpa_offline import SherpaOfflineProvider


class MoonshineSherpaProvider(SherpaOfflineProvider):
    """Moonshine (English) via sherpa-onnx — the low-latency CPU option.

    Built for real-time speech on constrained hardware: far smaller than
    Parakeet and noticeably snappier on a modest CPU, at the cost of being
    English-only. Preferred on machines without a GPU where responsiveness
    matters more than multilingual coverage.
    """

    id = "moonshine-base-en"
    label = "Moonshine Base (English)"
    model_dir_name = "moonshine-base-en"
    model_dir_env_var = "OMNIVOICE_MOONSHINE_MODEL_DIR"
    model_layouts = [
        (
            "preprocess.onnx",
            "encode.int8.onnx",
            "uncached_decode.int8.onnx",
            "cached_decode.int8.onnx",
            "tokens.txt",
        ),
    ]

    def _build_recognizer(self, execution_provider: str):
        import sherpa_onnx

        preprocessor, encoder, uncached_decoder, cached_decoder, tokens = self._model_paths()
        return sherpa_onnx.OfflineRecognizer.from_moonshine(
            preprocessor=str(preprocessor),
            encoder=str(encoder),
            uncached_decoder=str(uncached_decoder),
            cached_decoder=str(cached_decoder),
            tokens=str(tokens),
            num_threads=4,
            decoding_method="greedy_search",
            provider=execution_provider,
        )
