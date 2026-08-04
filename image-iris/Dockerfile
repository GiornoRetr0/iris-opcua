FROM intersystems/iris-community:2025.3

USER root
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libmbedtls-dev && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /usr/irissys/uac/certs/trustdir /usr/irissys/uac/certs/crldir && \
    mkdir -p /usr/irissys/mgr/opcua /usr/irissys/mgr/opcua/opcuaenstemp /usr/irissys/mgr/opcua/opcuasecondary && \
    chown -R 51773:51773 /usr/irissys/mgr/opcua

USER irisowner

# Source code
COPY --chown=irisowner:irisgroup src/ /opt/irisapp/src/

# C++ binaries, per architecture.
#
# TARGETARCH is supplied by BuildKit ("amd64" or "arm64"), so an Apple Silicon
# host gets the native arm64 libraries and an Intel host keeps the x86-64 ones.
# OPCUA.Utils looks the library up by name in the IRIS bin directory, so nothing
# in ObjectScript needs to know which architecture it is running on.
#
# Rebuild these with opc-ua-master/docker/Dockerfile.linux-arm64 (arm64) or the
# IrisOPCUA.mak lnxubuntux64 target (amd64).
ARG TARGETARCH
COPY --chown=irisowner:irisgroup uacbin/${TARGETARCH}/ /usr/irissys/bin/

# TLS certificates (readable by IRIS process)
COPY --chown=irisowner:irisgroup certs/secuac.crt.der /usr/irissys/uac/certs/
COPY --chown=irisowner:irisgroup certs/secuac.key.der /usr/irissys/uac/certs/
COPY --chown=irisowner:irisgroup certs/myCA.crt.der   /usr/irissys/uac/certs/trustdir/
COPY --chown=irisowner:irisgroup certs/myCA.crl       /usr/irissys/uac/certs/crldir/

# Install script (credentials + ObjectScript commands)
COPY --chown=irisowner:irisgroup iris-install.script /tmp/iris-install.script

# Start IRIS, run installer, stop IRIS
RUN iris start IRIS && \
    iris session IRIS -U %SYS < /tmp/iris-install.script && \
    iris stop IRIS quietly
