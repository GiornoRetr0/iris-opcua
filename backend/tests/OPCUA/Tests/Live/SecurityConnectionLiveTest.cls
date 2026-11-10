Include %occInclude

/// Live tests of managed Sign & Encrypt connections against the demo certified-server,
/// which does not trust the generated IRIS identity (approval is the setup script's
/// job): the connection must fail, be diagnosed as clientNotApproved, and never fall
/// back to an unsecured mode. The store is redirected to a throwaway global and root.
Class OPCUA.Tests.Live.SecurityConnectionLiveTest Extends %UnitTest.TestCase
{

Parameter URL = "opc.tcp://certified-server:4840";

Property Root As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..Skip = ""
    If '##class(OPCUA.Utils).SupportsPki() Set ..Skip = "connector 0.5 PKI is not available" Quit $$$OK
    Set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-conn-live-"_$Job)
    Do ##class(%File).RemoveDirectoryTree(..Root)
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityConnLive
    Set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityConnLive"
    Set ^%OPCUA.Security.Override("root") = ..Root
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityConnLive
    If ..Root '= "" Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ^%OPCUA.SecurityConnLive
    If ..Root '= "" Do ##class(%File).RemoveDirectoryTree(..Root)
    Quit $$$OK
}

Method Skipped() As %Boolean
{
    If ..Skip = "" Quit 0
    Do $$$AssertSkipped(..Skip)
    Quit 1
}

ClassMethod Fx() As %String
{
    Quit "/tmp/opcua-dev/fixtures/certified-server/"
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

/// Identity created, server trusted with its issuer; false (with a skip) if fixtures are absent.
Method Prepare() As %Boolean
{
    If '(##class(%File).Exists(..Fx()_"myCA.crt.der") && ##class(%File).Exists(..Fx()_"myCA.crl")) {
        Do $$$AssertSkipped("demo certificates not in "_..Fx()_" (run dev-load.sh)")
        Quit 0
    }
    Set tSC = ##class(OPCUA.Security.Identity).Create("", 0, "", .tStatus)
    Do $$$AssertStatusOK(tSC, "identity created")
    Quit:$$$ISERR(tSC) 0
    Set ..Fp = tStatus.fingerprint
    Set tSC = ##class(OPCUA.Security.Trust).Inspect(..#URL, .r)
    Quit:$$$ISERR(tSC) 0
    Set tSC = ##class(OPCUA.Security.Trust).Trust(..#URL, r.certificate.sha256, "Demo", .res)
    Do $$$AssertStatusOK(tSC, "server trusted")
    Quit:$$$ISERR(tSC) 0
    Set tSC = ##class(OPCUA.Security.Trust).AddIssuer(..#URL, ..Hex(..Fx()_"myCA.crt.der"), ..Hex(..Fx()_"myCA.crl"), .res2)
    Do $$$AssertStatusOK(tSC, "issuer added")
    Quit $$$ISOK(tSC)
}

Property Fp As %String;

Method TestManagedBeforeApproval()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
    Do $$$AssertStatusNotOK(tSC, "managed connect fails before the server approves IRIS")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
    Set d = ##class(OPCUA.Security.Diagnose).Run(..#URL, tSC)
    Do $$$AssertEquals(d.category, "clientNotApproved", "diagnosis (failure: "_$System.Status.GetErrorText(tSC)_")")
    Do $$$AssertEquals(d.clientFingerprint, ..Fp, "the fingerprint is the identity's")
}

Method TestManagedUnreachable()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    Set tURL = "opc.tcp://certified-server:4999"
    Set d = ##class(OPCUA.Security.Diagnose).Run(tURL, $$$ERROR($$$GeneralError, "BadConnectionClosed"))
    Do $$$AssertEquals(d.category, "network", "unreachable port")
}

Method TestServerChangedDiagnosed()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    // Pretend the pin is another certificate.
    Set tKey = ##class(OPCUA.Security.Store).ServerKey(..#URL)
    Do ##class(OPCUA.Security.Store).GetServer(tKey, .e)
    Set e.fingerprint = "00:11:22"
    Do ##class(OPCUA.Security.Store).SaveServer(tKey, e)
    Set d = ##class(OPCUA.Security.Diagnose).Run(..#URL, $$$ERROR($$$GeneralError, "BadConnectionClosed"))
    Do $$$AssertEquals(d.category, "serverChanged", "a different pinned certificate")
}

/// Overwrites the stored pin, as a server presenting a different certificate looks.
Method SetPin(pFp As %String)
{
    Set tKey = ##class(OPCUA.Security.Store).ServerKey(..#URL)
    Do ##class(OPCUA.Security.Store).GetServer(tKey, .e)
    Set e.fingerprint = pFp
    Do ##class(OPCUA.Security.Store).SaveServer(tKey, e)
}

Method TestPinnedMismatchRejected()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    // A valid fingerprint that is not the server's: the identity's own.
    Do ..SetPin(..Fp)
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
    Do $$$AssertStatusNotOK(tSC, "a server presenting another certificate than the pinned one is rejected")
    Set tConnected = 0
    If $IsObject($Get(tClient)) Do tClient.GetClientState("", .tConnected)
    Do $$$AssertEquals(+tConnected, 0, "no session")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
    Set d = ##class(OPCUA.Security.Diagnose).Run(..#URL, tSC)
    Do $$$AssertEquals(d.category, "serverChanged", "diagnosis")
    Do $$$AssertEquals(d.message, "Server certificate changed"_$Char(8212)_"review and approve the replacement.", "exact message")
}

