#!/usr/bin/env bash
# Pull mywellwallet.db from a physical iPhone into fixtures/test_database_export/
# Prereqs: unlocked device, paired Mac, devicectl (Xcode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${ROOT}/fixtures/test_database_export"
DEST_DB="${DEST_DIR}/mywellwallet_phone.sqlite3"
BUNDLE_ID="com.mywellwallet.mywellwallet"
REL_DB_PATH="Documents/mywellwallet.db"

mkdir -p "${DEST_DIR}"

DEVICE="${1:-}"
if [[ -z "${DEVICE}" ]]; then
  # Prefer Flutter-reported iOS device id when only one phone is connected
  DEVICE="$(flutter devices 2>/dev/null | grep -E '• ios' | head -1 | awk -F'•' '{print $2}' | tr -d ' ' || true)"
fi

if [[ -z "${DEVICE}" ]]; then
  echo "Usage: $0 <device_udid_or_name>" >&2
  echo "Or connect one iPhone and ensure 'flutter devices' lists it." >&2
  exit 1
fi

echo "Device: ${DEVICE}"
xcrun devicectl device copy from \
  --device "${DEVICE}" \
  --source "${REL_DB_PATH}" \
  --destination "${DEST_DB}" \
  --domain-type appDataContainer \
  --domain-identifier "${BUNDLE_ID}"

cp "${ROOT}/docs/SQLITE_SCHEMA.md" "${DEST_DIR}/SQLITE_SCHEMA.md"
echo "Wrote ${DEST_DB}"
echo "Updated ${DEST_DIR}/SQLITE_SCHEMA.md"
