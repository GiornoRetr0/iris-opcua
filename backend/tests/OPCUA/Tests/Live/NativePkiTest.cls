Include %occInclude

/// Live tests of the connector's PKI and discovery bindings (OPCUA.Security.Native,
/// OPCUA.Client.GetEndpoints / SetServerPin) against the real native library.
/// Fixtures that need openssl are made here, in the test only, in a per-job temp dir.
Class OPCUA.Tests.Live.NativePkiTest Extends %UnitTest.TestCase
{

Property Dir As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
	set ..Skip = ""
	if '##class(OPCUA.Utils).SupportsPki() {
		set ..Skip = "connector 0.5 PKI is not available"
		Quit $$$OK
	}
	set ..Dir = ##class(%File).NormalizeDirectory("/tmp/opcua-pki-test-"_$job)
	do ##class(%File).RemoveDirectoryTree(..Dir)
	do ##class(%File).CreateDirectoryChain(..Dir)
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	if ..Dir '= "" do ##class(%File).RemoveDirectoryTree(..Dir)
	Quit $$$OK
}

/// True (and a skip is recorded) when the library is unusable.
Method Skipped() As %Boolean
{
	if ..Skip = "" Quit 0
	do $$$AssertSkipped(..Skip)
	Quit 1
}

Method Openssl(pArgs...) As %Integer
{
	set tRC = $ZF(-100, "/STDOUT=""/dev/null"" /STDERR=""/dev/null""", "openssl", pArgs...)
	Quit tRC
}

Method TestCreateInspect()
{
	Quit:..Skipped()
	set tCert = ..Dir_"c1.der", tKey = ..Dir_"k1.der"
	set tSC = ##class(OPCUA.Security.Native).CreateIdentity(tCert, tKey, "urn:test:opcua", "testhost", "Test Identity")
	do $$$AssertStatusOK(tSC, "create identity")
	Quit:$$$ISERR(tSC)
	set tSC = ##class(OPCUA.Security.Native).InspectCert(tCert, 1, .tInfo)
	do $$$AssertStatusOK(tSC, "inspect it")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tInfo.sanUris.%Get(0), "urn:test:opcua", "SAN URI")
	do $$$AssertEquals(tInfo.sanDns.%Get(0), "testhost", "SAN DNS")
	do $$$AssertEquals(tInfo.keyBits, 2048, "RSA 2048")
	do $$$AssertEquals(tInfo.selfSigned, 1, "self signed")
	do $$$AssertEquals(tInfo.isCA, 0, "not a CA")
	do $$$AssertEquals(tInfo.keyType, "RSA", "key type")
	do $$$AssertTrue(tInfo.sha256 [ ":", "fingerprint is AA:BB form")
	do $$$AssertTrue($length(tInfo.derHex) > 100, "DER hex returned")
	do $$$AssertTrue(tInfo.notAfter ] $zdatetime($horolog, 3), "valid into the future")

	// the same certificate inspected from its bytes
	set tSC = ##class(OPCUA.Security.Native).InspectCert(tInfo.derHex, 0, .tInfo2)
	do $$$AssertStatusOK(tSC, "inspect from hex")
	do $$$AssertEquals(tInfo2.sha256, tInfo.sha256, "same fingerprint from bytes")
}

