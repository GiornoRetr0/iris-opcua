Include %occInclude

/// Live tests of OPCUA.Security.Trust against the demo certified-server (certificate
/// issued by myCA; discovery reports applicationUri urn:certified-server). The store is
/// redirected to a throwaway global and directory. The public demo certificates
/// (secsvr.crt.der, myCA.crt.der, myCA.crl) are copied into the container by
/// demo/iris/dev-load.sh to /tmp/opcua-dev/fixtures/certified-server/; tests that need
/// them record a skip when they are absent (run demo/certgen/generate.sh first).
Class OPCUA.Tests.Live.SecurityTrustLiveTest Extends %UnitTest.TestCase
{

Parameter URL = "opc.tcp://certified-server:4840";

Property Root As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..Skip = ""
    If '##class(OPCUA.Utils).SupportsPki() Set ..Skip = "connector 0.5 PKI is not available" Quit $$$OK
    Set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-trust-live-"_$Job)
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityTrustLive
    Set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityTrustLive"
    Set ^%OPCUA.Security.Override("root") = ..Root
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityTrustLive
    If ..Root '= "" Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ^%OPCUA.SecurityTrustLive
    If ..Root '= "" Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

ClassMethod Fx() As %String
{
    Quit "/tmp/opcua-dev/fixtures/certified-server/"
}

/// True when the demo public certificates are present; else records a skip.
Method HaveFixtures() As %Boolean
{
    If ##class(%File).Exists(..Fx()_"myCA.crt.der") && ##class(%File).Exists(..Fx()_"myCA.crl") && ##class(%File).Exists(..Fx()_"secsvr.crt.der") Quit 1
    Do $$$AssertSkipped("demo certificates not in "_..Fx()_" (run demo/certgen/generate.sh, then dev-load.sh)")
    Quit 0
}

Method Skipped() As %Boolean
{
    If ..Skip = "" Quit 0
    Do $$$AssertSkipped(..Skip)
    Quit 1
}

/// Inspect, or record a skip when the server cannot be reached.
Method Fetch(Output pResult As %DynamicObject) As %Boolean
{
    Set tSC = ##class(OPCUA.Security.Trust).Inspect(..#URL, .pResult)
    If $$$ISERR(tSC) {
        Do $$$AssertSkipped("certified-server unreachable: "_$System.Status.GetErrorText(tSC))
        Quit 0
    }
    Quit 1
}

ClassMethod Hex(pPath As %String) As %String
{
    Set s = ##class(%Stream.FileBinary).%New()
    Do s.LinkToFile(pPath)
    Set tHex = ""
    While 's.AtEnd {
        Set c = s.Read(2000)
        For i = 1:1:$Length(c) Set tHex = tHex_$ZHex($Ascii(c, i)\16)_$ZHex($Ascii(c, i)#16)
    }
    Quit tHex
}

Method CountFiles(pDir As %String) As %Integer
{
    Set n = 0
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(pDir)
    While rs.Next() { If rs.Get("Type") '= "D" Set n = n + 1 }
    Quit n
}

Method TrustDirCount() As %Integer
{
    Quit ..CountFiles(##class(OPCUA.Security.Store).ServerDir(##class(OPCUA.Security.Store).ServerKey(..#URL), "trusted"))
}

Method TestInspectCaSigned()
{
    Quit:..Skipped()
    Quit:'..Fetch(.r)
    Do $$$AssertEquals(r.offersSignAndEncrypt, 1, "offers Sign & Encrypt")
    Do $$$AssertEquals(r.applicationUri, "urn:certified-server", "application URI")
    Do $$$AssertEquals(r.certificate.selfSigned, 0, "CA-signed")
    Do $$$AssertEquals(r.needsIssuer, 1, "needs the issuer")
    Do $$$AssertTrue(r.issuerName [ "myCA", "issuer is myCA: "_r.issuerName)
    Do $$$AssertEquals(r.trusted, 0, "not trusted yet")
    Do $$$AssertEquals(r.identity.uriMatches, 1, "SAN URI matches")
    Do $$$AssertEquals(r.identity.hostMatches, 1, "host matches")
    Do $$$AssertEquals(r.identity.problems.%Size(), 0, "no identity problems")
    Set f = ..Fx()_"secsvr.crt.der"
    If ##class(%File).Exists(f) {
        Set tSC = ##class(OPCUA.Security.Native).InspectCert(f, 1, .ref)
        Do $$$AssertStatusOK(tSC, "fixture readable")
        If $$$ISOK(tSC) Do $$$AssertEquals(r.certificate.sha256, ref.sha256, "fingerprint equals the fixture's")
    } Else {
        Do $$$AssertSkipped("fixture "_f_" not copied into the container")
    }
}

Method TestTrustWrongFingerprint()
{
    Quit:..Skipped()
    Quit:'..Fetch(.r)
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, "00:11:22", "x", .res)
    Do $$$AssertTrue($$$ISERR(tSC), "wrong fingerprint refused")
    Do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "409")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "The server presented a different certificate than the one you reviewed. Review it again.", "message")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).GetServer(##class(OPCUA.Security.Store).ServerKey(..#URL), .e), 0, "no entry")
    Do $$$AssertEquals(..TrustDirCount(), 0, "no files")
}

