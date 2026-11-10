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
    Do $$$AssertEquals(a, "", "no setup arguments are produced")
}

Method TestManagedRefusesEmptyHost()
{
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://[]:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "an empty host in brackets is refused")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

Method TestManagedRefusesUntrusted()
{
    // A configured identity that is not usable still refuses; trust is checked live.
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://never-trusted:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "refused")
    Do $$$AssertEquals(pins, "", "no pins")
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

}
