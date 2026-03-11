#!/bin/bash


tmpdir=temp
mkdir $tmpdir
if [ "$?" -ne "0" ]; then 
    echo "unable to make temporary directory..."
    echo "  $(pwd)/$tmpdir"
    exit 1
fi


set -e  # exit on error

touch $tmpdir/index.txt
mkdir $tmpdir/newcerts
echo "01" > $tmpdir/serial


ca=myCA
svr=secsvr
uac=secuac
dir=$tmpdir
cfgdir=.

echo "generating private key for ca (omitting password protection)..."
openssl genrsa -out $dir/$ca.key 2048

echo "generating private key for server..."
openssl genrsa -out $dir/$svr.key 2048

echo "converting server key to der format..."
openssl rsa -in $dir/$svr.key -outform DER -out $dir/$svr.key.der

echo "generating private key for client..."
openssl genrsa -out $dir/$uac.key 2048

echo "converting client key to der format..."
openssl rsa -in $dir/$uac.key -outform DER -out $dir/$uac.key.der



echo "generating root certificate..."
openssl req -x509 -new -nodes -key $dir/$ca.key -sha256 -days 36525 \
-out $dir/$ca.crt -config $cfgdir/$ca.config

#echo "displaying root certificate (using pem format source)..."
#openssl x509 -noout -text -inform PEM -in $dir/$ca.crt

echo "converting root certificate to der format..."
openssl x509 -in $dir/$ca.crt -out $dir/$ca.crt.der -outform DER 

#echo "displaying root certificate (using der format source)..."
#openssl x509 -noout -text -inform DER -in $dir/$ca.crt.der



echo "creating signing request for server..."
openssl req -new -key $dir/$svr.key -out $dir/$svr.csr -config $cfgdir/$svr.config \
-extensions req_ext

echo "creating server certificate..."
openssl ca -batch -config $cfgdir/$ca.config -in $dir/$svr.csr -keyfile $dir/$ca.key \
-cert $dir/$ca.crt -out $dir/$svr.crt -extfile $cfgdir/$svr.config -extensions x509_ext

#echo "displaying server certificate (using pem format source)..."
#openssl x509 -noout -text -inform PEM -in $dir/$svr.crt

echo "converting server certificate to der format..."
openssl x509 -in $dir/$svr.crt -out $dir/$svr.crt.der -outform DER 

#echo "displaying server certificate (using der format source)..."
#openssl x509 -noout -text -inform DER -in $dir/$svr.crt.der



echo "creating signing request for client..."
openssl req -new -key $dir/$uac.key -out $dir/$uac.csr -config $cfgdir/$uac.config \
-extensions req_ext

echo "creating client certificate..."
openssl ca -batch -config $cfgdir/$ca.config -in $dir/$uac.csr -keyfile $dir/$ca.key \
-cert $dir/$ca.crt -out $dir/$uac.crt -extfile $cfgdir/$uac.config -extensions x509_ext

#echo "displaying client certificate (using pem format source)..."
#openssl x509 -noout -text -inform PEM -in $dir/$uac.crt

echo "converting client certificate to der format"
openssl x509 -in $dir/$uac.crt -out $dir/$uac.crt.der -outform DER 

#echo "displaying client certificate (using der format source)..."
#openssl x509 -noout -text -inform DER -in $dir/$uac.crt.der



echo "generating CRL..."
openssl ca -gencrl -config $cfgdir/$ca.config -keyfile $dir/$ca.key -keyform PEM \
-cert $dir/$ca.crt -out $dir/$ca.crl.pem

#echo "displaying CRL (using pem format source)..."
#openssl crl -inform PEM -in $dir/$ca.crl.pem -noout -text

echo "converting CRL to der format..."
openssl crl -inform PEM -in $dir/$ca.crl.pem -outform DER -out $dir/$ca.crl

#echo "displaying CRL (using der format source)..."
#openssl crl -inform DER -in $dir/$ca.crl -noout -text



echo "certificate generation complete, no errors"
exit 0
