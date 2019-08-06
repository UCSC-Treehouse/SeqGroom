FROM ubuntu:14.04
MAINTAINER Jackie Roger

RUN apt-get update && apt-get install -y --force-yes --no-install-recommends \
    python \
    python-pip \
    python-dev \
    build-essential \
    zlib1g-dev \
    libcurl4-gnutls-dev \
    libssl-dev \
    pigz \
    libbz2-dev \
    liblzma-dev

WORKDIR /root
ADD https://github.com/samtools/samtools/releases/download/1.9/samtools-1.9.tar.bz2 /root
RUN tar xvf /root/samtools-1.9.tar.bz2
RUN make -C /root/samtools-1.9/htslib-1.9/

ADD ./scripts /root/scripts
ADD ./run.sh /root

WORKDIR /root/samtools-1.9
RUN ./configure --without-curses
RUN make
RUN make install

WORKDIR /data
ENTRYPOINT ["/root/run.sh"]