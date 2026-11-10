Include %occInclude

/// Offline tests of OPCUA.Security.Identity: the pure validation (Evaluate) and the
/// replacement guard, against a redirected store.
Class OPCUA.Tests.Unit.SecurityIdentityTest Extends %UnitTest.TestCase
{

Parameter Now = "2026-11-10 12:00:00";

Method OnBeforeAllTests() As %Status
{
	set ^%OPCUA.Security.Override("global") = "^OPCUA.Tests.IdentityUnit"
	set ^%OPCUA.Security.Override("root") = "/tmp/opcua-identity-unit-"_$job
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	kill ^%OPCUA.Security.Override
	kill ^OPCUA.Tests.IdentityUnit
	do ##class(%File).RemoveDirectoryTree("/tmp/opcua-identity-unit-"_$job)
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^OPCUA.Tests.IdentityUnit
	Quit $$$OK
}

/// A healthy certificate description.
ClassMethod Info() As %DynamicObject
{
	Quit {
		"notBefore": "2026-01-01 00:00:00",
		"notAfter": "2030-01-01 00:00:00",
		"sanUris": ["urn:test:opcua"],
		"keyType": "RSA",
		"keyBits": 2048,
		"keyUsage": ["digitalSignature", "keyEncipherment"],
		"sha256": "AA:BB"
	}
}

Method Codes(pArr As %DynamicArray) As %String
{
	set tCodes = ","
	set tIt = pArr.%GetIterator()
	while tIt.%GetNext(.k, .v) { set tCodes = tCodes_v.code_"," }
	Quit tCodes
}

Method TestEvaluateHealthy()
{
	do ##class(OPCUA.Security.Identity).Evaluate(..Info(), 1, ..#Now, .e, .w)
	do $$$AssertEquals(e.%Size(), 0, "no errors")
	do $$$AssertEquals(w.%Size(), 0, "no warnings")
}

Method TestEvaluateUnparseable()
{
	do ##class(OPCUA.Security.Identity).Evaluate("", "", ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",unparseable,", "unparseable")
}

Method TestEvaluateExpired()
{
	set i = ..Info(), i.notAfter = "2026-11-09 23:59:59"
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",expired,", "expired")
	do $$$AssertNotTrue(..Codes(w) [ "expiresSoon", "no soon warning on top of expired")
}

Method TestEvaluateNotYetValid()
{
	set i = ..Info(), i.notBefore = "2026-11-10 12:00:01"
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",notYetValid,", "notYetValid")
}

Method TestEvaluateExpiresSoon()
{
	set i = ..Info(), i.notAfter = "2026-12-09 12:00:00"
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertEquals(e.%Size(), 0, "29 days is still usable")
	do $$$AssertTrue(..Codes(w) [ ",expiresSoon,", "29 days warns")
	set i.notAfter = "2026-12-11 12:00:00"
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertNotTrue(..Codes(w) [ "expiresSoon", "31 days does not warn")
}

Method TestEvaluateNoUri()
{
	set i = ..Info(), i.sanUris = []
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",noUri,", "noUri")
}

Method TestEvaluateKeyMismatch()
{
	do ##class(OPCUA.Security.Identity).Evaluate(..Info(), 0, ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",keyMismatch,", "keyMismatch")
	do ##class(OPCUA.Security.Identity).Evaluate(..Info(), "", ..#Now, .e, .w)
	do $$$AssertNotTrue(..Codes(e) [ "keyMismatch", "an unchecked key is not a mismatch")
}

Method TestEvaluateNotRsa()
{
	set i = ..Info(), i.keyType = "EC"
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertTrue(..Codes(e) [ ",notRsa,", "notRsa")
}

Method TestEvaluateWarnings()
{
	set i = ..Info(), i.keyBits = 1024, i.keyUsage = ["digitalSignature"]
	do ##class(OPCUA.Security.Identity).Evaluate(i, 1, ..#Now, .e, .w)
	do $$$AssertEquals(e.%Size(), 0, "still usable")
	do $$$AssertTrue(..Codes(w) [ ",weakKey,", "weakKey")
	do $$$AssertTrue(..Codes(w) [ ",keyUsage,", "keyUsage")
	do $$$AssertTrue(w.%Get(0).message '= "", "every entry has a message")
}

Method Configure(pFp As %String = "AA:BB")
{
	do ##class(OPCUA.Security.Store).SaveIdentity({"source": "files", "certPath": "/nonexistent/c.der", "keyPath": "/nonexistent/k.der", "clientURI": "urn:t:x", "fingerprint": (pFp)})
}

Method TestGuardNoReplace()
{
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).GuardReplace(0, ""), "nothing configured: free")
	do ..Configure()
	set tSC = ##class(OPCUA.Security.Identity).GuardReplace(0, "")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "409")
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), "An IRIS client identity is already configured. Replacing it means every OPC UA server must approve the new certificate.", "text")
	do $$$AssertStatusOK(##class(OPCUA.Security.Identity).GuardReplace(1, "AA:BB"), "confirmed replace")
}

Method TestReplaceStaleFingerprint()
{
	do ..Configure()
	set tBefore = ^OPCUA.Tests.IdentityUnit("identity")
	set tSC = ##class(OPCUA.Security.Identity).GuardReplace(1, "CC:DD")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "409")
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), "The client identity changed since you reviewed it. Reload and review the replacement again.", "text")
	set tSC = ##class(OPCUA.Security.Identity).Create("", 1, "CC:DD", .tStatus)
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "Create refuses too")
	do $$$AssertEquals(^OPCUA.Tests.IdentityUnit("identity"), tBefore, "store untouched")
	do $$$AssertNotTrue(##class(%File).DirectoryExists("/tmp/opcua-identity-unit-"_$job_"/own"), "no files written")
}

Method TestStatusNeverHasKey()
{
	do ..Configure()
	set tSC = ##class(OPCUA.Security.Identity).Status(.tStatus)
	do $$$AssertStatusOK(tSC, "status")
	set tJson = tStatus.%ToJSON()
	do $$$AssertNotTrue(tJson [ "PRIVATE KEY", "no PEM key")
	do $$$AssertEquals(tStatus.configured, 1, "configured")
	do $$$AssertEquals(tStatus.ready, 0, "files missing: not ready")
	do $$$AssertEquals(tStatus.errors.%Get(0).code, "unreadable", "unreadable")
	do $$$AssertEquals(tStatus.fingerprint, "AA:BB", "falls back to the stored fingerprint")
	do $$$AssertEquals(tStatus.advanced.keyPath, "/nonexistent/k.der", "key path (not bytes) in advanced")
}

Method TestActiveRefusesWhenNotSetUp()
{
	set tSC = ##class(OPCUA.Security.Identity).Active(.c, .k, .u)
	do $$$AssertEquals(##class(OPCUA.REST.Error).Message(tSC), "No IRIS client identity is set up. Open Settings "_$char(8250)_" OPC UA Security to create one.", "message")
	do ..Configure()
	set tSC = ##class(OPCUA.Security.Identity).Active(.c, .k, .u)
	do $$$AssertTrue(##class(OPCUA.REST.Error).Message(tSC) [ "The IRIS client identity is not usable: ", "not usable")
}

}
