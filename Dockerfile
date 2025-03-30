FROM debian:buster-slim
ARG UPX_VER
ARG UPLOADER_VER
ARG TARGETARCH
ENV UPX_VER=${UPX_VER:-4.0.0}
ENV UPLOADER_VER=${UPLOADER_VER:-v0.13.0}

# Install core dependencies including vips and CGO requirements
RUN DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  curl \
  wget \
  git \
  build-essential \
  zip \
  xz-utils \
  jq \
  ca-certificates \
  pkg-config \
  libvips-dev \
  libglib2.0-dev \
  libjpeg-dev \
  libpng-dev \
  libwebp-dev \
  libgif-dev \
  libtiff-dev \
  libexif-dev \
  libgsf-1-dev \
  liblcms2-dev \
  libheif-dev \
  liborc-0.4-dev \
  gcc \
  g++ \
  gcc-aarch64-linux-gnu \
  g++-aarch64-linux-gnu \
  && rm -rf /var/lib/apt/lists/*

# Add ARM64 architecture and install ARM64 libraries for cross-compilation
RUN dpkg --add-architecture arm64 && \
    echo "deb [arch=arm64] http://deb.debian.org/debian buster main" >> /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    libvips-dev:arm64 \
    libglib2.0-dev:arm64 \
    libjpeg-dev:arm64 \
    libpng-dev:arm64 \
    libwebp-dev:arm64 \
    libgif-dev:arm64 \
    libtiff-dev:arm64 \
    libexif-dev:arm64 \
    libgsf-1-dev:arm64 \
    liblcms2-dev:arm64 \
    libheif-dev:arm64 \
    liborc-0.4-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

# install latest upx by wget instead of `apt install upx-ucl`
RUN export arch=$(dpkg --print-architecture) || arch=${TARGETARCH} && \
  wget --no-check-certificate --progress=dot:mega https://github.com/upx/upx/releases/download/v${UPX_VER}/upx-${UPX_VER}-${arch}_linux.tar.xz && \
  tar -Jxf upx-${UPX_VER}-${arch}_linux.tar.xz && \
  mv upx-${UPX_VER}-${arch}_linux /usr/local/ && \
  ln -s /usr/local/upx-${UPX_VER}-${arch}_linux/upx /usr/local/bin/upx && \
  rm upx-${UPX_VER}-${arch}_linux.tar.xz && \
  upx --version

# github-assets-uploader to provide robust github assets upload
RUN export arch=$(dpkg --print-architecture) && wget --no-check-certificate --progress=dot:mega https://github.com/wangyoucao577/assets-uploader/releases/download/${UPLOADER_VER}/github-assets-uploader-${UPLOADER_VER}-linux-${arch}.tar.gz -O github-assets-uploader.tar.gz && \
  tar -zxf github-assets-uploader.tar.gz && \
  mv github-assets-uploader /usr/sbin/ && \
  rm -f github-assets-uploader.tar.gz && \
  github-assets-uploader -version

# Add Go environment variables to support CGO
ENV CGO_ENABLED=1

# Configure pkg-config to find arm64 libraries
RUN mkdir -p /usr/lib/aarch64-linux-gnu/pkgconfig && \
    ln -sf /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    ln -sf /usr/lib/aarch64-linux-gnu/pkgconfig/glib-2.0.pc /usr/lib/aarch64-linux-gnu/pkgconfig/glib-2.0.pc && \
    ln -sf /usr/lib/aarch64-linux-gnu/pkgconfig/gobject-2.0.pc /usr/lib/aarch64-linux-gnu/pkgconfig/gobject-2.0.pc && \
    ln -sf /usr/lib/aarch64-linux-gnu/pkgconfig/gmodule-2.0.pc /usr/lib/aarch64-linux-gnu/pkgconfig/gmodule-2.0.pc && \
    ln -sf /usr/lib/aarch64-linux-gnu/pkgconfig/gio-2.0.pc /usr/lib/aarch64-linux-gnu/pkgconfig/gio-2.0.pc

# Fix missing library links for ARM64 cross-compilation
RUN ln -sf /usr/lib/aarch64-linux-gnu/libvips.so /usr/aarch64-linux-gnu/lib/libvips.so && \
    ln -sf /usr/lib/aarch64-linux-gnu/libglib-2.0.so /usr/aarch64-linux-gnu/lib/libglib-2.0.so && \
    ln -sf /usr/lib/aarch64-linux-gnu/libgobject-2.0.so /usr/aarch64-linux-gnu/lib/libgobject-2.0.so && \
    ln -sf /usr/lib/aarch64-linux-gnu/libgmodule-2.0.so /usr/aarch64-linux-gnu/lib/libgmodule-2.0.so && \
    ln -sf /usr/lib/aarch64-linux-gnu/libgio-2.0.so /usr/aarch64-linux-gnu/lib/libgio-2.0.so

# Configure cross-compilation environment for ARM64
RUN echo '#!/bin/bash\n\
# Cross-compilation script for ARM64 architecture\n\
\n\
# Ensure Go is available\n\
if [ -f "/go.env" ]; then\n\
  source /go.env\n\
fi\n\
\n\
# Set basic environment variables for ARM64 cross-compilation\n\
export CGO_ENABLED=1\n\
export GOOS=linux\n\
export GOARCH=arm64\n\
\n\
# Set C/C++ cross-compilers\n\
export CC=aarch64-linux-gnu-gcc\n\
export CXX=aarch64-linux-gnu-g++\n\
\n\
# Set pkg-config path for ARM64\n\
export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig\n\
\n\
# Set additional environment variables to help with linking\n\
export CGO_LDFLAGS="-L/usr/lib/aarch64-linux-gnu/ -L/usr/aarch64-linux-gnu/lib/"\n\
export CGO_CFLAGS="-I/usr/include/aarch64-linux-gnu"\n\
\n\
# Make sure PATH includes Go binaries\n\
export PATH=$PATH:/usr/local/go/bin:/go/bin:/usr/local/bin\n\
\n\
# Find Go binary\n\
GO_BIN="go"\n\
if [ "$1" = "go" ] || [[ "$1" == */go ]]; then\n\
  GO_BIN="$1"\n\
  shift\n\
fi\n\
\n\
# Print environment for debugging\n\
echo "=== ARM64 Build Environment ==="\n\
echo "CC: $CC"\n\
echo "CXX: $CXX"\n\
echo "GOOS: $GOOS"\n\
echo "GOARCH: $GOARCH"\n\
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"\n\
echo "PATH: $PATH"\n\
echo "Go binary: $GO_BIN"\n\
which $GO_BIN || echo "WARNING: Go not found in PATH!"\n\
echo "==========================="\n\
\n\
# Execute the actual command\n\
echo "Running command for ARM64: $GO_BIN $@"\n\
exec $GO_BIN "$@"' > /usr/local/bin/build-arm64.sh && \
    chmod +x /usr/local/bin/build-arm64.sh

COPY *.sh /
ENTRYPOINT ["/entrypoint.sh"]

LABEL maintainer = "MDFriday <me@sunwei.xyz>"
LABEL org.opencontainers.image.source = "https://github.com/mdfriday/hugoverse-release"
