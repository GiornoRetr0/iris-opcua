Include %occInclude

/// Live tests of the client identity lifecycle (OPCUA.Security.Identity) with the real
/// native library. The store is redirected with ^%OPCUA.Security.Override (root and
/// global), so the real identity is never touched; both are removed afterwards.
/// Fixtures that need openssl are made here, in the test only.
Class OPCUA.Tests.Live.SecurityIdentityLiveTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.IdentityImpactProduction";

Property Base As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
	set ..Skip = ""
	if '##class(OPCUA.Utils).SupportsPki() {
		set ..Skip = "connector 0.5 PKI is not available"
		Quit $$$OK
	}
	set ..Base = ##class(%File).NormalizeDirectory("/tmp/opcua-identity-live-"_$job)
	do ##class(%File).RemoveDirectoryTree(..Base)
	do ##class(%File).CreateDirectoryChain(..Base_"fx")
	set ^%OPCUA.Security.Override("root") = ..Base_"store"
	set ^%OPCUA.Security.Override("global") = "^OPCUA.Tests.IdentityLive"
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	kill ^%OPCUA.Security.Override
	kill ^OPCUA.Tests.IdentityLive
	if ..Base '= "" do ##class(%File).RemoveDirectoryTree(..Base)
	do ..DropProduction()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	Quit:..Skip'="" $$$OK
	kill ^OPCUA.Tests.IdentityLive
	do ##class(%File).RemoveDirectoryTree(..Base_"store")
	Quit $$$OK
}

Method Skipped() As %Boolean
{
	if ..Skip = "" Quit 0
	do $$$AssertSkipped(..Skip)
	Quit 1
}

Method Openssl(pArgs...) As %Integer
{
	Quit $ZF(-100, "/STDOUT=""/dev/null"" /STDERR=""/dev/null""", "openssl", pArgs...)
}

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

/// A good DER pair in fx/<name>.crt / .key; returns the cert path via .pCert.
Method MakePair(pName As %String, pURI As %String = "urn:fx:opcua") As %Status
{
	set d = ..Base_"fx/"
	Quit ##class(OPCUA.Security.Native).CreateIdentity(d_pName_".crt", d_pName_".key", pURI, "fxhost", "Fixture "_pName)
}

ClassMethod ReadRaw(pPath As %String) As %String
{
	set s = ##class(%Stream.FileBinary).%New()
	do s.LinkToFile(pPath)
	Quit s.Read(100000)
}

Method Fp(pPath As %String) As %String
{
	do ##class(OPCUA.Security.Native).InspectCert(pPath, 1, .i)
	Quit i.sha256
}

Method OwnFiles() As %Integer
{
	set tDir = ##class(OPCUA.Security.Store).Dir("own")
	set n = 0, rs = ##class(%ResultSet).%New("%File:FileSet")
	do rs.Execute(tDir, "*")
	while rs.Next() { set:rs.Get("Type")="F" n = n + 1 }
	Quit n
}

