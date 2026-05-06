# syntax=docker/dockerfile:1

# Build stage
#
# SM_REF=v*.*.* → download official AppImage (no build, signatures preserved)
# SM_REF=main/branch/SHA → source build with quilt patches applied
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS builder

ARG SM_REF=main

COPY patches/ /patches/

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git quilt squashfs-tools unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Try shallow clone for branch/tag refs, then fall back for bare commit SHAs.
# Branch: version tag → download AppImage; branch/commit → source build with patches.
RUN <<'BUILD_STABILITY_MATRIX'
set -eu
mkdir -p /build/publish /build/root/usr/bin
if echo "${SM_REF}" | grep -qE '^v[0-9]+\.[0-9]+'; then
    echo "[builder] Downloading AppImage for release ${SM_REF}..."
    curl -fsSL \
      "https://github.com/LykosAI/StabilityMatrix/releases/download/${SM_REF}/StabilityMatrix-linux-x64.zip" \
      -o /tmp/StabilityMatrix.zip
    unzip -q /tmp/StabilityMatrix.zip -d /tmp
    chmod +x /tmp/StabilityMatrix.AppImage
    cd /build
    /tmp/StabilityMatrix.AppImage --appimage-extract usr
    mv -v /build/squashfs-root/usr/bin/StabilityMatrix.Avalonia /build/root/usr/bin/StabilityMatrix.Avalonia
    echo "${SM_REF}" > /build/commit.sha
else
    echo "[builder] Cloning source for ref ${SM_REF}..."
    git clone --depth 1 --branch "${SM_REF}" \
        https://github.com/LykosAI/StabilityMatrix.git /src 2>/dev/null \
    || (git clone https://github.com/LykosAI/StabilityMatrix.git /src \
        && git -C /src checkout "${SM_REF}")
    cd /src
    QUILT_PATCHES=/patches quilt push -a
    dotnet restore
    dotnet publish StabilityMatrix.Avalonia/StabilityMatrix.Avalonia.csproj \
        --configuration Release \
        --runtime linux-x64 \
        --self-contained true \
        -p:PublishSingleFile=true \
        -p:DebugType=none \
        -p:DebugSymbols=false \
        -p:SkipSigning=true \
        --output /build/publish
    ls -l /build/publish/
    mv -v /build/publish/* /build/root/usr/bin/
    git -C /src rev-parse --short HEAD > /build/commit.sha
fi
chmod +x /build/root/usr/bin/StabilityMatrix.Avalonia
BUILD_STABILITY_MATRIX

# Runtime stage
FROM lscr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

ARG BUILD_DATE
ARG SM_VERSION=unknown
ARG SM_COMMIT=unknown

LABEL build_version="docker-stabilitymatrix-vnc:${SM_VERSION} (${SM_COMMIT}) build-date=${BUILD_DATE}"
LABEL org.opencontainers.image.title="docker-stabilitymatrix-vnc"
LABEL org.opencontainers.image.description="StabilityMatrix multi-UI Stable Diffusion manager in browser-based KasmVNC with AMD ROCm GPU passthrough"
LABEL org.opencontainers.image.url="https://github.com/shawly/stabilitymatrix-vnc"
LABEL org.opencontainers.image.source="https://github.com/shawly/stabilitymatrix-vnc"
LABEL org.opencontainers.image.documentation="https://github.com/shawly/stabilitymatrix-vnc#readme"
LABEL org.opencontainers.image.vendor="shawly"
LABEL org.opencontainers.image.version="${SM_VERSION}"
LABEL org.opencontainers.image.revision="${SM_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.licenses="GPL-3.0-only AND AGPL-3.0-only"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         ca-certificates \
         desktop-file-utils \
         jq \
         git \
         libicu74 \
         libnotify-bin \
         python3-xdg \
         software-properties-common \
         xclip \
    && add-apt-repository --yes ppa:dotnet/backports \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        dotnet-runtime-9.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/root/ /

COPY root/ /

RUN chmod +x /etc/s6-overlay/s6-rc.d/init-stability-matrix-config/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/init-sm-host-patch/run \
    && chmod +x /usr/local/bin/sm-patch-bindings \
    && chmod +x /usr/local/bin/sm-launch \
    && chmod +x /usr/local/bin/sm-apply-xft-dpi \
    && chmod +x /usr/local/bin/sm-url-copy

ENV SM_HOME_DIR=/config/StabilityMatrix \
    SM_DATA_DIR=/data \
    TITLE="Stability Matrix" \
    NO_DECOR="true" \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    DOTNET_EnableWriteXorExecute=0 \
    APPIMAGE="/usr/bin/StabilityMatrix.Avalonia" \
    GITHUB_TOKEN=""
