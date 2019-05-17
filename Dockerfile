ARG ALPINE_VER="3.9"
FROM alpine:3.9 as fetch-stage

############## fetch stage ##############

# package versions
ARG MP3GAIN_VER="1.6.2"

# install fetch packages
RUN \
	set -ex \
	&& apk add --no-cache \
		bash \
		curl \
		git \
		unzip

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch version file
RUN \
	set -ex \
	&& curl -o \
	/tmp/version.txt -L \
	"https://raw.githubusercontent.com/sparklyballs/versioning/master/version.txt"

# fetch source code
# hadolint ignore=SC1091
RUN \
	. /tmp/version.txt \
	&& set -ex \
	&& mkdir -p \
		/tmp/beets-src \
		/tmp/mp3gain-src \
	&& curl -o \
	/tmp/beets.tar.gz -L \
	"https://github.com/sampsyo/beets/archive/v${BEETS_RELEASE}.tar.gz" \
	&& curl -o \
	/tmp/mp3gain.zip -L \
	"https://sourceforge.net/projects/mp3gain/files/mp3gain/${MP3GAIN_VER}/mp3gain-${MP3GAIN_VER//./_}-src.zip" \
	&& tar xf \
	/tmp/beets.tar.gz -C \
	/tmp/beets-src --strip-components=1 \
	&& unzip -q /tmp/mp3gain.zip -d /tmp/mp3gain-src \
	&& git clone https://bitbucket.org/acoustid/chromaprint.git /tmp/chromaprint-src \
	&& git clone https://github.com/sbarakat/beets-copyartifacts.git /tmp/copyartifacts-src

FROM alpine:${ALPINE_VER} as beets_build-stage

############## beets build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/beets-src /tmp/beets-src
COPY --from=fetch-stage /tmp/copyartifacts-src /tmp/copyartifacts-src

# set workdir for beets install
WORKDIR /tmp/beets-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		py3-setuptools \
		python3-dev

# build beets package
RUN \
	set -ex \
	&& python3 setup.py build \
	&& python3 setup.py install --prefix=/usr --root=/build/beets

# set workdir for copyartifacts install
WORKDIR /tmp/copyartifacts-src

# build copyartifacts package
RUN \
	set -ex \
	&& python3 setup.py install --prefix=/usr --root=/build/beets

FROM alpine:${ALPINE_VER} as mp3gain_build-stage

############## mp3gain build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/mp3gain-src /tmp/mp3gain-src

# set workdir
WORKDIR /tmp/mp3gain-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		g++ \
		make \
		mpg123-dev

# build package
RUN \
	set -ex \
	&& mkdir -p \
		/build/mp3gain/usr/bin \
	&& sed -i "s#/usr/local/bin#/build/mp3gain/usr/bin#g" Makefile \
	&& make \
	&& make install

FROM alpine:${ALPINE_VER} as chromaprint_build-stage

############## chromaprint build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/chromaprint-src /tmp/chromaprint-src

# set workdir
WORKDIR /tmp/chromaprint-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		cmake \
		ffmpeg-dev \
		fftw-dev \
		g++ \
		make

# build package
RUN \
	set -ex \
	&&  cmake \
		-DBUILD_TOOLS=ON \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX:PATH=/usr \
	&& make \
	&& make DESTDIR=/build/chromaprint install

FROM alpine:${ALPINE_VER} as pip-stage

############## pip packages install stage ##############

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		g++ \
		make \
		py3-pip \
		python3-dev

# install pip packages
RUN \
	set -ex \
	&& pip3 install --no-cache-dir -U \
		discogs-client \
		mutagen \
		pyacoustid \
		pyyaml \
		unidecode

FROM alpine:${ALPINE_VER} as strip-stage

############## strip packages stage ##############

# copy artifacts build stages
COPY --from=beets_build-stage /build/beets/usr/ /build/all//usr/
COPY --from=chromaprint_build-stage /build/chromaprint/usr/ /build/all//usr/
COPY --from=mp3gain_build-stage /build/mp3gain/usr/ /build/all//usr/
COPY --from=pip-stage /usr/lib/python3.6/site-packages /build/all/usr/lib/python3.6/site-packages

# install strip packages
RUN \
	set -ex \
	&& apk add --no-cache \
		bash \
		binutils

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# strip packages
RUN \
	set -ex \
	&& for dirs in usr/bin usr/lib usr/lib/python3.6/site-packages; \
	do \
		find /build/all/"${dirs}" -type f | \
		while read -r files ; do strip "${files}" || true \
		; done \
	; done

# remove unneeded files
RUN \	
	set -ex \
	&& for cleanfiles in *.la *.pyc *.pyo; \
	do \
	find /build/all/ -iname "${cleanfiles}" -exec rm -vf '{}' + \
	; done

FROM sparklyballs/alpine-test:${ALPINE_VER}

############## runtime stage ##############

# copy artifacts strip stage
COPY --from=strip-stage /build/all/usr/  /usr/

# install runtime packages
RUN \
	set -ex \
	&& apk add --no-cache \
		curl \
		ffmpeg \
		fftw \
		mpg123 \
		nano \
		jq \
		lame \
		nano \
		py3-beautifulsoup4 \
		py3-flask \
		py3-jellyfish \
		py3-munkres \
		py3-musicbrainzngs \
		py3-pillow \
		py3-pip \
		py3-pylast \
		py3-requests \
		py3-setuptools \
		py3-six \
		py-enum34 \
		python3 \
		sqlite-libs \
		tar \
		wget

# environment settings
ENV BEETSDIR="/config" \
EDITOR="nano" \
HOME="/config"

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 8337
VOLUME /config /downloads /music