Method TestPairMatch()
{
	Quit:..Skipped()
	set tCert = ..Dir_"c2.der", tKey = ..Dir_"k2.der"
	do $$$AssertStatusOK(##class(OPCUA.Security.Native).CreateIdentity(tCert, tKey, "urn:test:a", "a", "A"), "create")
	set tSC = ##class(OPCUA.Security.Native).CheckKeyPair(tCert, tKey, .tMatch)
	do $$$AssertStatusOK(tSC, "check")
	do $$$AssertEquals(tMatch, 1, "pair matches")
}

Method TestPairMismatch()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(##class(OPCUA.Security.Native).CreateIdentity(..Dir_"c3.der", ..Dir_"k3.der", "urn:test:a", "a", "A"), "create 1")
	do $$$AssertStatusOK(##class(OPCUA.Security.Native).CreateIdentity(..Dir_"c4.der", ..Dir_"k4.der", "urn:test:b", "b", "B"), "create 2")
	set tSC = ##class(OPCUA.Security.Native).CheckKeyPair(..Dir_"c3.der", ..Dir_"k4.der", .tMatch)
	do $$$AssertStatusOK(tSC, "check")
	do $$$AssertEquals(tMatch, 0, "mismatched pair is reported, not an error")
	set tSC = ##class(OPCUA.Security.Native).CheckKeyPair(..Dir_"nope.der", ..Dir_"k4.der", .tMatch)
	do $$$AssertTrue($$$ISERR(tSC), "an unreadable file is an error")
}

/// Make a PEM/DER/P12 fixture set from one openssl key and certificate.
Method TestImportPemDerP12()
{
	Quit:..Skipped()
	set d = ..Dir
	set tRC = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"f.key.pem", "-out", d_"f.crt.pem", "-days", "30", "-subj", "/CN=fixture")
	do $$$AssertEquals(tRC, 0, "openssl made a PEM pair")
	Quit:tRC
	do ..Openssl("x509", "-in", d_"f.crt.pem", "-outform", "DER", "-out", d_"f.crt.der")
	do ..Openssl("pkcs12", "-export", "-in", d_"f.crt.pem", "-inkey", d_"f.key.pem", "-out", d_"f.p12", "-passout", "pass:secret")
	do ..Openssl("pkcs8", "-topk8", "-in", d_"f.key.pem", "-out", d_"f.enc.pem", "-passout", "pass:secret", "-v2", "aes256")

	// PEM cert and PEM key
	set tSC = ##class(OPCUA.Security.Native).Normalise("cert", ..ReadHex(d_"f.crt.pem"), "", d_"o1.crt")
	do $$$AssertStatusOK(tSC, "normalise a PEM certificate")
	set tSC = ##class(OPCUA.Security.Native).Normalise("key", ..ReadHex(d_"f.key.pem"), "", d_"o1.key")
	do $$$AssertStatusOK(tSC, "normalise a PEM key")
	do ##class(OPCUA.Security.Native).CheckKeyPair(d_"o1.crt", d_"o1.key", .tMatch)
	do $$$AssertEquals(tMatch, 1, "PEM import gives a matching pair")

	// DER cert
	set tSC = ##class(OPCUA.Security.Native).Normalise("cert", ..ReadHex(d_"f.crt.der"), "", d_"o2.crt")
	do $$$AssertStatusOK(tSC, "normalise a DER certificate")

	// encrypted key, right password
	set tSC = ##class(OPCUA.Security.Native).Normalise("key", ..ReadHex(d_"f.enc.pem"), "secret", d_"o3.key")
	do $$$AssertStatusOK(tSC, "normalise an encrypted key with its password")

	// PKCS#12 gives both
	set tSC = ##class(OPCUA.Security.Native).Normalise("p12", ..ReadHex(d_"f.p12"), "secret", d_"o4.crt", d_"o4.key")
	do $$$AssertStatusOK(tSC, "normalise a PKCS#12 bundle")
	do ##class(OPCUA.Security.Native).CheckKeyPair(d_"o4.crt", d_"o4.key", .tMatch)
	do $$$AssertEquals(tMatch, 1, "PKCS#12 import gives a matching pair")

	// too big to pass through $ZF
	set tBig = $translate($justify("", 33000), " ", "0")
	set tSC = ##class(OPCUA.Security.Native).Normalise("p12", tBig, "x", d_"o5.crt", d_"o5.key")
	do $$$AssertTrue($$$ISERR(tSC), "an oversized payload is refused")
	do $$$AssertTrue($system.Status.GetErrorText(tSC) [ "too large to import (max 16 KB)", "with a clear message")
	do $$$AssertNotTrue(##class(%File).Exists(d_"o5.crt"), "and nothing is written")
}

Method TestImportWrongPassword()
{
	Quit:..Skipped()
	set d = ..Dir
	do ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"w.key.pem", "-out", d_"w.crt.pem", "-days", "30", "-subj", "/CN=wrong")
	do ..Openssl("pkcs12", "-export", "-in", d_"w.crt.pem", "-inkey", d_"w.key.pem", "-out", d_"w.p12", "-passout", "pass:right")
	do ..Openssl("pkcs8", "-topk8", "-in", d_"w.key.pem", "-out", d_"w.enc.pem", "-passout", "pass:right", "-v2", "aes256")
	// native errors are wrapped ("Application Error [9] : ...") and cut at 99 characters: contain, do not equal
	set tSC = ##class(OPCUA.Security.Native).Normalise("p12", ..ReadHex(d_"w.p12"), "bad", d_"own1.crt", d_"own1.key")
	do $$$AssertTrue($$$ISERR(tSC), "wrong PKCS#12 password fails")
	do $$$AssertTrue($system.Status.GetErrorText(tSC) [ "password", "and names the password")
	do $$$AssertNotTrue(##class(%File).Exists(d_"own1.crt"), "no certificate left behind")
	do $$$AssertNotTrue(##class(%File).Exists(d_"own1.key"), "no key left behind")

	set tSC = ##class(OPCUA.Security.Native).Normalise("key", ..ReadHex(d_"w.enc.pem"), "", d_"own2.key")
	do $$$AssertTrue($$$ISERR(tSC), "an encrypted key without its passphrase fails")
	do $$$AssertTrue($system.Status.GetErrorText(tSC) [ "password", "and names the password")
	do $$$AssertNotTrue(##class(%File).Exists(d_"own2.key"), "no key left behind")
}

Method TestExpiredFixtureInspect()
{
	Quit:..Skipped()
	set d = ..Dir
	// `openssl x509 -days` cannot go negative, so sign a past validity window with `openssl ca`.
	set tRC = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"e.key.pem", "-out", d_"e.crt.pem", "-days", "1", "-subj", "/CN=expired")
	do $$$AssertEquals(tRC, 0, "openssl made a certificate")
	Quit:tRC
	// Backdate with the `openssl ca` -startdate/-enddate options
	open d_"index.txt":"NWS":2
	close d_"index.txt"
	set tCnf = d_"ca.cnf"
	set f = ##class(%Stream.FileCharacter).%New()
	do f.LinkToFile(tCnf)
	do f.WriteLine("[ca]"), f.WriteLine("default_ca=x"), f.WriteLine("[x]")
	do f.WriteLine("database="_d_"index.txt"), f.WriteLine("new_certs_dir="_d), f.WriteLine("serial="_d_"serial")
	do f.WriteLine("default_md=sha256"), f.WriteLine("policy=p"), f.WriteLine("[p]"), f.WriteLine("commonName=supplied")
	do f.%Save()
	set s = ##class(%Stream.FileCharacter).%New()
	do s.LinkToFile(d_"serial"), s.WriteLine("01"), s.%Save()
	do ..Openssl("req", "-new", "-key", d_"e.key.pem", "-subj", "/CN=expired", "-out", d_"e.csr")
	set tRC = ..Openssl("ca", "-batch", "-config", tCnf, "-selfsign", "-keyfile", d_"e.key.pem", "-in", d_"e.csr", "-out", d_"e.old.pem", "-startdate", "20200101000000Z", "-enddate", "20200102000000Z", "-notext")
	do $$$AssertEquals(tRC, 0, "openssl made an expired certificate")
	Quit:tRC
	set tSC = ##class(OPCUA.Security.Native).InspectCert(d_"e.old.pem", 1, .tInfo)
	do $$$AssertStatusOK(tSC, "inspect an expired certificate")
	Quit:$$$ISERR(tSC)
	do $$$AssertTrue(tInfo.notAfter '= "", "has notAfter")
	do $$$AssertTrue($extract(tInfo.notAfter, 1, 10) < $zdate($horolog, 3), "notAfter is in the past: "_tInfo.notAfter)
}

Method TestGetEndpointsCertifiedServer()
{
	Quit:..Skipped()
	set tURL = "opc.tcp://certified-server:4840"
	set tClient = ##class(OPCUA.Client).%New()
	do $$$AssertTrue($isobject(tClient), "client created")
	Quit:'$isobject(tClient)
	set tSC = tClient.Initialize()
	if $$$ISOK(tSC) set tSC = tClient.SetupClient(3000, 1)
	if $$$ISOK(tSC) set tSC = tClient.GetEndpoints(tURL, .tEndpoints, .tCertHex, .tAppUri)
	if $$$ISERR(tSC) {
		do $$$AssertSkipped("certified-server unreachable: "_$system.Status.GetErrorText(tSC))
		Quit
	}
	set tMode3 = 0
	for i = 0:1:tEndpoints.%Size()-1 {
		set e = tEndpoints.%Get(i)
		if e.mode = 3 set tMode3 = 1
		do $$$AssertTrue(e.url [ "opc.tcp", "endpoint url present")
		do $$$AssertTrue(e.policyUri '= "", "policy present")
	}
	do $$$AssertTrue(tMode3, "an endpoint offers Sign & Encrypt (mode 3)")
	do $$$AssertTrue(tCertHex '= "", "server certificate returned")
	do $$$AssertTrue(tAppUri '= "", "application URI returned: "_tAppUri)
}

Method TestSetServerPinRejectsEmptyHost()
{
	Quit:..Skipped()
	set tClient = ##class(OPCUA.Client).%New()
	do tClient.Initialize()
	set tSC = tClient.SetServerPin($lb("AA:BB"), "")
	do $$$AssertTrue($$$ISERR(tSC), "an empty host is refused")
	do $$$AssertTrue($system.Status.GetErrorText(tSC) [ "host", "the error names the host")
}

/// Whole file as uppercase hex, as the native side expects.
ClassMethod ReadHex(pPath As %String) As %String
{
	set s = ##class(%Stream.FileBinary).%New()
	do s.LinkToFile(pPath)
	set tHex = ""
	while 's.AtEnd {
		set tChunk = s.Read(2000)
		for i = 1:1:$length(tChunk) set tHex = tHex_$zhex($ascii(tChunk, i)\16)_$zhex($ascii(tChunk, i)#16)
	}
	Quit tHex
}

}
