FROM intersystemsdc/irisdemo-base-irisint-community:version-1.6

# Name of the project folder ex.: my-atelier-project
ARG IRIS_PROJECT_FOLDER_NAME=src 

# Adding source code that will be loaded by the installer
ADD --chown=irisowner:irisuser ./${IRIS_PROJECT_FOLDER_NAME}/ $IRIS_APP_SOURCEDIR

ADD --chown=irisowner:irisuser ./uacbin /usr/irissys/bin/

ADD ./certs/secuac.crt.der /usr/irissys/uac/certs/
ADD ./certs/secuac.key.der /usr/irissys/uac/certs/
ADD ./certs/myCA.crt.der   /usr/irissys/uac/certs/trustdir/
ADD ./certs/myCA.crl       /usr/irissys/uac/certs/crldir/

# Running the installer. This will load the source from our project.
RUN /usr/irissys/demo/irisdemoinstaller.sh 

# libmbedtls-dev/stable,now 2.16.0-1 amd64 (omits libmbedcrypto3)
USER root
RUN apt-get update -y && \
    apt-get install -y libmbedtls-dev
