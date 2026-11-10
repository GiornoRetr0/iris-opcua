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