Method TestCreateThenReuse()
{
	Quit:..Skipped()
	set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tStatus)
	do $$$AssertStatusOK(tSC, "create")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tStatus.ready, 1, "ready")
	do $$$AssertEquals(tStatus.source, "generated", "source")
	do $$$AssertEquals(tStatus.clientURI, ##class(OPCUA.Security.Store).DefaultClientURI(), "default URI")
	do $$$AssertTrue(tStatus.subject [ "IRIS OPC UA Client (", "common name")
	do $$$AssertTrue(tStatus.daysLeft > 3600, "about ten years")
	set tFp = tStatus.fingerprint
	set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tStatus2)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "second create without replace is a 409")
	do ##class(OPCUA.Security.Identity).Status(.tStatus3)
	do $$$AssertEquals(tStatus3.fingerprint, tFp, "fingerprint unchanged")
	do $$$AssertEquals(tStatus3.candidates.%Size(), 0, "no candidates once configured")
	set tSC = ##class(OPCUA.Security.Identity).Active(.tCert, .tKey, .tURI)
	do $$$AssertStatusOK(tSC, "active")
	do $$$AssertTrue(##class(%File).Exists(tCert), "cert exists")
	do $$$AssertTrue(##class(%File).Exists(tKey), "key exists")
	do $$$AssertEquals(tURI, tStatus.clientURI, "uri")
	set tJson = tStatus3.%ToJSON()
	do $$$AssertNotTrue(tJson [ "PRIVATE KEY", "status has no PEM key text")
	set tBytes = ..ReadRaw(tKey), tHex = ..ReadHex(tKey)
	do $$$AssertTrue($length(tHex) > 600, "read the key file")
	do $$$AssertNotTrue(tJson [ $zconvert(tHex, "U"), "no key hex (upper)")
	do $$$AssertNotTrue(tJson [ $zconvert(tHex, "L"), "no key hex (lower)")
	do $$$AssertNotTrue(tJson [ $system.Encryption.Base64Encode(tBytes, 1), "no key base64")
	do $$$AssertNotTrue(tJson [ $extract($zconvert(tHex, "U"), 41, 120), "no fragment of the key hex")
	do $$$AssertEquals(..OwnFiles(), 2, "two files in own/")
	// the certificate download
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).CertificateBytes("der", .tDer, .tName), "der")
	do $$$AssertEquals(tName, "iris-opcua-client.der", "der name")
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).CertificateBytes("pem", .tPem, .tName2), "pem")
	do $$$AssertEquals(tName2, "iris-opcua-client.pem", "pem name")
	do $$$AssertTrue(tPem [ "-----BEGIN CERTIFICATE-----", "pem header")
	do $$$AssertNotTrue(tPem [ "PRIVATE", "pem has no key")
}

Method TestImportPair()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(..MakePair("p1"), "fixture")
	set d = ..Base_"fx/"
	set tSC = ##class(OPCUA.Security.Identity).Import(..ReadHex(d_"p1.crt"), ..ReadHex(d_"p1.key"), "", "", 0, "", .tStatus)
	do $$$AssertStatusOK(tSC, "import")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tStatus.source, "imported", "source")
	do $$$AssertEquals(tStatus.ready, 1, "ready")
	do $$$AssertEquals(tStatus.clientURI, "urn:fx:opcua", "URI from SAN")
	do $$$AssertEquals(tStatus.fingerprint, ..Fp(d_"p1.crt"), "fingerprint")
	do $$$AssertEquals(..OwnFiles(), 2, "copied into own/")
	// both forms at once, or neither, is a 400
	set tSC = ##class(OPCUA.Security.Identity).Import("", "", "", "", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "nothing given")
}

Method TestImportP12()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(..MakePair("p2"), "fixture")
	set d = ..Base_"fx/"
	do ..Openssl("x509", "-inform", "DER", "-in", d_"p2.crt", "-out", d_"p2.pem")
	do ..Openssl("pkey", "-inform", "DER", "-in", d_"p2.key", "-out", d_"p2.key.pem")
	set tRC = ..Openssl("pkcs12", "-export", "-in", d_"p2.pem", "-inkey", d_"p2.key.pem", "-out", d_"p2.p12", "-passout", "pass:pw1")
	do $$$AssertEquals(tRC, 0, "p12 fixture")
	set tSC = ##class(OPCUA.Security.Identity).Import("", "", ..ReadHex(d_"p2.p12"), "wrong", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "wrong password is a 400")
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), "The password for the key or PKCS#12 file is wrong or missing.", "clear text")
	do $$$AssertEquals(..OwnFiles(), 0, "nothing left in own/")
	set tSC = ##class(OPCUA.Security.Identity).Import("", "", ..ReadHex(d_"p2.p12"), "pw1", 0, "", .tStatus)
	do $$$AssertStatusOK(tSC, "import p12")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tStatus.ready, 1, "ready")
	do $$$AssertEquals(tStatus.clientURI, "urn:fx:opcua", "URI")
}

