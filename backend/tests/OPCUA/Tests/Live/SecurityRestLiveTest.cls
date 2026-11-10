Include %occInclude

/// Live tests of the managed Sign &amp; Encrypt REST layer that create a real client
/// identity, which needs the native connector (PKI support). The store is redirected
/// to a test global and directory.
Class OPCUA.Tests.Live.SecurityRestLiveTest Extends %UnitTest.TestCase
{

Property Root As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
	set ..Skip = ""
	if '##class(OPCUA.Utils).SupportsPki() set ..Skip = "connector 0.5 PKI is not available" Quit $$$OK
	set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-secrest-live-"_$Job)
	do ##class(%File).RemoveDirectoryTree(..Root)
	kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityRestLive
	set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityRestLive"
	set ^%OPCUA.Security.Override("root") = ..Root
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityRestLive
	kill ^||OPCUA.Tests("securityPrivilege")
	if ..Root '= "" do ##class(%File).RemoveDirectoryTree(..Root)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^%OPCUA.SecurityRestLive, ^||OPCUA.Tests("securityPrivilege")
	if ..Root '= "" do ##class(%File).RemoveDirectoryTree(..Root)
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("securityPrivilege")
	Quit $$$OK
}

Method Skipped() As %Boolean
{
	if ..Skip = "" Quit 0
	do $$$AssertSkipped(..Skip)
	Quit 1
}

/// A created identity is described by public facts only: no key bytes, no key path
/// content, and the certificate download is the certificate.
Method TestIdentityResponseNoKey()
{
	Quit:..Skipped()
	set ^||OPCUA.Tests("securityPrivilege") = 1
	set tSC = ##class(OPCUA.REST.SecurityService).CreateIdentity({"clientURI": "urn:secrest:test"}, .tRes)
	do $$$AssertStatusOK(tSC, "create")
	do $$$AssertEquals(tRes.ready, 1, "ready")
	do $$$AssertEquals(tRes.clientURI, "urn:secrest:test", "uri")
	set tSC = ##class(OPCUA.REST.SecurityService).Identity(.tStat)
	do $$$AssertStatusOK(tSC, "status")
	set tJson = tRes.%ToJSON()_tStat.%ToJSON()
	do $$$AssertTrue(tJson '[ "PRIVATE KEY", "no PEM key")
	do $$$AssertNotTrue(tStat.%IsDefined("key"), "no key property")
	// The key file's bytes appear nowhere in what the API returns.
	set tKeyHex = ..FileHex(tStat.advanced.keyPath)
	do $$$AssertTrue($Length(tKeyHex) > 100, "the key file was read")
	do $$$AssertTrue($ZConvert(tJson, "U") '[ $Extract(tKeyHex, 21, 100), "no key bytes in the status")

	set tSC = ##class(OPCUA.REST.SecurityService).Certificate("pem", .tData, .tName, .tType)
	do $$$AssertStatusOK(tSC, "pem download")
	do $$$AssertEquals(tType, "application/x-pem-file", "pem content type")
	do $$$AssertEquals(tName, "iris-opcua-client.pem", "pem file name")
	do $$$AssertTrue($Extract(tData, 1, 27) = "-----BEGIN CERTIFICATE-----", "pem text")
	do $$$AssertTrue(tData '[ "PRIVATE", "pem has no key")
	set tSC = ##class(OPCUA.REST.SecurityService).Certificate("", .tData, .tName, .tType)
	do $$$AssertEquals(tType, "application/pkix-cert", "der is the default")
	do $$$AssertEquals($Ascii(tData, 1), 48, "DER starts with SEQUENCE")
	set tSC = ##class(OPCUA.REST.SecurityService).Certificate("pfx", .tData, .tName, .tType)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "unknown format is 400")
}

/// /test with an identity but no pin: identityReady true, serverTrusted false.
Method TestConnectionTestManagedUntrusted()
{
	Quit:..Skipped()
	set ^||OPCUA.Tests("securityPrivilege") = 1
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).Create("urn:secrest:test", 0, "", .tStat), "identity")
	set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": "opc.tcp://x:4840", "securityMode": 3}, .tRes)
	do $$$AssertEquals(tRes.connected, 0, "not connected")
	do $$$AssertEquals(tRes.security.identityReady, 1, "identity ready")
	do $$$AssertEquals(tRes.security.serverTrusted, 0, "server not trusted")
	do $$$AssertEquals(tRes.security.diagnosis.message, ##class(OPCUA.Security.Trust).#NotTrusted, "not-trusted message")
	do $$$AssertEquals(tRes.security.diagnosis.category, "notTrusted", "category")
}

// ==================== helpers ====================

ClassMethod FileHex(pPath As %String) As %String
{
	set tFile = ##class(%Stream.FileBinary).%New()
	do tFile.LinkToFile(pPath)
	set tHex = ""
	while 'tFile.AtEnd {
		set tChunk = tFile.Read(1000)
		for i=1:1:$Length(tChunk) { set tHex = tHex_$ZHex($Ascii(tChunk, i)) }
	}
	Quit tHex
}

}
