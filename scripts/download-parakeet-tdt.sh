#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_ROOT="${ROOT_DIR}/models"
MODEL_DIR="${MODEL_ROOT}/parakeet-tdt"
ARCHIVE="${MODEL_ROOT}/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2"

mkdir -p "${MODEL_ROOT}"
curl -L "${URL}" -o "${ARCHIVE}"
tar -xjf "${ARCHIVE}" -C "${MODEL_ROOT}"
rm -rf "${MODEL_DIR}"
mv "${MODEL_ROOT}/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8" "${MODEL_DIR}"

echo "Parakeet TDT model ready at ${MODEL_DIR}"
