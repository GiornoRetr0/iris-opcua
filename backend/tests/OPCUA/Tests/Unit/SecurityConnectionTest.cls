Include %occInclude

/// Offline tests for OPCUA.Security.Connection (managed vs manual resolution) and the
/// pure Diagnose.Classify. Resolve is checked instead of Setup: SetupClient is Final, so
/// every refusal must happen in Resolve, before any native call.
Class OPCUA.Tests.Unit.SecurityConnectionTest Extends %UnitTest.TestCase
{

Property Root As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-conn-unit-"_$Job)
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityConnTest
    Set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityConnTest"
    Set ^%OPCUA.Security.Override("root") = ..Root
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityConnTest
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ^%OPCUA.SecurityConnTest
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

Method TestIsManaged()
{
    Do $$$AssertEquals(##class(OPCUA.Security.Connection).IsManaged(3, "", ""), 1, "mode 3 without paths is managed")
    Do $$$AssertEquals(##class(OPCUA.Security.Connection).IsManaged(3, "/a.der", ""), 0, "a certificate path makes it manual")
    Do $$$AssertEquals(##class(OPCUA.Security.Connection).IsManaged(3, "", "/k.der"), 0, "a key path makes it manual")
    Do $$$AssertEquals(##class(OPCUA.Security.Connection).IsManaged(1, "", ""), 0, "mode 1 is never managed")
}

Method TestManualUnchanged()
{
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://x:4840", 3, "urn:secuac", "/c.der", "/k.der", "/t/", "/r/", .a, .pins, .host, .managed)
    Do $$$AssertStatusOK(tSC, "manual resolves")
    Do $$$AssertEquals(managed, 0, "not managed")
    Do $$$AssertEquals($ListToString(a, "|"), "3|urn:secuac|/c.der|/k.der|/t/|/r/", "arguments pass through unchanged")
    Do $$$AssertEquals(pins, "", "no pin")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://x:4840", 1, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertEquals(managed, 0, "mode 1 not managed")
    Do $$$AssertEquals($ListToString(a, "|"), "1|||||", "mode 1 arguments unchanged")
}

Method TestManagedRefusesNoIdentity()
{
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://x:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertEquals(managed, 1, "managed")
    Do $$$AssertStatusNotOK(tSC, "refused without an identity")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: No IRIS client identity is set up. Open Settings "_$Char(8250)_" OPC UA Security to create one.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments are produced")
}

Method TestManagedRefusesEmptyHost()
{
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://[]:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "an empty host in brackets is refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: The server address has no host name. Enter it as opc.tcp://host:port.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

/// A usable identity in the test store.
Method MakeIdentity() As %Boolean
{
    Set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .st)
    Do $$$AssertStatusOK(tSC, "identity created")
    Quit $$$ISOK(tSC)
}

/// A pin entry; pFiles are written into the trusted directory.
Method Seed(pURL As %String, pNeedsIssuer As %Boolean, pFiles As %String)
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
    Do ##class(OPCUA.Security.Store).SaveServer(key, {"url": (##class(OPCUA.Security.Store).NormaliseURL(pURL)), "fingerprint": "AA:BB", "subject": "CN=s", "issuer": "CN=myCA", "notAfter": "2099-01-01 00:00:00", "selfSigned": (+'pNeedsIssuer), "needsIssuer": (+pNeedsIssuer), "hasIssuer": 0})
}

Method TestManagedRefusesUntrusted()
{
    Quit:'..MakeIdentity()
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://never-trusted:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "no pin: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments (no native call)")
    Do $$$AssertEquals(pins, "", "no pins")
}

Method TestManagedRefusesEmptyTrustDir()
{
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://emptytrust:4840", 0, "")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://emptytrust:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "entry but nothing in the trust directory: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

Method TestManagedRefusesMissingIssuer()
{
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://needsca:4840", 1, "server.der")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://needsca:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "CA-signed without issuer and CRL: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: This server's certificate was issued by CN=myCA. Add that CA certificate and its revocation list before connecting.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

Method TestManagedResolvesWhenTrusted()
{
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://selfsigned:4840", 0, "server.der")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://selfsigned:4840", 3, "ignored", "", "", "x", "y", .a, .pins, .host, .managed)
    Do $$$AssertStatusOK(tSC, "resolves")
    Do $$$AssertEquals($ListGet(a, 1), 3, "mode 3")
    Do $$$AssertTrue($ListGet(a, 2) '= "ignored", "the identity's URI, not the caller's")
    Do $$$AssertEquals(pins, $ListBuild("AA:BB"), "pin")
    Do $$$AssertEquals(host, "selfsigned", "host")
}

Method TestClassifyUnknownFingerprintNotChanged()
{
    For tSha = "", "absent" {
        Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1}
        If tSha = "" Set d.sha256 = ""
        Set r = ##class(OPCUA.Security.Diagnose).Classify("BadConnectionClosed", d, "AA:AA", "BB")
        Do $$$AssertNotEquals(r.category, "serverChanged", "unknown presented fingerprint is not a change ("_tSha_")")
        Do $$$AssertEquals(r.category, "clientNotApproved", "falls through ("_tSha_")")
    }
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadUserAccessDenied", {"reachable": 1, "offersSignAndEncrypt": 1}, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "other", "other error stays other")
}

Method TestDiagnosisDedupe()
{
    Set d1 = {"category": "clientNotApproved", "serverFingerprint": "AA"}
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).IsNew("", d1, .k1), 1, "first failure is logged")
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).IsNew(k1, d1, .k2), 0, "same category and fingerprint: not logged again")
    Set d2 = {"category": "clientNotApproved", "serverFingerprint": "BB"}
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).IsNew(k1, d2, .k3), 1, "new server fingerprint is logged")
    Set d3 = {"category": "network"}
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).IsNew(k3, d3, .k4), 1, "new category is logged")
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).IsNew("", d3, .k5), 1, "after recovery the same failure is logged again")
}

