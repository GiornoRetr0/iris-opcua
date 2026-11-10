Include %occInclude

/// Offline tests for OPCUA.Security.Trust: the pure endpoint-identity check and the
/// refusals of Pin (nothing trusted, issuer missing, trust directory empty). The store
/// is redirected to a throwaway global and directory.
Class OPCUA.Tests.Unit.SecurityTrustTest Extends %UnitTest.TestCase
{

Property Root As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-trust-unit-"_$Job)
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityTrustTest
    Set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityTrustTest"
    Set ^%OPCUA.Security.Override("root") = ..Root
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityTrustTest
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

ClassMethod Cert(pUris As %String = "", pDns As %String = "", pIps As %String = "") As %DynamicObject
{
    Set c = {"sanUris": [], "sanDns": [], "sanIps": []}
    For i = 1:1:$Length(pUris, ",") { If $Piece(pUris, ",", i) '= "" Do c.sanUris.%Push($Piece(pUris, ",", i)) }
    For i = 1:1:$Length(pDns, ",") { If $Piece(pDns, ",", i) '= "" Do c.sanDns.%Push($Piece(pDns, ",", i)) }
    For i = 1:1:$Length(pIps, ",") { If $Piece(pIps, ",", i) '= "" Do c.sanIps.%Push($Piece(pIps, ",", i)) }
    Quit c
}

Method TestIdentityOk()
{
    Set ok = ##class(OPCUA.Security.Trust).CheckEndpointIdentity(..Cert("urn:srv", "srv.example"), "urn:srv", "SRV.example", .p)
    Do $$$AssertEquals(ok, 1, "matching URI and host pass (host compared without case)")
    Do $$$AssertEquals(p.%Size(), 0, "no problems")
}

Method TestIdentityUriMismatch()
{
    Set ok = ##class(OPCUA.Security.Trust).CheckEndpointIdentity(..Cert("urn:other", "srv"), "urn:srv", "srv", .p)
    Do $$$AssertEquals(ok, 0, "a different application URI fails")
    Do $$$AssertEquals(p.%Size(), 1, "one problem")
    Do $$$AssertEquals(p.%Get(0), "The certificate is for application urn:other, but the server says it is urn:srv.", "message")
}

Method TestIdentityHostMismatch()
{
    Set ok = ##class(OPCUA.Security.Trust).CheckEndpointIdentity(..Cert("urn:srv", "a.example,b.example"), "urn:srv", "c.example", .p)
    Do $$$AssertEquals(ok, 0, "a host the certificate does not name fails")
    Do $$$AssertEquals(p.%Size(), 1, "one problem")
    Do $$$AssertEquals(p.%Get(0), "The certificate does not name c.example; it names a.example, b.example.", "message")
}

Method TestIdentityIpHost()
{
    Set c = ..Cert("urn:srv", "srv", "10.1.2.3")
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).CheckEndpointIdentity(c, "urn:srv", "10.1.2.3", .p), 1, "an IP in the SAN matches")
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).CheckEndpointIdentity(c, "urn:srv", "10.1.2.4", .p), 0, "another IP fails")
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).CheckEndpointIdentity(c, "urn:srv", "[::1]", .p), 0, "a bracketed v6 literal is not silently accepted")
    Set c6 = ..Cert("urn:srv", "", "::1")
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).CheckEndpointIdentity(c6, "urn:srv", "::1", .p), 1, "an IPv6 literal matches")
}

Method Seed(pURL As %String, pNeedsIssuer As %Boolean, pHasIssuer As %Boolean, pFiles As %String) As %String
{
    Set key = ##class(OPCUA.Security.Store).ServerKey(pURL)
    Do ##class(OPCUA.Security.Store).EnsureDirs(##class(OPCUA.Security.Store).ServerDir(key, "trusted"))
    Do ##class(OPCUA.Security.Store).EnsureDirs(##class(OPCUA.Security.Store).ServerDir(key, "crl"))
    For i = 1:1:$Length(pFiles, ",") {
        Set f = $Piece(pFiles, ",", i)
        If f '= "" {
            Set s = ##class(%Stream.FileBinary).%New()
            Do s.LinkToFile(##class(OPCUA.Security.Store).ServerDir(key, "trusted")_f)
            Do s.Write("x")
            Do s.%Save()
        }
    }
    Do ##class(OPCUA.Security.Store).SaveServer(key, {"url": (##class(OPCUA.Security.Store).NormaliseURL(pURL)), "fingerprint": "AA:BB", "subject": "CN=s", "issuer": "CN=myCA", "notAfter": "2099-01-01 00:00:00", "selfSigned": (+'pNeedsIssuer), "needsIssuer": (+pNeedsIssuer), "hasIssuer": (+pHasIssuer)})
    Quit key
}

Method TestPinRefusesUntrusted()
{
    Set tSC = ##class(OPCUA.Security.Trust).Pin("opc.tcp://never-seen:4840", .fps, .td, .cd, .h)
    Do $$$AssertTrue($$$ISERR(tSC), "no entry: refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.", "message")
}