Method TestTrustThenIssuer()
{
    Quit:..Skipped()
    Quit:'..HaveFixtures()
    Quit:'..Fetch(.r)
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, r.certificate.sha256, "Demo", .res)
    Do $$$AssertStatusOK(tSC, "trust")
    Quit:$$$ISERR(tSC)
    Do $$$AssertEquals(res.trusted, 1, "result says trusted")
    Do $$$AssertEquals(res.pinnedFingerprint, r.certificate.sha256, "pin recorded")
    Set tSC = ##class(OPCUA.Security.Trust).Pin(..#URL, .fps, .td, .cd, .h)
    Do $$$AssertTrue($$$ISERR(tSC), "Pin refuses until the issuer is added")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "was issued by", "needs-issuer message")
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), ..Hex(..Fx()_"myCA.crl"), .res2)
    Do $$$AssertStatusOK(tSC, "add issuer")
    Quit:$$$ISERR(tSC)
    Set tSC = ##class(OPCUA.Security.Trust).Pin(..#URL, .fps, .td, .cd, .h)
    Do $$$AssertStatusOK(tSC, "Pin now works")
    Do $$$AssertEquals($ListLength(fps), 1, "one fingerprint")
    Do $$$AssertEquals($ListGet(fps, 1), r.certificate.sha256, "the pinned one")
    Do $$$AssertEquals(h, "certified-server", "host")
    Do $$$AssertEquals(..CountFiles(td), 2, "trust dir has the server certificate and the CA")
    Do $$$AssertEquals(..CountFiles(cd), 1, "crl dir has the CRL")
    Set tSC = ##class(OPCUA.Security.Trust).List(.l)
    Do $$$AssertEquals(l.%Size(), 1, "listed")
    Set e = l.%Get(0)
    Do $$$AssertEquals(e.label, "Demo", "label")
    Do $$$AssertEquals(e.hasIssuer, 1, "hasIssuer")
    Do $$$AssertEquals(e.needsIssuer, 1, "needsIssuer")
    Do $$$AssertTrue(e.daysLeft > 0, "daysLeft")
    Do $$$AssertEquals(e.url, "opc.tcp://certified-server:4840", "url")
    // the CRL really is checked: Inspect reports the trusted server
    Do ..Fetch(.r2)
    Do $$$AssertEquals(r2.trusted, 1, "Inspect now says trusted")
    // Removing trust deletes everything
    Set tSC = ##class(OPCUA.Security.Trust).Remove(##class(OPCUA.Security.Store).ServerKey(..#URL))
    Do $$$AssertStatusOK(tSC, "remove")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).GetServer(##class(OPCUA.Security.Store).ServerKey(..#URL), .e2), 0, "entry gone")
    Do $$$AssertEquals(..TrustDirCount(), 0, "files gone")
}

Method TestAddIssuerWrongCa()
{
    Quit:..Skipped()
    Quit:'..HaveFixtures()
    Quit:'..Fetch(.r)
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, r.certificate.sha256, "", .res)
    Do $$$AssertStatusOK(tSC, "trust")
    Quit:$$$ISERR(tSC)
    // a fresh self-signed CA that did not issue the server certificate
    Set dir = ..Root_"fx/"
    Do ##class(%File).CreateDirectoryChain(dir)
    Set tSC = ##class(OPCUA.Security.Native).CreateIdentity(dir_"c.der", dir_"k.der", "urn:fake:ca", "fake", "Fake CA")
    Do $$$AssertStatusOK(tSC, "make the fake CA")
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(dir_"c.der"), ..Hex(..Fx()_"myCA.crl"), .res2)
    Do $$$AssertTrue($$$ISERR(tSC), "a CA that did not issue the certificate is refused")
    Do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
    Do $$$AssertEquals(..TrustDirCount(), 1, "nothing added to the trust dir")
    // right CA, but a CRL the CA did not sign
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), "00", .res3)
    Do $$$AssertTrue($$$ISERR(tSC), "an unreadable CRL is refused")
    Do $$$AssertEquals(..TrustDirCount(), 1, "still nothing added")
}

Method Openssl(pArgs...) As %Integer
{
    Quit $ZF(-100, "/STDOUT=""/dev/null"" /STDERR=""/dev/null""", "openssl", pArgs...)
}

