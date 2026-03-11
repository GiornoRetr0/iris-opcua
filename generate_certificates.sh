#!/bin/bash


echo "generating certificates/credentials..."

curdir=$(pwd)
cd certgen

bash certgen.bash
if [ "$?" -ne "0" ]; then

    set -e

    cd $curdir

    echo "unable to generate new certificates/credentials."
    exit 1

else

    set -e

    cd $curdir

    echo "finished generating certificates/credentials; copying results..."

    dir=certgen/temp

    server_image_certs_dir=image-opcua-certified-server/certs
    iris_image_certs_dir=image-iris/certs

    mkdir -p $server_image_certs_dir
    mkdir -p $iris_image_certs_dir

    svr=secsvr
    uac=secuac
    ca=myCA

    cp  $dir/$svr.crt.der   $server_image_certs_dir/$svr.crt.der
    cp  $dir/$svr.key.der   $server_image_certs_dir/$svr.key.der
    cp  $dir/$ca.crt.der    $server_image_certs_dir/$ca.crt.der
    cp  $dir/$ca.crl        $server_image_certs_dir/$ca.crl

    cp  $dir/$uac.crt.der   $iris_image_certs_dir/$uac.crt.der
    cp  $dir/$uac.key.der   $iris_image_certs_dir/$uac.key.der
    cp  $dir/$ca.crt.der    $iris_image_certs_dir/$ca.crt.der
    cp  $dir/$ca.crl        $iris_image_certs_dir/$ca.crl

    echo "done."
    exit 0

fi