Method TestImportMismatchRejected()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(..MakePair("m1", "urn:fx:m1"), "fixture 1")
	do $$$AssertStatusOK(..MakePair("m2", "urn:fx:m2"), "fixture 2")
	set d = ..Base_"fx/"
	set tSC = ##class(OPCUA.Security.Identity).Import(..ReadHex(d_"m1.crt"), ..ReadHex(d_"m2.key"), "", "", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "does not belong", "message")
	do $$$AssertEquals(..OwnFiles(), 0, "nothing in own/")
	do $$$AssertNotTrue(##class(OPCUA.Security.Store).GetIdentity(.c), "nothing configured")
}

Method TestImportExpiredRejected()
{
	Quit:..Skipped()
	set d = ..Base_"fx/"
	do ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"e.key.pem", "-out", d_"e.crt.pem", "-days", "1", "-subj", "/CN=expired")
	open d_"index.txt":"NWS":2
	close d_"index.txt"
	set f = ##class(%Stream.FileCharacter).%New()
	do f.LinkToFile(d_"ca.cnf")
	do f.WriteLine("[ca]"), f.WriteLine("default_ca=x"), f.WriteLine("[x]")
	do f.WriteLine("database="_d_"index.txt"), f.WriteLine("new_certs_dir="_d), f.WriteLine("serial="_d_"serial")
	do f.WriteLine("default_md=sha256"), f.WriteLine("policy=p"), f.WriteLine("[p]"), f.WriteLine("commonName=supplied")
	do f.%Save()
	set s = ##class(%Stream.FileCharacter).%New()
	do s.LinkToFile(d_"serial"), s.WriteLine("01"), s.%Save()
	do ..Openssl("req", "-new", "-key", d_"e.key.pem", "-subj", "/CN=expired", "-out", d_"e.csr")
	set tRC = ..Openssl("ca", "-batch", "-config", d_"ca.cnf", "-selfsign", "-keyfile", d_"e.key.pem", "-in", d_"e.csr", "-out", d_"e.old.pem", "-startdate", "20200101000000Z", "-enddate", "20200102000000Z", "-notext")
	do $$$AssertEquals(tRC, 0, "expired fixture")
	Quit:tRC
	set tSC = ##class(OPCUA.Security.Identity).Import(..ReadHex(d_"e.old.pem"), ..ReadHex(d_"e.key.pem"), "", "", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "expired", "says expired: "_##class(OPCUA.REST.Error).Message(tSC))
	do $$$AssertEquals(..OwnFiles(), 0, "nothing in own/")
}

Method TestImportNoSanUriRejected()
{
	Quit:..Skipped()
	set d = ..Base_"fx/"
	set tRC = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"n.key.pem", "-out", d_"n.crt.pem", "-days", "30", "-subj", "/CN=nosan")
	do $$$AssertEquals(tRC, 0, "fixture")
	Quit:tRC
	set tSC = ##class(OPCUA.Security.Identity).Import(..ReadHex(d_"n.crt.pem"), ..ReadHex(d_"n.key.pem"), "", "", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "URI", "names the URI: "_##class(OPCUA.REST.Error).Message(tSC))
	do $$$AssertEquals(..OwnFiles(), 0, "nothing in own/")
}

Method TestUseFilesDemoSecuac()
{
	Quit:..Skipped()
	set tCert = "/usr/irissys/uac/certs/secuac.crt.der", tKey = "/usr/irissys/uac/certs/secuac.key.der"
	if '##class(%File).Exists(tCert) || '##class(%File).Exists(tKey) {
		do $$$AssertSkipped("demo secuac files not present")
		Quit
	}
	do ##class(OPCUA.Security.Identity).Status(.tBefore)
	do $$$AssertEquals(tBefore.configured, 0, "not configured")
	do $$$AssertEquals(tBefore.candidates.%Size(), 1, "one candidate")
	do $$$AssertEquals(tBefore.candidates.%Get(0).certPath, tCert, "candidate cert path")
	do $$$AssertEquals(tBefore.candidates.%Get(0).clientURI, "urn:secuac", "candidate URI")
	do $$$AssertEquals(tBefore.candidates.%Get(0).ready, 1, "candidate ready")
	do $$$AssertEquals($listlength($listfromstring(tBefore.candidates.%Get(0).%ToJSON(), ",")) > 0, 1, "json")
	set tSC = ##class(OPCUA.Security.Identity).UseFiles(tCert, tKey, 0, "", .tStatus)
	do $$$AssertStatusOK(tSC, "use files")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tStatus.ready, 1, "ready")
	do $$$AssertEquals(tStatus.clientURI, "urn:secuac", "URI")
	do $$$AssertEquals(tStatus.source, "files", "source")
	do $$$AssertEquals(..OwnFiles(), 0, "referenced in place, nothing copied")
	do $$$AssertEquals(tStatus.advanced.certPath, tCert, "path")
}

