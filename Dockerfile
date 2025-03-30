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
  crossbuild-essential-arm64 \
  gcc-aarch64-linux-gnu \
  g++-aarch64-linux-gnu \
  libc6-dev-arm64-cross \
  && rm -rf /var/lib/apt/lists/*

# Install arm64 version of libvips and its dependencies
RUN if [ "$(dpkg --print-architecture)" != "arm64" ]; then \
  dpkg --add-architecture arm64 && \
  DEBIAN_FRONTEND=noninteractive apt-get update && \
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
  && rm -rf /var/lib/apt/lists/* ; \
  fi

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

# Configure cross-compilation environment for ARM64
RUN echo '#!/bin/bash\nexport CC=aarch64-linux-gnu-gcc\nexport CXX=aarch64-linux-gnu-g++\nexport CGO_ENABLED=1\nexport GOOS=linux\nexport GOARCH=arm64\nexport PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig\n\n$@' > /usr/local/bin/build-arm64.sh && \
    chmod +x /usr/local/bin/build-arm64.sh

COPY *.sh /
ENTRYPOINT ["/entrypoint.sh"]

LABEL maintainer = "MDFriday <me@sunwei.xyz>"
LABEL org.opencontainers.image.source = "https://github.com/mdfriday/hugoverse-release"
