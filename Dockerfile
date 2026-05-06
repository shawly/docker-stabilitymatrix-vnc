# syntax=docker/dockerfile:1

# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0-noble AS builder

ARG SM_REF=main

RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Try shallow clone for branch/tag refs, then fall back for bare commit SHAs.
RUN git clone --depth 1 --branch "${SM_REF}" \
      https://github.com/LykosAI/StabilityMatrix.git /src 2>/dev/null \
    || (git clone https://github.com/LykosAI/StabilityMatrix.git /src \
        && git -C /src checkout "${SM_REF}")

WORKDIR /src
RUN dotnet restore \
  && dotnet publish StabilityMatrix.Avalonia/StabilityMatrix.Avalonia.csproj \
      --configuration Release \
      --runtime linux-x64 \
      --self-contained false \
      -p:PublishSingleFile=true \
      -p:DebugType=none \
      -p:DebugSymbols=false \
      -p:SkipSigning=true \
      --output /build/publish

RUN git -C /src rev-parse --short HEAD > /build/commit.sha

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

COPY --from=builder /build/publish/ /opt/stability-matrix/
RUN chmod +x /opt/stability-matrix/StabilityMatrix.Avalonia \
    && ln -sf /opt/stability-matrix/StabilityMatrix.Avalonia /usr/bin/stability-matrix

COPY root/ /

RUN chmod +x /etc/s6-overlay/s6-rc.d/init-stability-matrix-config/run \
    && chmod +x /opt/scripts/patch-sm-package.sh \
    && chmod +x /usr/local/bin/stability-matrix-launch \
    && chmod +x /usr/local/bin/sm-apply-xft-dpi \
    && chmod +x /usr/local/bin/sm-url-copy

ENV SM_HOME_DIR=/config/StabilityMatrix \
    SM_DATA_DIR=/data \
    TITLE="Stability Matrix" \
    NO_DECOR="true" \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false \
    DOTNET_EnableWriteXorExecute=0 \
    APPIMAGE="/opt/stability-matrix/StabilityMatrix.Avalonia"
