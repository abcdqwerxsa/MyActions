# syntax=docker/dockerfile:1
# Ubuntu 24.04 + XFCE4 + Xvfb + voxl browser desktop — single-file build
# voxl: https://github.com/tembo/voxl  (MIT; binary links x264 -> GPL)
#
# build:  docker build -t voxl-desktop .
# run:    docker run -d --name voxl-desktop -p 6901:6901 --shm-size=1g \
#           -e VOXL_PASSWORD=你的密码 -v voxl-home:/home/dev voxl-desktop
# open:   http://localhost:6901/?token=你的密码

# ---------- build stage: compile voxl from crates.io ----------
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|//archive.ubuntu.com|//mirrors.aliyun.com|; s|//security.ubuntu.com|//mirrors.aliyun.com|' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang pkg-config curl ca-certificates git \
      libx264-dev libyuv-dev libopus-dev libpulse-dev esbuild \
    && rm -rf /var/lib/apt/lists/*
ENV RUSTUP_DIST_SERVER=https://rsproxy.cn RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH=/root/.cargo/bin:$PATH
RUN mkdir -p /root/.cargo && printf '[source.crates-io]\nreplace-with = "rsproxy-sparse"\n[source.rsproxy-sparse]\nregistry = "sparse+https://rsproxy.cn/index/"\n' > /root/.cargo/config.toml \
 && cargo install voxl-server

# ---------- runtime stage ----------
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|//archive.ubuntu.com|//mirrors.aliyun.com|; s|//security.ubuntu.com|//mirrors.aliyun.com|' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update && apt-get install -y --no-install-recommends \
      xfce4 xfce4-terminal dbus-x11 \
      xvfb x11-xserver-utils \
      pulseaudio pulseaudio-utils \
      libx264-164 libyuv0 libopus0 \
      fonts-dejavu fonts-noto-cjk \
      git curl vim sudo build-essential python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 440 /etc/sudoers.d/dev
COPY --from=build /root/.cargo/bin/voxl /usr/local/bin/voxl

COPY <<'EOF' /usr/local/bin/entrypoint.sh
#!/bin/sh
# Xvfb + XFCE4 + voxl
set -u

Xvfb "$DISPLAY" -screen 0 "$RES" -nolisten tcp -shmem &
until xset -q >/dev/null 2>&1; do sleep 0.2; done

# compositing off: cheaper capture, no tearing in the stream
mkdir -p "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
cat > "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'XEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XEOF

# audio: pulseaudio with a null sink so voxl has a monitor source
export XDG_RUNTIME_DIR="/tmp/xdg-runtime"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
pactl load-module module-null-sink sink_name=voxl >/dev/null 2>&1 || true

startxfce4 >/tmp/xfce.log 2>&1 &

exec voxl --addr 0.0.0.0 --port "$PORT" --title "Dev Desktop" $VOXL_ARGS
EOF
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/voxl

USER dev
WORKDIR /home/dev
ENV DISPLAY=:1 RES=1920x1080x24 PORT=6901
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD curl -sf "http://localhost:${PORT}/healthz" || exit 1
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
