/// Offline tests for OPCUA.Security.Store (URL normalisation, keys, Client URI, store).
/// Every test that writes redirects the store with ^%OPCUA.Security.Override so the
/// real instance identity is never touched.
Class OPCUA.Tests.Unit.SecurityStoreTest Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override
    Set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityTest"
    Kill ^%OPCUA.SecurityTest
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^%OPCUA.Security.Override
    Kill ^%OPCUA.SecurityTest
    Quit $$$OK
}

Method TestNormaliseURL()
{
    Do $$$AssertEquals(##class(OPCUA.Security.Store).NormaliseURL("opc.tcp://Certified-Server:4840/"), "opc.tcp://certified-server:4840", "case, port and trailing slash")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).NormaliseURL("opc.tcp://certified-server"), "opc.tcp://certified-server:4840", "default port made explicit")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).NormaliseURL("OPC.TCP://Plc:10000/Path/Seg/"), "opc.tcp://plc:10000/Path/Seg", "path case kept, trailing slash removed")
}

Method TestServerKeyStable()
{
    Set k1 = ##class(OPCUA.Security.Store).ServerKey("opc.tcp://Certified-Server:4840/")
    Set k2 = ##class(OPCUA.Security.Store).ServerKey("opc.tcp://certified-server")
    Set k3 = ##class(OPCUA.Security.Store).ServerKey("opc.tcp://plc")
    Do $$$AssertEquals(k1, k2, "equivalent URL forms share a key")
    Do $$$AssertNotEquals(k1, k3, "different servers differ")
    Do $$$AssertTrue($Match(k1, "^[0-9a-f]{16}$"), "16 lowercase hex characters")
}

Method TestURLHost()
{
    Do $$$AssertEquals(##class(OPCUA.Security.Store).URLHost("opc.tcp://Certified-Server:4840/x"), "certified-server", "host")
}

Method TestDefaultClientURI()
{
    Set uri = ##class(OPCUA.Security.Store).DefaultClientURI()
    Do $$$AssertTrue(uri ? 1"urn:".E, "starts with urn: "_uri)
    Do $$$AssertTrue($Match(uri, "^urn:[a-z0-9.-]+:intersystems:iris:[a-z0-9._-]+:opcua$"), "matches default shape: "_uri)
    Do $$$AssertTrue(##class(OPCUA.Security.Store).ValidClientURI(uri), "default is valid")
}

Method TestValidClientURI()
{
    Set s = "OPCUA.Security.Store"
    Do $$$AssertTrue($classmethod(s, "ValidClientURI", "urn:host:intersystems:iris:iris:opcua"), "good")
    Do $$$AssertNotTrue($classmethod(s, "ValidClientURI", "urn:a"_$Char(10)_"b"), "newline")
    Do $$$AssertNotTrue($classmethod(s, "ValidClientURI", "urn:a b"), "space")
    Do $$$AssertNotTrue($classmethod(s, "ValidClientURI", "urn:a;b"), "semicolon")
    Do $$$AssertNotTrue($classmethod(s, "ValidClientURI", ""), "empty")
}

Method TestOverrideRoot()
{
    Set default = ##class(OPCUA.Security.Store).Root()
    Set ^%OPCUA.Security.Override("root") = "/tmp/opcua-pki-test"
    Do $$$AssertEquals(##class(OPCUA.Security.Store).Root(), ##class(%File).NormalizeDirectory("/tmp/opcua-pki-test"), "override honoured")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).Dir("own"), ##class(%File).NormalizeDirectory("/tmp/opcua-pki-test/own"), "own dir under override")
    Kill ^%OPCUA.Security.Override("root")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).Root(), default, "override removed")
    Do $$$AssertEquals(##class(OPCUA.Security.Store).Global(), "^%OPCUA.SecurityTest", "global override honoured")
}

Method TestEnsureDirs()
{
    Set ^%OPCUA.Security.Override("root") = "/tmp/opcua-pki-test-dirs"
    Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(##class(OPCUA.Security.Store).ServerDir("abc", "trusted"))
    Do $$$AssertStatusOK(tSC, "EnsureDirs")
    Do $$$AssertTrue(##class(%File).DirectoryExists(##class(OPCUA.Security.Store).ServerDir("abc", "trusted")), "trusted dir exists")
    Do ##class(%File).RemoveDirectoryTree("/tmp/opcua-pki-test-dirs")
    Kill ^%OPCUA.Security.Override("root")
}

Method TestConfigRoundTrip()
{
    Set found = ##class(OPCUA.Security.Store).GetIdentity(.c)
    Do $$$AssertNotTrue(found, "no identity yet")
    Do ##class(OPCUA.Security.Store).SaveIdentity({"source":"generated","clientURI":"urn:x","fingerprint":"AB"})
    Set found = ##class(OPCUA.Security.Store).GetIdentity(.c)
    Do $$$AssertTrue(found, "identity found")
    Do $$$AssertEquals(c.source, "generated", "source")
    Do $$$AssertEquals(c.clientURI, "urn:x", "uri")
    Do ##class(OPCUA.Security.Store).ClearIdentity()
    Set found = ##class(OPCUA.Security.Store).GetIdentity(.c)
    Do $$$AssertNotTrue(found, "cleared")

    Do ##class(OPCUA.Security.Store).SaveServer("k1", {"url":"opc.tcp://a:4840","key":"k1","label":"A"})
    Do ##class(OPCUA.Security.Store).SaveServer("k2", {"url":"opc.tcp://b:4840","key":"k2","label":"B"})
    Set found = ##class(OPCUA.Security.Store).GetServer("k1", .e)
    Do $$$AssertTrue(found, "server found")
    Do $$$AssertEquals(e.label, "A", "label")
    Set l = ##class(OPCUA.Security.Store).ListServers()
    Do $$$AssertEquals(l.%Size(), 2, "two servers")
    Do ##class(OPCUA.Security.Store).RemoveServer("k1")
    Set found = ##class(OPCUA.Security.Store).GetServer("k1", .e)
    Do $$$AssertNotTrue(found, "removed")
    Set l = ##class(OPCUA.Security.Store).ListServers()
    Do $$$AssertEquals(l.%Size(), 1, "one left")
    Do ##class(OPCUA.Security.Store).RemoveServer("k2")
}

}