Method TestClassifyNetwork()
{
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadConnectionClosed", {"reachable": 0}, "AA", "BB")
    Do $$$AssertEquals(r.category, "network", "category")
    Do $$$AssertEquals(r.message, "IRIS could not reach the OPC UA server. Check the URL, port and firewall.", "message")
}

Method TestClassifyNoSecureEndpoint()
{
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadConnectionClosed", {"reachable": 1, "offersSignAndEncrypt": 0}, "AA", "BB")
    Do $$$AssertEquals(r.category, "noSecureEndpoint", "category")
    Do $$$AssertEquals(r.message, "The server does not offer Sign & Encrypt with a security policy IRIS supports.", "message")
}

Method TestClassifyServerChanged()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1, "sha256": "CC:CC"}
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadConnectionClosed", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "serverChanged", "category")
    Do $$$AssertEquals(r.message, "Server certificate changed"_$Char(8212)_"review and approve the replacement.", "message")
}

Method TestClassifyHostMismatch()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 0, "sha256": "AA:AA"}
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadConnectionClosed", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "hostMismatch", "category (from discovery)")
    Do $$$AssertEquals(r.message, "The server's certificate does not name the host in this URL.", "message")
    Set d.hostMatches = 1
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadCertificateHostNameInvalid", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "hostMismatch", "category (from status)")
}

Method TestClassifyUriInvalid()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1, "sha256": "AA:AA"}
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadCertificateUriInvalid", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "uriInvalid", "category")
    Do $$$AssertEquals(r.message, "The Client URI does not match IRIS's certificate.", "message")
}

Method TestClassifyTimeInvalid()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1, "sha256": "AA:AA"}
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadCertificateTimeInvalid", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "timeInvalid", "category")
    Do $$$AssertEquals(r.message, "A certificate is expired or not yet valid, or the clocks differ.", "message")
}

Method TestClassifyClientNotApproved()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1, "sha256": "aa:aa"}
    For tErr = "BadSecurityChecksFailed", "BadCertificateUntrusted", "BadCertificateInvalid", "BadSecureChannelClosed", "BadConnectionClosed" {
        Set r = ##class(OPCUA.Security.Diagnose).Classify(tErr, d, "AA:AA", "BB:BB")
        Do $$$AssertEquals(r.category, "clientNotApproved", tErr_" category")
    }
    Do $$$AssertEquals(r.message, "The OPC UA server has not approved IRIS's certificate yet. Download the IRIS client certificate, ask the server administrator to trust it (often: move it from the server's ""rejected"" to its ""trusted"" certificates), then test again.", "message")
    Do $$$AssertEquals(r.clientFingerprint, "BB:BB", "client fingerprint")
}

Method TestClassifyOther()
{
    Set d = {"reachable": 1, "offersSignAndEncrypt": 1, "hostMatches": 1, "sha256": "AA:AA"}
    Set r = ##class(OPCUA.Security.Diagnose).Classify("BadUserAccessDenied", d, "AA:AA", "BB")
    Do $$$AssertEquals(r.category, "other", "category")
    Do $$$AssertEquals(r.message, "BadUserAccessDenied", "the original error text")
}

Method TestClassifyRefusal()
{
    Set tNoId = ##class(OPCUA.Security.Diagnose).ClassifyRefusal($$$ERROR($$$GeneralError, "No IRIS client identity is set up. Open Settings to create one."))
    Do $$$AssertEquals(tNoId.category, "noIdentity", "no identity")
    Set tBad = ##class(OPCUA.Security.Diagnose).ClassifyRefusal($$$ERROR($$$GeneralError, "The IRIS client identity is not usable: expired"))
    Do $$$AssertEquals(tBad.category, "identityInvalid", "invalid identity")
    Set tNT = ##class(OPCUA.Security.Diagnose).ClassifyRefusal($$$ERROR($$$GeneralError, ##class(OPCUA.Security.Trust).#NotTrusted))
    Do $$$AssertEquals(tNT.category, "notTrusted", "not trusted")
    Do $$$AssertEquals(tNT.message, ##class(OPCUA.Security.Trust).#NotTrusted, "message without the status prefix")
    Set tIss = ##class(OPCUA.Security.Diagnose).ClassifyRefusal($$$ERROR($$$GeneralError, "This server's certificate was issued by CN=myCA. Add that CA certificate and its revocation list before connecting."))
    Do $$$AssertEquals(tIss.category, "issuerMissing", "issuer missing")
    Set tOth = ##class(OPCUA.Security.Diagnose).ClassifyRefusal($$$ERROR($$$GeneralError, "The server address has no host name."))
    Do $$$AssertEquals(tOth.category, "other", "anything else")
}

Method TestResolveRefusalsClassify()
{
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://noid:4840", 3, "", "", "", "", "", .a, .p, .h, .m)
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).ClassifyRefusal(tSC).category, "noIdentity", "no identity yet")
    Quit:'..MakeIdentity()
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://never:4840", 3, "", "", "", "", "", .a, .p, .h, .m)
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).ClassifyRefusal(tSC).category, "notTrusted", "untrusted")
    Do ..Seed("opc.tcp://needsca2:4840", 1, "server.der")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://needsca2:4840", 3, "", "", "", "", "", .a, .p, .h, .m)
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).ClassifyRefusal(tSC).category, "issuerMissing", "no issuer")
}

}
