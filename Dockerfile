FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Metatrader Docker:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="gmartin"

ENV TITLE=Metatrader5
ENV WINEPREFIX="/config/.wine"
ENV WINEDEBUG=-all

# Kron4ek Wine
ENV KRON_WINE_VER=10.2
ENV KRON_WINE_ASSET=wine-10.2-staging-tkg-amd64-wow64.tar.xz

# Install packages + download/extract Kron4ek wine
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends libc6:i386 libc6-i386 libstdc++6:i386 zlib1g:i386 \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
	python3-xdg \
        wget \
        curl \
        ca-certificates \
        git \
        xz-utils \
    && mkdir -p /opt/wine-kron4ek \
    && curl -fsSL -o /tmp/${KRON_WINE_ASSET} \
        https://github.com/Kron4ek/Wine-Builds/releases/download/${KRON_WINE_VER}/${KRON_WINE_ASSET} \
    && tar -xJf /tmp/${KRON_WINE_ASSET} -C /opt/wine-kron4ek \
    && rm -f /tmp/${KRON_WINE_ASSET} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY /Metatrader /Metatrader
RUN chmod +x /Metatrader/start.sh /Metatrader/app_win.sh

COPY /root /

EXPOSE 3000 8001
VOLUME /config