Method TestUseFilesThenDeleted()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(..MakePair("u1"), "fixture")
	set d = ..Base_"fx/"
	set tSC = ##class(OPCUA.Security.Identity).UseFiles(d_"u1.crt", d_"u1.key", 0, "", .tStatus)
	do $$$AssertStatusOK(tSC, "use files")
	Quit:$$$ISERR(tSC)
	do $$$AssertEquals(tStatus.ready, 1, "ready")
	set tFp = tStatus.fingerprint
	do ##class(%File).Delete(d_"u1.key")
	do ##class(OPCUA.Security.Identity).Status(.tAfter)
	do $$$AssertEquals(tAfter.ready, 0, "not ready")
	do $$$AssertEquals(tAfter.errors.%Get(0).code, "unreadable", "unreadable")
	do $$$AssertEquals(tAfter.fingerprint, tFp, "fingerprint still known")
	set tSC = ##class(OPCUA.Security.Identity).Active(.c, .k, .u)
	do $$$AssertTrue($$$ISERR(tSC), "Active refuses")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "The IRIS client identity is not usable: ", "message")
	// replaced with an unrelated key: mismatch
	do $$$AssertStatusOK(..MakePair("u2", "urn:fx:u2"), "second fixture")
	do ##class(%File).CopyFile(d_"u2.key", d_"u1.key")
	do ##class(OPCUA.Security.Identity).Status(.tMis)
	do $$$AssertEquals(tMis.ready, 0, "not ready")
	do $$$AssertEquals(tMis.errors.%Get(0).code, "keyMismatch", "keyMismatch")
}

Method TestUseFilesPemRejected()
{
	Quit:..Skipped()
	set d = ..Base_"fx/"
	set tRC = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"x.key.pem", "-out", d_"x.crt.pem", "-days", "30", "-subj", "/CN=pem", "-addext", "subjectAltName=URI:urn:fx:pem")
	do $$$AssertEquals(tRC, 0, "PEM fixture")
	Quit:tRC
	set tExpect = "Use DER files for the certificate and key (IRIS's OPC UA library reads DER only). "_$char(8220)_"Use existing certificate"_$char(8221)_" converts PEM and .pfx for you."
	set tSC = ##class(OPCUA.Security.Identity).UseFiles(d_"x.crt.pem", d_"x.key.pem", 0, "", .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), tExpect, "text")
	do $$$AssertNotTrue(##class(OPCUA.Security.Store).GetIdentity(.c), "nothing configured")
	// with an identity in place it stays as it was
	do $$$AssertStatusOK(..MakePair("x2"), "DER fixture")
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).UseFiles(d_"x2.crt", d_"x2.key", 0, "", .tOne), "use DER")
	set tSC = ##class(OPCUA.Security.Identity).UseFiles(d_"x.crt.pem", d_"x.key.pem", 1, tOne.fingerprint, .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), tExpect, "text on replace")
	do ##class(OPCUA.Security.Identity).Status(.tAfter)
	do $$$AssertEquals(tAfter.fingerprint, tOne.fingerprint, "identity unchanged")
	do $$$AssertEquals(tAfter.ready, 1, "still ready")
}

