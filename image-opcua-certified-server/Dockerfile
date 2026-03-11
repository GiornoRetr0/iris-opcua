FROM intersystemsdc/irisdemo-base-gcc:version-1.0.0 as gcc

# libmbedtls-dev/stable,now 2.16.0-1 amd64
RUN apt-get update -y && \
    apt-get install -y libmbedtls-dev

ADD ./cmakemod  /tmp/cmakemod/
ADD ./src       /tmp/src/

WORKDIR /tmp/src

RUN mkdir ./build && \
    cd ./build && \
    cmake ../ && \
    make



FROM library/ubuntu

WORKDIR /app

RUN apt-get update -y && \
    apt-get install -y libmbedtls-dev

COPY --from=gcc /tmp/src/build/secserver /app

ADD ./certs/secsvr.crt.der /app/certs/
ADD ./certs/secsvr.key.der /app/certs/
ADD ./certs/myCA.crt.der   /app/trustdir/
ADD ./certs/myCA.crl       /app/crldir/

ADD ./scripts /app/scripts

ENTRYPOINT [ "/app/scripts/run.bash" ]
