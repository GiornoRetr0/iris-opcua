FROM ubuntu:22.04 AS gcc

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential cmake libmbedtls-dev && \
    rm -rf /var/lib/apt/lists/*

ADD ./cmakemod  /tmp/cmakemod/
ADD ./src       /tmp/src/

WORKDIR /tmp/src

RUN mkdir ./build && \
    cd ./build && \
    cmake -DCMAKE_C_FLAGS="-fcommon" ../ && \
    make


FROM ubuntu:22.04

WORKDIR /app

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libmbedtls14 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=gcc /tmp/src/build/secserver /app

ADD ./certs/secsvr.crt.der /app/certs/
ADD ./certs/secsvr.key.der /app/certs/
ADD ./certs/myCA.crt.der   /app/trustdir/
ADD ./certs/myCA.crl       /app/crldir/

ADD ./scripts /app/scripts
RUN chmod +x /app/scripts/run.bash

ENTRYPOINT [ "/app/scripts/run.bash" ]
