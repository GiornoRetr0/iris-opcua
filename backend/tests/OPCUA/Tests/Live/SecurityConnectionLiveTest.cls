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

}
