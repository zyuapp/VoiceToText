#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_VERSION="1.13.4"
ARCHIVE_NAME="sherpa-onnx-v${RUNTIME_VERSION}-osx-arm64-static-lib.tar.bz2"
ARCHIVE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${RUNTIME_VERSION}/${ARCHIVE_NAME}"
ARCHIVE_SHA256="57801db2bbb786a5d343f515a38ff210b401842338bdc804fa075312d1cd2404"
RUNTIME_DIR="${PROJECT_ROOT}/sherpa-onnx"
VERSION_MARKER="${RUNTIME_DIR}/.just-speak-runtime"
LIBRARY_FILELIST="${PROJECT_ROOT}/ParakeetLibraries.filelist"

runtime_is_current() {
    [ -f "${VERSION_MARKER}" ] || return 1
    [ -s "${LIBRARY_FILELIST}" ] || return 1
    [ "$(sed -n '1p' "${VERSION_MARKER}")" = "${RUNTIME_VERSION}" ] || return 1
    [ "$(sed -n '2p' "${VERSION_MARKER}")" = "${ARCHIVE_SHA256}" ] || return 1

    while IFS= read -r library; do
        [ -n "${library}" ] || continue
        [ -f "${PROJECT_ROOT}/${library}" ] || return 1
    done < "${LIBRARY_FILELIST}"
}

if runtime_is_current; then
    echo "sherpa-onnx ${RUNTIME_VERSION} is already installed."
    exit 0
fi

SETUP_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${SETUP_TMP_DIR}"' EXIT

ARCHIVE_PATH="${SETUP_TMP_DIR}/${ARCHIVE_NAME}"
if [ -n "${SHERPA_ONNX_ARCHIVE:-}" ]; then
    cp "${SHERPA_ONNX_ARCHIVE}" "${ARCHIVE_PATH}"
else
    echo "Downloading sherpa-onnx ${RUNTIME_VERSION}..."
    curl --fail --location --output "${ARCHIVE_PATH}" "${ARCHIVE_URL}"
fi

ACTUAL_SHA256="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
if [ "${ACTUAL_SHA256}" != "${ARCHIVE_SHA256}" ]; then
    echo "sherpa-onnx checksum mismatch." >&2
    exit 1
fi

tar -xjf "${ARCHIVE_PATH}" -C "${SETUP_TMP_DIR}"
EXTRACTED_DIR="${SETUP_TMP_DIR}/${ARCHIVE_NAME%.tar.bz2}"

if [ ! -d "${EXTRACTED_DIR}/lib" ]; then
    echo "sherpa-onnx archive did not contain the expected libraries." >&2
    exit 1
fi

rm -rf "${RUNTIME_DIR}"
mv "${EXTRACTED_DIR}" "${RUNTIME_DIR}"
printf '%s\n%s\n' "${RUNTIME_VERSION}" "${ARCHIVE_SHA256}" > "${VERSION_MARKER}"
echo "Installed sherpa-onnx ${RUNTIME_VERSION} at ${RUNTIME_DIR}."