/// The adapter sets the client up again after a failed managed connect; this is the same
/// flow (one client, Setup + Connect repeated) with the pin changed between attempts:
/// each attempt re-resolves the pin, so the diagnosis follows it.
Method TestResetupPicksUpNewPin()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    Set tRealFp = ##class(OPCUA.Security.Store).ServerKey(..#URL)
    Do ##class(OPCUA.Security.Store).GetServer(tRealFp, .e0)
    Set tReal = e0.fingerprint
    Do ##class(OPCUA.Utils).Initialize()
    Set tClient = ##class(OPCUA.Client).%New()
    Do tClient.Initialize()
    Do ..SetPin(..Fp)
    Do $$$AssertStatusOK(##class(OPCUA.Security.Connection).Setup(tClient, ..#URL, 3, "", "", "", "", "", .m, ""), "setup 1")
    Set tSC = tClient.Connect(..#URL, "", "")
    Do $$$AssertStatusNotOK(tSC, "attempt 1 fails")
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).Run(..#URL, tSC).category, "serverChanged", "attempt 1 against the wrong pin")
    Do ..SetPin(tReal)
    Do $$$AssertStatusOK(##class(OPCUA.Security.Connection).Setup(tClient, ..#URL, 3, "", "", "", "", "", .m, ""), "setup 2")
    Set tSC = tClient.Connect(..#URL, "", "")
    Do $$$AssertStatusNotOK(tSC, "attempt 2 still fails (not approved)")
    Do $$$AssertEquals(##class(OPCUA.Security.Diagnose).Run(..#URL, tSC).category, "clientNotApproved", "attempt 2 sees the restored pin")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
}

Method TestNoFallback()
{
    Quit:..Skipped()
    Quit:'..Prepare()
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
    Do $$$AssertStatusNotOK(tSC, "connect fails")
    Set tConnected = 0
    If $IsObject($Get(tClient)) Do tClient.GetClientState("", .tConnected)
    Do $$$AssertEquals(+tConnected, 0, "no session was opened")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
}

Method TestNoIdentityRefusesBeforeNative()
{
    Quit:..Skipped()
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3)
    Do $$$AssertStatusNotOK(tSC, "refused")
    Do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "No IRIS client identity", "says to set up an identity")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
}

Method TestMode1Unchanged()
{
    Quit:..Skipped()
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, "opc.tcp://plc:4840", 1)
    Do $$$AssertStatusOK(tSC, "plc connects in mode 1")
    Quit:$$$ISERR(tSC)
    Set tSC = tClient.Browse(.tRes, $LB(0), $LB(0), $LB(85))
    Do $$$AssertStatusOK(tSC, "browse works")
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
}

Method TestManualDemoUnchanged()
{
    Quit:..Skipped()
    Set tC = "/usr/irissys/uac/certs/"
    If '##class(%File).Exists(tC_"secuac.crt.der") Do $$$AssertSkipped("demo secuac files not present") Quit
    Set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, ..#URL, 3, "", "", tC_"secuac.crt.der", tC_"secuac.key.der", tC_"trustdir", tC_"crldir", "urn:secuac")
    Do $$$AssertStatusOK(tSC, "explicit demo paths still connect: "_$System.Status.GetErrorText(tSC))
    Do ##class(OPCUA.REST.ClientManager).Disconnect(tClient)
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
    Quit:..Skipped()
    Quit:'..MakeIdentity()
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://never-trusted:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "no pin: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments (no native call)")
    Do $$$AssertEquals(pins, "", "no pins")
}

Method TestManagedRefusesEmptyTrustDir()
{
    Quit:..Skipped()
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://emptytrust:4840", 0, "")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://emptytrust:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "entry but nothing in the trust directory: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

Method TestManagedRefusesMissingIssuer()
{
    Quit:..Skipped()
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://needsca:4840", 1, "server.der")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://needsca:4840", 3, "", "", "", "", "", .a, .pins, .host, .managed)
    Do $$$AssertStatusNotOK(tSC, "CA-signed without issuer and CRL: refused")
    Do $$$AssertEquals($System.Status.GetErrorText(tSC), "ERROR #5001: This server's certificate was issued by CN=myCA. Add that CA certificate and its revocation list before connecting.", "message")
    Do $$$AssertEquals(a, "", "no setup arguments")
}

Method TestManagedResolvesWhenTrusted()
{
    Quit:..Skipped()
    Quit:'..MakeIdentity()
    Do ..Seed("opc.tcp://selfsigned:4840", 0, "server.der")
    Set tSC = ##class(OPCUA.Security.Connection).Resolve("opc.tcp://selfsigned:4840", 3, "ignored", "", "", "x", "y", .a, .pins, .host, .managed)
    Do $$$AssertStatusOK(tSC, "resolves")
    Do $$$AssertEquals($ListGet(a, 1), 3, "mode 3")
    Do $$$AssertTrue($ListGet(a, 2) '= "ignored", "the identity's URI, not the caller's")
    Do $$$AssertEquals(pins, $ListBuild("AA:BB"), "pin")
    Do $$$AssertEquals(host, "selfsigned", "host")
}

Method TestResolveRefusalsClassify()
{
    Quit:..Skipped()
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