Method TestPinRefusesEmptyTrustDir()
{
    Set url = "opc.tcp://emptydir:4840"
    Set key = ..Seed(url, 0, 0, "")
    Set tSC = ##class(OPCUA.Security.Trust).Pin(url, .fps, .td, .cd, .h)
    Do $$$AssertTrue($$$ISERR(tSC), "entry present but the trust directory is empty: refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "does not trust this OPC UA server yet", "same message as untrusted (an empty list would allow everything)")
}

Method TestPinRefusesMissingIssuer()
{
    Set url = "opc.tcp://needsca:4840"
    Set key = ..Seed(url, 1, 0, "server.der")
    Set tSC = ##class(OPCUA.Security.Trust).Pin(url, .fps, .td, .cd, .h)
    Do $$$AssertTrue($$$ISERR(tSC), "CA-signed without issuer: refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "This server's certificate was issued by CN=myCA. Add that CA certificate and its revocation list before connecting.", "message names the issuer")
}

/// A fabricated Native.InspectCert-shaped object.
ClassMethod Info(pSelfSigned As %Boolean, pUsage As %String, pNotBefore As %String, pNotAfter As %String) As %DynamicObject
{
    Set c = ..Cert("urn:srv", "srv")
    Set c.selfSigned = pSelfSigned
    Set c.keyUsage = []
    For i = 1:1:$Length(pUsage, ",") { If $Piece(pUsage, ",", i) '= "" Do c.keyUsage.%Push($Piece(pUsage, ",", i)) }
    Set c.notBefore = pNotBefore, c.notAfter = pNotAfter
    Quit c
}

/// UTC "YYYY-MM-DD HH:MM:SS" pDays days (may be fractional) from now.
ClassMethod At(pDays As %Numeric) As %String
{
    Set n = $ZTimeStamp
    Set total = ($Piece(n, ",", 1) * 86400) + $Piece(n, ",", 2) + (pDays * 86400)
    Set days = total \ 86400
    Quit $ZDateTime(days_","_$Piece(total - (days * 86400), ".", 1), 3, 1, 0)
}

Method TestIdentityProblemsKeyCertSign()
{
    Set bad = ..Info(1, "digitalSignature,keyEncipherment", ..At(-1), ..At(100))
    Set p = ##class(OPCUA.Security.Trust).IdentityProblems(bad, "urn:srv", "srv")
    Do $$$AssertEquals(p.%Size(), 1, "one problem")
    Do $$$AssertEquals(p.%Get(0), "This server's self-signed certificate lacks the keyCertSign usage that IRIS's OPC UA library requires to trust it. Ask the server administrator to reissue it.", "ruled message")
    Set good = ..Info(1, "digitalSignature,keyCertSign", ..At(-1), ..At(100))
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).IdentityProblems(good, "urn:srv", "srv").%Size(), 0, "keyCertSign present: fine")
    Set ca = ..Info(0, "digitalSignature", ..At(-1), ..At(100))
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).IdentityProblems(ca, "urn:srv", "srv").%Size(), 0, "CA-signed needs no keyCertSign")
}

Method TestIdentityProblemsValidity()
{
    Set exp = ##class(OPCUA.Security.Trust).IdentityProblems(..Info(0, "", ..At(-10), ..At(-1)), "urn:srv", "srv")
    Do $$$AssertEquals(exp.%Size(), 1, "expired: one problem")
    Do $$$AssertTrue(exp.%Get(0) [ "expired on", "says expired: "_exp.%Get(0))
    Set nyv = ##class(OPCUA.Security.Trust).IdentityProblems(..Info(0, "", ..At(1), ..At(10)), "urn:srv", "srv")
    Do $$$AssertEquals(nyv.%Size(), 1, "not yet valid: one problem")
    Do $$$AssertTrue(nyv.%Get(0) [ "not valid before", "says not valid before: "_nyv.%Get(0))
}

Method TestTrustRefusesIdentityProblems()
{
    Set bad = {"offersSignAndEncrypt": 1, "identity": {"problems": []}}
    Set bad.identity.problems = ##class(OPCUA.Security.Trust).IdentityProblems(..Info(1, "digitalSignature", ..At(-1), ..At(100)), "urn:srv", "srv")
    Set tSC = ##class(OPCUA.Security.Trust).CheckTrustable(bad)
    Do $$$AssertTrue($$$ISERR(tSC), "refused")
    Do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "keyCertSign", "names keyCertSign")
    Set none = {"offersSignAndEncrypt": 0, "identity": {"problems": []}}
    Do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(##class(OPCUA.Security.Trust).CheckTrustable(none)), 400, "no Sign & Encrypt endpoint: 400")
    Set ok = {"offersSignAndEncrypt": 1, "identity": {"problems": []}}
    Do $$$AssertStatusOK(##class(OPCUA.Security.Trust).CheckTrustable(ok), "clean result passes")
}

Method TestDaysLeft()
{
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).DaysLeft(..At(10.04)), 10, "10 days and an hour")
    Do $$$AssertTrue(##class(OPCUA.Security.Trust).DaysLeft(..At(-3)) < 0, "past is negative")
    Do $$$AssertEquals(##class(OPCUA.Security.Trust).DaysLeft(""), 0, "empty")
}

Method TestPinAcceptsSelfSignedEntry()
{
    Set url = "opc.tcp://[::1]:4840"
    Set key = ..Seed(url, 0, 0, "server.der")
    Set tSC = ##class(OPCUA.Security.Trust).Pin(url, .fps, .td, .cd, .h)
    Do $$$AssertStatusOK(tSC, "a pinned self-signed entry with its file passes")
    Do $$$AssertEquals($ListGet(fps, 1), "AA:BB", "fingerprint list")
    Do $$$AssertEquals(h, "::1", "host without brackets")
    Do $$$AssertEquals(td, ##class(OPCUA.Security.Store).ServerDir(key, "trusted"), "trust dir")
}

}
