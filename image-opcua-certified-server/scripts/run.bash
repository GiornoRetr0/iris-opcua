#!/bin/bash

projdir=/app
certname=secsvr

$projdir/secserver $projdir/certs/$certname.crt.der $projdir/certs/$certname.key.der \
--trustlistFolder $projdir/trustdir --revocationlistFolder $projdir/crldir 
