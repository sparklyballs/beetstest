ARG ALPINE_VER="3.9"
FROM alpine:3.9 as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	set -ex \
	&& apk add --no-cache \
		curl \
		git \
		unzip

# fetch source
RUN \
	set -ex \
	&& mkdir -p \
		/tmp/beets-src \
		/tmp/mp3gain-src \
	&& curl -o \
	/tmp/beets.tar.gz -L \
	"https://github.com/sampsyo/beets/releases/download/v1.4.7/beets-1.4.7.tar.gz" \
	&& curl -o \
	/tmp/mp3gain.zip -L \
	"https://sourceforge.net/projects/mp3gain/files/mp3gain/1.6.2/mp3gain-1_6_2-src.zip" \
	&& tar xf \
	/tmp/beets.tar.gz -C \
	/tmp/beets-src --strip-components=1 \
	&& unzip -q /tmp/mp3gain.zip -d /tmp/mp3gain-src \
	&& git clone https://bitbucket.org/acoustid/chromaprint.git /tmp/chromaprint-src

FROM alpine:${ALPINE_VER} as beets_build-stage

############## beets build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/beets-src /tmp/beets-src

# set workdir
WORKDIR /tmp/beets-src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
		py2-setuptools \
		python2-dev

# build package
RUN \
	set -ex \
	&& python setup.py build \
	&& python setup.py install --prefix=/usr --root=/build/beets

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

FROM sparklyballs/alpine-test:${ALPINE_VER}

############## runtime stage ##############

# copy artifacts build stages
COPY --from=beets_build-stage /build/beets/usr/ /usr/
COPY --from=chromaprint_build-stage /build/chromaprint/usr/ /usr/
COPY --from=mp3gain_build-stage /build/mp3gain/usr/ /usr/

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache --virtual=build-dependencies \
		g++ \
		make \
		python2-dev \
	\
# install runtime packages
	\
	&& apk add --no-cache \
		curl \
		ffmpeg-libs \
		fftw \
		mpg123 \
		nano \
		jq \
		lame \
		py2-beautifulsoup4 \
		py2-flask \
		py2-jellyfish \
		py2-munkres \
		py2-musicbrainzngs \
		py2-pillow \
		py2-pip \
		py2-pylast \
		py2-requests \
		py2-setuptools \
		py2-six \
		py-enum34 \
		python2 \
		sqlite-libs \
		tar \
		wget \
	\
# install pip packages
	\
	&& pip install --no-cache-dir -U \
		beets-copyartifacts \
		discogs-client \
		mutagen \
		pyacoustid \
		pyyaml \
		unidecode \
	\
# cleanup
	\
	&& apk del --purge \
		build-dependencies \
	&& rm -rf \
		/root/.cache \
		/tmp/*

# environment settings
ENV BEETSDIR="/config" \
EDITOR="nano" \
HOME="/config"

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 8337
VOLUME /config /downloads /music
