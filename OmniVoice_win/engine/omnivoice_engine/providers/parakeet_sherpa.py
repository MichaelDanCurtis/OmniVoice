from __future__ import annotations

from .sherpa_offline import SAMPLE_RATE, SherpaOfflineProvider


class ParakeetSherpaProvider(SherpaOfflineProvider):
    """NVIDIA Parakeet-TDT (NeMo transducer) via sherpa-onnx.

    The default Windows model: multilingual, INT8-quantised, and fast enough to
    run faster-than-real-time on a plain CPU — with the same files reused on an
    NVIDIA GPU when the CUDA execution provider is available.
    """

    id = "parakeet-tdt"
    label = "Parakeet TDT"
    model_dir_name = "parakeet-tdt"
    model_dir_env_var = "OMNIVOICE_PARAKEET_MODEL_DIR"
    model_layouts = [
        ("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"),
        ("encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt"),
    ]

    def _build_recognizer(self, execution_provider: str):
        import sherpa_onnx

        encoder, decoder, joiner, tokens = self._model_paths()
        return sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=str(encoder),
            decoder=str(decoder),
            joiner=str(joiner),
            tokens=str(tokens),
            num_threads=4,
            sample_rate=SAMPLE_RATE,
            feature_dim=80,
            decoding_method="greedy_search",
            model_type="nemo_transducer",
            provider=execution_provider,
        )