Method WriteLines(pPath As %String, pLines As %String)
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(pPath)
    For i = 1:1:$Length(pLines, "|") Do f.WriteLine($Piece(pLines, "|", i))
    Do f.%Save()
}

/// A well-formed CRL that another CA signed must not be accepted for myCA; the previously
/// stored issuer must survive the failed attempt.
Method TestAddIssuerCrlFromOtherCa()
{
    Quit:..Skipped()
    Quit:'..HaveFixtures()
    Quit:'..Fetch(.r)
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, r.certificate.sha256, "", .res)
    Do $$$AssertStatusOK(tSC, "trust")
    Quit:$$$ISERR(tSC)
    Set d = ..Root_"ca2/"
    Do ##class(%File).CreateDirectoryChain(d)
    Do ..WriteLines(d_"ca.cnf", "[ca]|default_ca=x|[x]|database="_d_"index.txt|crlnumber="_d_"crlnumber|default_md=sha256|default_crl_days=30|[ext]|basicConstraints=critical,CA:TRUE|keyUsage=keyCertSign,cRLSign")
    Open d_"index.txt":"NWS":2
    Close d_"index.txt"
    Do ..WriteLines(d_"crlnumber", "01")
    Set rc = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"ca.key", "-out", d_"ca.pem", "-days", "30", "-subj", "/CN=OtherCA", "-extensions", "ext", "-config", d_"ca.cnf")
    If rc '= 0 Set rc = ..Openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", d_"ca.key", "-out", d_"ca.pem", "-days", "30", "-subj", "/CN=OtherCA")
    Do $$$AssertEquals(rc, 0, "openssl made the other CA")
    Quit:rc
    Set rc = ..Openssl("ca", "-gencrl", "-config", d_"ca.cnf", "-keyfile", d_"ca.key", "-cert", d_"ca.pem", "-out", d_"other.crl.pem")
    Do $$$AssertEquals(rc, 0, "openssl made a CRL signed by the other CA")
    Quit:rc
    Set tHexCrl = ..Hex(d_"other.crl.pem")
    // 1: nothing stored yet
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), tHexCrl, .x1)
    Do $$$AssertTrue($$$ISERR(tSC), "a valid CRL signed by another CA is refused")
    Do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
    Do $$$AssertEquals(..TrustDirCount(), 1, "trusted/ holds only the server certificate")
    Set tKey = ##class(OPCUA.Security.Store).ServerKey(..#URL)
    Do $$$AssertEquals(..CountFiles(##class(OPCUA.Security.Store).ServerDir(tKey, "crl")), 0, "crl/ is empty")
    Do ##class(OPCUA.Security.Store).GetServer(tKey, .e)
    Do $$$AssertEquals(e.hasIssuer, 0, "entry still has no issuer")
    // 2: a good issuer is stored, then a bad attempt must not remove it
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), ..Hex(..Fx()_"myCA.crl"), .x2)
    Do $$$AssertStatusOK(tSC, "the real issuer is accepted")
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), tHexCrl, .x3)
    Do $$$AssertTrue($$$ISERR(tSC), "bad CRL refused again")
    Do $$$AssertEquals(..TrustDirCount(), 2, "the good issuer is still there")
    Do $$$AssertEquals(..CountFiles(##class(OPCUA.Security.Store).ServerDir(tKey, "crl")), 1, "and its CRL")
    Set tSC = ##class(OPCUA.Security.Trust).Pin(..#URL, .fps, .td, .cd, .h)
    Do $$$AssertStatusOK(tSC, "Pin still works")
    // scratch is cleaned up and never sits inside a trust or crl directory
    Do $$$AssertEquals(..CountFiles(td), 2, "no scratch files in trusted/")
}

Method TestChangedDetected()
{
    Quit:..Skipped()
    Quit:'..Fetch(.r)
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, r.certificate.sha256, "", .res)
    Do $$$AssertStatusOK(tSC, "trust")
    Quit:$$$ISERR(tSC)
    Set key = ##class(OPCUA.Security.Store).ServerKey(..#URL)
    Do ##class(OPCUA.Security.Store).GetServer(key, .e)
    Set e.fingerprint = "AA:BB:CC"
    Do ##class(OPCUA.Security.Store).SaveServer(key, e)
    Quit:'..Fetch(.r2)
    Do $$$AssertEquals(r2.changed, 1, "changed")
    Do $$$AssertEquals(r2.trusted, 0, "not trusted any more")
    Do $$$AssertEquals(r2.pinnedFingerprint, "AA:BB:CC", "old pin shown")
    Do $$$AssertTrue($IsObject(r2.previous), "previous present")
    Do $$$AssertEquals(r2.previous.subject, e.subject, "previous subject")
}

}
