#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR_CMD="${CURRENT_DIR}/src/autoreload.sh"

chmod +x "${AR_CMD}" 2>/dev/null || true

"${AR_CMD}" ensure >/dev/null 2>&1
