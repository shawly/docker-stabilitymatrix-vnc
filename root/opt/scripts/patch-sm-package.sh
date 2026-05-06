#!/usr/bin/env bash

set -euo pipefail

PACKAGE_NAME="${1:?Usage: $0 <package-name> <host> <port> [torch-index]}"
HOST="${2:?Missing host argument}"
PORT="${3:?Missing port argument}"
TORCH_INDEX="${4:-}"

SETTINGS="${SM_DATA_DIR:-/data}/settings.json"

if [[ ! -f "${SETTINGS}" ]]; then
    echo "ERROR: settings.json not found at ${SETTINGS}" >&2
    exit 1
fi

case "${PACKAGE_NAME}" in
    ComfyUI|ComfyZluda)
        HOST_FLAG="--listen"
        ;;
    InvokeAI)
        HOST_FLAG="--host"
        ;;
    *)
        HOST_FLAG="--server-name"
        ;;
esac

JQ_FILTER='
  .InstalledPackages |= map(
    if .PackageName == $pkg then
      .LaunchArgs = (
        (.LaunchArgs // [])
        | map(select(.Name != $host_flag and .Name != "--port"))
        + [
            {"Name": $host_flag, "Type": "String", "OptionValue": $host},
            {"Name": "--port",   "Type": "String", "OptionValue": $port}
          ]
      )
    else . end
  )
'

MATCH_COUNT="$(jq --arg pkg "${PACKAGE_NAME}" '[.InstalledPackages[] | select(.PackageName == $pkg)] | length' "${SETTINGS}")"
if [[ "${MATCH_COUNT}" -eq 0 ]]; then
    echo "ERROR: package '${PACKAGE_NAME}' not found in ${SETTINGS}" >&2
    exit 1
fi

jq --arg pkg       "${PACKAGE_NAME}" \
   --arg host_flag "${HOST_FLAG}" \
   --arg host      "${HOST}" \
   --arg port      "${PORT}" \
   "${JQ_FILTER}" \
   "${SETTINGS}" > "${SETTINGS}.tmp" \
&& mv "${SETTINGS}.tmp" "${SETTINGS}"

echo "[patch-sm-package] Set ${HOST_FLAG}=${HOST}, --port=${PORT} for ${PACKAGE_NAME}"

if [[ -n "${TORCH_INDEX}" ]]; then
    jq --arg pkg "${PACKAGE_NAME}" --arg idx "${TORCH_INDEX}" \
       '.InstalledPackages |= map(
          if .PackageName == $pkg
          then .PreferredTorchIndex = $idx
          else . end
        )' \
       "${SETTINGS}" > "${SETTINGS}.tmp" \
    && mv "${SETTINGS}.tmp" "${SETTINGS}"
    echo "[patch-sm-package] Set PreferredTorchIndex=${TORCH_INDEX} for ${PACKAGE_NAME}"
fi
