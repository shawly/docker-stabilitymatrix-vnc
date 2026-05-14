# syntax=docker/dockerfile:1

# Build stage
#
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS builder

ARG SM_REF=main

COPY patches/ /patches/

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl git quilt squashfs-tools unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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
    mv -v /build/publish/* /build/root/usr/bin/
fi
chmod +x /build/root/usr/bin/StabilityMatrix.Avalonia
BUILD_STABILITY_MATRIX

# Runtime stage
FROM lscr.io/linuxserver/baseimage-kasmvnc:ubuntunoble

ARG BUILD_DATE
ARG SM_VERSION=unknown
ARG SM_COMMIT=unknown
ARG ROCM_VERSION=7.2.3

LABEL build_version="docker-stabilitymatrix-vnc:${SM_VERSION} (${SM_COMMIT}) build-date=${BUILD_DATE}"
LABEL org.opencontainers.image.title="docker-stabilitymatrix-vnc"
LABEL org.opencontainers.image.description="StabilityMatrix multi-UI Stable Diffusion manager in browser-based Selkies with AMD ROCm GPU passthrough"
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
        pkg-config \
        libcairo2-dev \
        xclip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN <<'INSTALL_ROCM'
set -eu

if [[ -z "${ROCM_VERSION}" ]]; then
    echo "ROCM_VERSION is not set. Skipping ROCm installation."
    exit 0
fi

mkdir --parents --mode=0755 /etc/apt/keyrings

curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg

tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu noble main
EOF

tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

apt-get update
apt-get install -y --no-install-recommends \
        sudo \
        libelf1 \
        libdw1t64 \
        libfile-which-perl \
        liburi-perl \
        kmod \
        file \
        python3-dev \
        python3-pip \
        rocm-dev \
        build-essential 
apt-get clean
rm -rf /var/lib/apt/lists/*

INSTALL_ROCM

COPY --from=builder /build/root/ /

COPY root/ /

ENV SM_HOME_DIR=/config/StabilityMatrix \
    SM_DATA_DIR=/data \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    DOTNET_EnableWriteXorExecute=0 \
    APPIMAGE="/usr/bin/StabilityMatrix.Avalonia" \
    FM_HOME=/data \
    NO_DECOR=true \
    TITLE="Stability Matrix"
