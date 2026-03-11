#!/bin/bash

DOCKER_REPO=intersystemsdc/irisdemo-demo-opcua
VERSION=`cat ./VERSION`

./generate_certificates.sh
if [ "$?" -eq "0" ]; then
    echo "proceeding with newly generated certficates/credentials..."
else 
    echo "skipping certificate/credential (re)generation..."
fi

set -e

# Building the OPCUA Certified Server Image
docker build -t ${DOCKER_REPO}:server-ctt-version-${VERSION} ./image-opcua-certified-server

# Building the IRIS Image
docker build -t ${DOCKER_REPO}:iris-version-${VERSION} ./image-iris

