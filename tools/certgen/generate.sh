#!/bin/bash

# Run this before the first `docker compose build`: the certificates it generates
# are gitignored, so a fresh clone has none and the iris image build fails on its
# certs/ COPY without them.

echo "generating certificates/credentials..."

# Resolve paths from this script's own location rather than the caller's working
# directory. This script used to sit at the repository root and assumed it was run
# from there; now it lives in tools/certgen and is expected to work from anywhere.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)

curdir=$(pwd)
cd "$script_dir"

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

    dir=$script_dir/temp

    server_image_certs_dir=$repo_root/docker/certified-server/certs
    iris_image_certs_dir=$repo_root/docker/iris/certs

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


