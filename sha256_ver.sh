#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_IO_ERROR=2
readonly EXIT_DEPENDENCY_ERROR=3
readonly EXIT_HASH_MISMATCH=4

readonly TARGET_FILE="${1:-}"
readonly CHECKSUM_SOURCE="${2:-}"

log_error() {
    printf "[ERROR] %s\n" "$1" >&2
}

if [[ -z "${TARGET_FILE}" ]] || [[ -z "${CHECKSUM_SOURCE}" ]]; then
    log_error "Usage: $0 <file> <checksum_file>"
    exit "${EXIT_INVALID_ARGS}"
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
    log_error "Target file not found: ${TARGET_FILE}"
    exit "${EXIT_IO_ERROR}"
fi

if [[ ! -f "${CHECKSUM_SOURCE}" ]]; then
    log_error "Checksum source file not found: ${CHECKSUM_SOURCE}"
    exit "${EXIT_IO_ERROR}"
fi

if ! command -v sha256sum &> /dev/null; then
    log_error "Dependency 'sha256sum' (coreutils) is required."
    exit "${EXIT_DEPENDENCY_ERROR}"
fi

readonly EXPECTED_HASH=$(awk '{print tolower($1)}' "${CHECKSUM_SOURCE}" | head -n 1)
readonly ACTUAL_HASH=$(sha256sum "${TARGET_FILE}" | awk '{print tolower($1)}')

if [[ ! "${EXPECTED_HASH}" =~ ^[a-f0-9]{64}$ ]]; then
    log_error "Invalid SHA256 format detected in source file."
    exit "${EXIT_IO_ERROR}"
fi

if [[ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]]; then
    log_error "Verification Failed!"
    printf "Expected: %s\nActual:   %s\n" "${EXPECTED_HASH}" "${ACTUAL_HASH}" >&2
    exit "${EXIT_HASH_MISMATCH}"
fi

printf "Verification Successful: %s\n" "${TARGET_FILE}"
exit "${EXIT_SUCCESS}"
