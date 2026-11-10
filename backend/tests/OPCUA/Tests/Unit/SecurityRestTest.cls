Include %occInclude

/// Offline tests for the managed Sign &amp; Encrypt REST layer: the privilege gate,
/// the identity responses, the import validation, how deploy writes managed and
/// manual pipelines, and the masking of key material in the error log. The store is
/// redirected to a test global and directory; deploy runs on a throwaway production.
Class OPCUA.Tests.Unit.SecurityRestTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.SecRestProduction";

Parameter Schema = "OPCUA.Tests.Tmp.SecRestSchema";

Property Root As %String;

Method OnBeforeAllTests() As %Status
{
	set ..Root = ##class(%File).NormalizeDirectory("/tmp/opcua-secrest-unit-"_$Job)
	do ..Cleanup()
	kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityRestTest
	set ^%OPCUA.Security.Override("global") = "^%OPCUA.SecurityRestTest"
	set ^%OPCUA.Security.Override("root") = ..Root
	set tSC = ..CreateSchema()
	Quit:$$$ISERR(tSC) tSC
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_"""></Production>")
	do tDef.XDatas.Insert(tX)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	set tSC = $System.OBJ.Compile(..#Production, "ck-d")
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(Ens.Config.Production).LoadFromClass(..#Production)
}

Method OnAfterAllTests() As %Status
{
	kill ^%OPCUA.Security.Override, ^%OPCUA.SecurityRestTest
	kill ^||OPCUA.Tests("production"), ^||OPCUA.Tests("securityPrivilege")
	do ..Cleanup()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^%OPCUA.SecurityRestTest, ^||OPCUA.Tests("securityPrivilege")
	do ##class(%File).RemoveDirectoryTree(..Root)
	set ^||OPCUA.Tests("production") = ..#Production
	Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("securityPrivilege")
	Quit $$$OK
}

/// Without %Admin_Secure:USE every method answers 403 with the ruled text, and
/// does nothing.
Method TestForbiddenWithoutPrivilege()
{
	set ^||OPCUA.Tests("securityPrivilege") = 0
	set tText = "Managing OPC UA certificates needs the %Admin_Secure:USE privilege (a SuperUser account)."
	set tSvc = "OPCUA.REST.SecurityService"
	for tCall = "Identity", "Servers" {
		set tSC = $classmethod(tSvc, tCall, .tRes)
		do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 403, tCall_" is 403")
		do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), tText, tCall_" message")
	}
	for tCall = "CreateIdentity", "ImportIdentity", "UseFiles", "Inspect", "Trust", "Issuer" {
		set tSC = $classmethod(tSvc, tCall, {"url": "opc.tcp://x:4840"}, .tRes)
		do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 403, tCall_" is 403")
		do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), tText, tCall_" message")
	}
	set tSC = ##class(OPCUA.REST.SecurityService).Certificate("der", .tData, .tName, .tType)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 403, "Certificate is 403")
	set tSC = ##class(OPCUA.REST.SecurityService).RemoveServer("0123456789abcdef", .tRes)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 403, "RemoveServer is 403")
	do $$$AssertEquals($Data(^%OPCUA.SecurityRestTest), 0, "nothing was stored")
	do $$$AssertEquals(##class(%File).DirectoryExists(..Root), 0, "no directory was made")
}

/// A created identity is described by public facts only: no key bytes, no key path
/// content, and the certificate download is the certificate.
Method TestIdentityResponseNoKey()
{
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

/// A certificate with a key and a PKCS#12 file together is refused before anything
/// is read.
Method TestImportBothFormsRejected()
{
	set ^||OPCUA.Tests("securityPrivilege") = 1
	for tField = "certificate", "key" {
		set tBody = {"pkcs12": "3082"}
		do tBody.%Set(tField, "3082")
		set tSC = ##class(OPCUA.REST.SecurityService).ImportIdentity(tBody, .tRes)
		do $$$AssertStatusNotOK(tSC, "pkcs12 with "_tField_" refused")
		do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "400")
	}
	set tSC = ##class(OPCUA.REST.SecurityService).ImportIdentity({}, .tRes)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "nothing at all is 400")
	do $$$AssertEquals($Data(^%OPCUA.SecurityRestTest), 0, "nothing stored")
}

/// A key of the wrong shape is a 400 and an unknown one a 404, never a 500.
Method TestRemoveServerKeys()
{
	set ^||OPCUA.Tests("securityPrivilege") = 1
	for tKey = "../etc", "x", "ZZZZZZZZZZZZZZZZ" {
		set tSC = ##class(OPCUA.REST.SecurityService).RemoveServer(tKey, .tRes)
		do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "'"_tKey_"' is 400")
	}
	set tSC = ##class(OPCUA.REST.SecurityService).RemoveServer("0123456789abcdef", .tRes)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 404, "unknown key is 404")
}

/// Missing url is a 400; a raw discovery failure becomes a 502 with the network text.
Method TestMapFailure()
{
	set ^||OPCUA.Tests("securityPrivilege") = 1
	set tSC = ##class(OPCUA.REST.SecurityService).Inspect({}, .tRes)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "no url is 400")
	set tRaw = $$$ERROR($$$GeneralError, "Other error : BadConnectionClosed")
	set tSC = ##class(OPCUA.REST.SecurityService).MapFailure(tRaw)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 502, "raw failure is 502")
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "IRIS could not reach the OPC UA server", "network message")
	set tCarried = ##class(OPCUA.REST.Error).Conflict("stale")
	do $$$AssertEquals(##class(OPCUA.REST.SecurityService).MapFailure(tCarried), tCarried, "carried statuses pass through")
}

/// A managed pipeline carries only SecurityMode=3: nothing that would make it manual.
Method TestDeployManagedWritesOnlyMode()
{
	set tSC = ##class(OPCUA.REST.DeployService).AddServiceItem({"url": "opc.tcp://plc", "securityMode": 3, "clientURI": "urn:secuac", "trustDir": "/t/", "crlDir": "/c/"}, ..#Schema, "SecRestManaged", "polling", "i=85")
	do $$$AssertStatusOK(tSC, "added")
	do $$$AssertEquals(..Setting("SecRestManaged", "SecurityMode"), 3, "SecurityMode=3")
	for tName = "ClientURI", "PublicCertificate", "PrivateKey", "TrustListDir", "RevocationListDir" {
		do $$$AssertEquals(..HasSetting("SecRestManaged", tName), 0, tName_" is not written")
	}
}

/// A manual pipeline keeps every path setting.
Method TestDeployManualKeepsPaths()
{
	set tSC = ##class(OPCUA.REST.DeployService).AddServiceItem({"url": "opc.tcp://plc", "securityMode": 3, "clientURI": "urn:secuac", "certPath": "/c.der", "keyPath": "/k.der", "trustDir": "/t/", "crlDir": "/r/"}, ..#Schema, "SecRestManual", "polling", "i=85")
	do $$$AssertStatusOK(tSC, "added")
	do $$$AssertEquals(..Setting("SecRestManual", "SecurityMode"), 3, "SecurityMode=3")
	do $$$AssertEquals(..Setting("SecRestManual", "ClientURI"), "urn:secuac", "ClientURI")
	do $$$AssertEquals(..Setting("SecRestManual", "PublicCertificate"), "/c.der", "PublicCertificate")
	do $$$AssertEquals(..Setting("SecRestManual", "PrivateKey"), "/k.der", "PrivateKey")
	do $$$AssertEquals(..Setting("SecRestManual", "TrustListDir"), "/t/", "TrustListDir")
	do $$$AssertEquals(..Setting("SecRestManual", "RevocationListDir"), "/r/", "RevocationListDir")
}

/// Mode 1 writes no security settings at all.
Method TestDeployModeOneNoSecurity()
{
	set tSC = ##class(OPCUA.REST.DeployService).AddServiceItem({"url": "opc.tcp://plc", "securityMode": 1, "certPath": "/c.der"}, ..#Schema, "SecRestOne", "polling", "i=85")
	do $$$AssertStatusOK(tSC, "added")
	do $$$AssertEquals(..HasSetting("SecRestOne", "SecurityMode"), 0, "no SecurityMode")
	do $$$AssertEquals(..HasSetting("SecRestOne", "PublicCertificate"), 0, "no certificate")
}

/// /test for a managed connection without an identity reports the refusal in the
/// security block, not as a server error and not by trying mode 1.
Method TestConnectionTestManagedRefused()
{
	set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": "opc.tcp://x:4840", "securityMode": 3}, .tRes)
	do $$$AssertStatusOK(tSC, "not an error status")
	do $$$AssertEquals(tRes.connected, 0, "not connected")
	do $$$AssertEquals(tRes.security.managed, 1, "managed")
	do $$$AssertEquals(tRes.security.identityReady, 0, "no identity")
	do $$$AssertEquals(tRes.security.serverTrusted, 0, "not trusted")
	do $$$AssertTrue(tRes.security.diagnosis.message [ "No IRIS client identity", "diagnosis names the cause")
	do $$$AssertEquals(tRes.error, tRes.security.diagnosis.message, "same text as error")
	do $$$AssertEquals(tRes.%IsDefined("securityMode"), 0, "no securityMode echoed on failure")

	// Manual and mode 1 add no security block.
	set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": "opc.tcp://x:4840", "securityMode": 3, "certPath": "/nope.der", "keyPath": "/nope.key"}, .tRes)
	do $$$AssertEquals(tRes.%IsDefined("security"), 0, "manual has no security block")
}

/// /test with an identity but no pin: identityReady true, serverTrusted false.
Method TestConnectionTestManagedUntrusted()
{
	set ^||OPCUA.Tests("securityPrivilege") = 1
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).Create("urn:secrest:test", 0, "", .tStat), "identity")
	set tSC = ##class(OPCUA.REST.ConnectionService).Test({"url": "opc.tcp://x:4840", "securityMode": 3}, .tRes)
	do $$$AssertEquals(tRes.connected, 0, "not connected")
	do $$$AssertEquals(tRes.security.identityReady, 1, "identity ready")
	do $$$AssertEquals(tRes.security.serverTrusted, 0, "server not trusted")
	do $$$AssertEquals(tRes.security.diagnosis.message, ##class(OPCUA.Security.Trust).#NotTrusted, "not-trusted message")
}

/// The request's key, pkcs12 and password values never reach the event log text.
Method TestLogMasksKey()
{
	set tBody = {"certificate": "AABBCC", "key": "DEADBEEFCAFE0123", "pkcs12": "FACEFEED0042", "password": "hunter2xx", "nested": {"key": "FEEDFACE9999"}}
	new %request
	set %request = ##class(%CSP.Request).%New()
	set %request.Content = ##class(%Stream.TmpCharacter).%New()
	do %request.Content.Write(tBody.%ToJSON())
	set %request.Method = "POST"
	set %request.URL = "/csp/opcua/api/security/identity/import"
	do ##class(OPCUA.REST.Handler).RequestSecrets(.tSecrets)
	set tText = "failed: DEADBEEFCAFE0123 and FACEFEED0042 with hunter2xx also FEEDFACE9999 but AABBCC stays"
	set tMasked = tText
	set tS = ""
	for {
		set tS = $Order(tSecrets(tS), -1)
		Quit:tS=""
		set tMasked = $Replace(tMasked, tS, "*****")
	}
	do $$$AssertEquals(tMasked, "failed: ***** and ***** with ***** also ***** but AABBCC stays", "secrets masked, the certificate is public")
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

ClassMethod Item(pName As %String) As Ens.Config.Item
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	Quit:'$IsObject(tProd) ""
	Quit ##class(OPCUA.REST.ProductionEdit).FindItem(tProd, pName)
}

ClassMethod HasSetting(pName As %String, pSetting As %String) As %Boolean
{
	set tItem = ..Item(pName)
	Quit:'$IsObject(tItem) 0
	for i=1:1:tItem.Settings.Count() {
		if tItem.Settings.GetAt(i).Name = pSetting Return 1
	}
	Quit 0
}

ClassMethod Setting(pName As %String, pSetting As %String) As %String
{
	set tItem = ..Item(pName)
	Quit:'$IsObject(tItem) ""
	for i=1:1:tItem.Settings.Count() {
		if tItem.Settings.GetAt(i).Name = pSetting Return tItem.Settings.GetAt(i).Value
	}
	Quit ""
}

ClassMethod CreateSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Schema)
	set tDef.Super = "OPCUA.DataSource.DeviceSchema,%Persistent"
	set tDef.Description = "Throwaway schema for SecurityRestTest"
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE"
	set tParam.Default = "TmpSecRest"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE"
	set tParam.Default = "1"
	do tDef.Parameters.Insert(tParam)
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "Temperature"
	set tProp.Type = "OPCUA.Types.DoubleDataValue"
	do tProp.Parameters.SetAt("Temperature", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#Schema, "ck-d")
}

Method Cleanup()
{
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
	if ##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema) {
		Try { do $classmethod(..#Schema, "%KillExtent") } Catch {}
		do $System.OBJ.Delete(..#Schema, "-d")
	}
	kill ^OPCUA.DataSource(..#Schema)
	do ##class(%File).RemoveDirectoryTree(..Root)
}

}
