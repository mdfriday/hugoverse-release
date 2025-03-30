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
    echo "Creating custom vips.pc for ARM64 cross-compilation" && \
    echo "prefix=/usr" > /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "exec_prefix=\${prefix}" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "libdir=\${prefix}/lib/aarch64-linux-gnu" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "includedir=\${prefix}/include" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Name: vips" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Description: Image processing library" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Version: 8.7.4" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Requires: glib-2.0 >= 2.40.0 gobject-2.0 >= 2.40.0 gmodule-2.0 >= 2.40.0 gio-2.0 >= 2.40.0" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Requires.private: libgsf-1 >= 1.14.26 fftw3 >= 3.1.0 lcms2 >= 2.0.0 libexif >= 0.6" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Libs: -L\${libdir} -lvips -lm" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Libs.private: -lm -lz" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc && \
    echo "Cflags: -I\${includedir}" >> /usr/lib/aarch64-linux-gnu/pkgconfig/vips.pc

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
export CGO_LDFLAGS="-L/usr/aarch64-linux-gnu/lib/"\n\
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