Method TestUseFilesManagedRejected()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).Create("", 0, "", .tOne), "create")
	do ##class(OPCUA.Security.Identity).Status(.tS1)
	set tCert = tS1.advanced.certPath, tKey = tS1.advanced.keyPath
	set tSC = ##class(OPCUA.Security.Identity).UseFiles(tCert, tKey, 1, tOne.fingerprint, .tS)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), "These files are already managed by IRIS.", "text")
	do ##class(OPCUA.Security.Identity).Status(.tAfter)
	do $$$AssertEquals(tAfter.ready, 1, "identity still ready")
	do $$$AssertEquals(tAfter.fingerprint, tOne.fingerprint, "unchanged")
	do $$$AssertEquals(..OwnFiles(), 2, "files still in own/")
}

Method TestSaveFailureLeavesNothingHalfSwapped()
{
	Quit:..Skipped()
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).Create("", 0, "", .tOne), "create")
	set tCfgBefore = ^OPCUA.Tests.IdentityLive("identity")
	set ^%OPCUA.Security.Override("failSave") = 1
	set tSC = ##class(OPCUA.Security.Identity).Create("", 1, tOne.fingerprint, .tTwo)
	kill ^%OPCUA.Security.Override("failSave")
	do $$$AssertTrue($$$ISERR(tSC), "the replacement fails")
	do $$$AssertEquals(^OPCUA.Tests.IdentityLive("identity"), tCfgBefore, "config unchanged")
	do $$$AssertEquals(..OwnFiles(), 2, "own/ holds the original pair")
	do ##class(OPCUA.Security.Identity).Status(.tAfter)
	do $$$AssertEquals(tAfter.ready, 1, "still ready")
	do $$$AssertEquals(tAfter.fingerprint, tOne.fingerprint, "same certificate")
	set tPrev = ##class(OPCUA.Security.Store).Dir("previous")
	set rs = ##class(%ResultSet).%New("%File:FileSet")
	do rs.Execute(tPrev, "*")
	set n = 0
	while rs.Next() { set n = n + 1 }
	do $$$AssertEquals(n, 0, "no previous/ entry left")
	// and the staging area is gone
	set rs = ##class(%ResultSet).%New("%File:FileSet")
	do rs.Execute(##class(OPCUA.Security.Store).Root()_"staging", "*")
	set n = 0
	while rs.Next() { set n = n + 1 }
	do $$$AssertEquals(n, 0, "no staging left")
}

Method TestReplaceKeepsPrevious()
{
	Quit:..Skipped()
	set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tOne)
	do $$$AssertStatusOK(tSC, "first")
	Quit:$$$ISERR(tSC)
	set tSC = ##class(OPCUA.Security.Identity).Create("", 1, "WRONG", .tX)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "stale fingerprint")
	do $$$AssertEquals(..OwnFiles(), 2, "own/ untouched")
	set tSC = ##class(OPCUA.Security.Identity).Create("", 1, tOne.fingerprint, .tTwo)
	do $$$AssertStatusOK(tSC, "replace")
	Quit:$$$ISERR(tSC)
	do $$$AssertTrue(tTwo.fingerprint '= tOne.fingerprint, "new certificate")
	do $$$AssertEquals(tTwo.clientURI, tOne.clientURI, "URI kept when none given")
	do $$$AssertEquals(tTwo.ready, 1, "ready")
	do $$$AssertEquals(..OwnFiles(), 2, "own/ holds only the new pair")
	// the previous pair is in previous/<timestamp>/
	set tPrev = ##class(OPCUA.Security.Store).Dir("previous")
	set rs = ##class(%ResultSet).%New("%File:FileSet")
	do rs.Execute(tPrev, "*")
	set tDirs = 0, tFound = 0
	while rs.Next() {
		if rs.Get("Type") = "D" {
			set tDirs = tDirs + 1
			set r2 = ##class(%ResultSet).%New("%File:FileSet")
			do r2.Execute(rs.Get("Name"), "*")
			while r2.Next() {
				if r2.Get("Type") = "F", ..Fp2(r2.Get("Name")) = tOne.fingerprint set tFound = 1
			}
		}
	}
	do $$$AssertEquals(tDirs, 1, "one previous/ entry")
	do $$$AssertEquals(tFound, 1, "the old certificate is in it")
	// replacing with a new explicit URI
	set tSC = ##class(OPCUA.Security.Identity).Create("urn:other:uri", 1, tTwo.fingerprint, .tThree)
	do $$$AssertStatusOK(tSC, "replace with URI")
	do $$$AssertEquals(tThree.clientURI, "urn:other:uri", "explicit URI wins")
	set tSC = ##class(OPCUA.Security.Identity).Create("Not A URI", 1, tThree.fingerprint, .tBad)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "invalid URI is 400")
}

