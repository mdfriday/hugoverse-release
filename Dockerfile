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
  && rm -rf /var/lib/apt/lists/*

# install latest upx 3.96 by wget instead of `apt install upx-ucl`(only 3.95)
RUN export arch=$(dpkg --print-architecture) && wget --no-check-certificate --progress=dot:mega https://github.com/upx/upx/releases/download/v${UPX_VER}/upx-${UPX_VER}-${arch}_linux.tar.xz && \
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

COPY *.sh /
ENTRYPOINT ["/entrypoint.sh"]

LABEL maintainer = "MDFriday <me@sunwei.xyz>"
LABEL org.opencontainers.image.source = "https://github.com/mdfriday/hugoverse-release"