Method Fp2(pPath As %String) As %String
{
	set tSC = ##class(OPCUA.Security.Native).InspectCert(pPath, 1, .i)
	Quit:$$$ISERR(tSC) ""
	Quit i.sha256
}

Method TestImpactListsManagedPipeline()
{
	Quit:..Skipped()
	do ..DropProduction()
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	set tItem = "<Item Name=""TmpManaged"" ClassName=""OPCUA.Service.TCPPollingRowSourceService"" Enabled=""false""><Setting Target=""Adapter"" Name=""SecurityMode"">3</Setting><Setting Target=""Adapter"" Name=""URL"">opc.tcp://managed-host:4840</Setting></Item>"
	set tItem = tItem_"<Item Name=""TmpManual"" ClassName=""OPCUA.Service.TCPPollingRowSourceService"" Enabled=""false""><Setting Target=""Adapter"" Name=""SecurityMode"">3</Setting><Setting Target=""Adapter"" Name=""PublicCertificate"">/x/c.der</Setting><Setting Target=""Adapter"" Name=""PrivateKey"">/x/k.der</Setting></Item>"
	set tItem = tItem_"<Item Name=""TmpNone"" ClassName=""OPCUA.Service.TCPPollingRowSourceService"" Enabled=""false""><Setting Target=""Adapter"" Name=""SecurityMode"">1</Setting></Item>"
	do tX.Data.Write("<Production Name="""_..#Production_""">"_tItem_"</Production>")
	do tDef.XDatas.Insert(tX)
	do $$$AssertStatusOK(tDef.%Save(), "save production")
	do $$$AssertStatusOK($System.OBJ.Compile(..#Production, "ck-d"), "compile")
	do $$$AssertStatusOK(##class(Ens.Config.Production).LoadFromClass(..#Production), "load")
	set tKey = ##class(OPCUA.Security.Store).ServerKey("opc.tcp://managed-host:4840")
	do $$$AssertStatusOK(##class(OPCUA.Security.Store).SaveServer(tKey, {"key": (tKey), "url": "opc.tcp://managed-host:4840", "label": "Managed host"}), "server")
	set tSC = ##class(OPCUA.Security.Identity).Impact(.tImpact)
	do $$$AssertStatusOK(tSC, "impact")
	set tNames = ",", tIt = tImpact.pipelines.%GetIterator()
	while tIt.%GetNext(.k, .v) {
		set tNames = tNames_v.name_","
		if v.name = "TmpManaged" {
			do $$$AssertEquals(v.namespace, $namespace, "namespace")
			do $$$AssertEquals(v.url, "opc.tcp://managed-host:4840", "url")
		}
	}
	do $$$AssertTrue(tNames [ ",TmpManaged,", "managed pipeline listed")
	do $$$AssertNotTrue(tNames [ ",TmpManual,", "manual paths: not listed")
	do $$$AssertNotTrue(tNames [ ",TmpNone,", "mode 1: not listed")
	do $$$AssertEquals(tImpact.servers.%Size(), 1, "one trusted server")
	do $$$AssertEquals(tImpact.servers.%Get(0).key, tKey, "server key")
	do $$$AssertEquals(tImpact.servers.%Get(0).label, "Managed host", "server label")
	do $$$AssertEquals($namespace, "OPCUA", "namespace restored")
	do ..DropProduction()
}

ClassMethod DropProduction()
{
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
}

}
