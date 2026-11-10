Include %occInclude

/// Live tests that the certificate store is closed to everyone but the IRIS account,
/// with the real native library (connector 0.5.1, <tt>zfPkiProtectPath</tt>).
///
/// Unix: directories are 0700 and keys 0600, and ProtectPath puts a loosened tree back.
/// Windows: root, folders and key carry a PROTECTED DACL naming only the process
/// user, SYSTEM and BUILTIN\Administrators; an extra Users grant is removed the next
/// time the store is touched. The Windows test reads the DACL back as SDDL with
/// <tt>icacls /save</tt> (SIDs, so it does not depend on the Windows language) and is
/// skipped on Unix; the Unix test is skipped on Windows. The store is redirected with
/// ^%OPCUA.Security.Override, removed afterwards.
Class OPCUA.Tests.Live.StoreProtectionLiveTest Extends %UnitTest.TestCase
{

Property Base As %String;

Property Skip As %String;

Method OnBeforeAllTests() As %Status
{
	set ..Skip = ""
	if '##class(OPCUA.Utils).SupportsProtect() {
		set ..Skip = "connector 0.5.1 (zfPkiProtectPath) is not available"
		Quit $$$OK
	}
	set tTemp = $select($$$isWINDOWS: ##class(%File).GetDirectory(##class(%File).TempFilename()), 1: "/tmp/")
	set ..Base = ##class(%File).NormalizeDirectory(tTemp_"opcua-protect-live-"_$job)
	do ##class(%File).RemoveDirectoryTree(..Base)
	do ##class(%File).CreateDirectoryChain(..Base)
	set ^%OPCUA.Security.Override("root") = ..Base_"store"
	set ^%OPCUA.Security.Override("global") = "^OPCUA.Tests.ProtectLive"
	Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
	kill ^%OPCUA.Security.Override
	kill ^OPCUA.Tests.ProtectLive
	if ..Base '= "" do ##class(%File).RemoveDirectoryTree(..Base)
	Quit $$$OK
}

Method Skipped(pWindows As %Boolean) As %Boolean
{
	if ..Skip '= "" {
		do $$$AssertSkipped(..Skip)
		Quit 1
	}
	if pWindows '= $$$isWINDOWS {
		do $$$AssertSkipped($select(pWindows: "Windows-only test", 1: "Unix-only test"))
		Quit 1
	}
	Quit 0
}

/// Creates a native identity in own/ of the redirected store.
Method MakeKey(Output pOwn As %String, Output pKey As %String) As %Status
{
	set tStore = "OPCUA.Security.Store"
	set pOwn = $classmethod(tStore, "Dir", "own")
	set tSC = $classmethod(tStore, "EnsureDirs", pOwn)
	Quit:$$$ISERR(tSC) tSC
	set pKey = pOwn_"client.key.der"
	Quit ##class(OPCUA.Security.Native).CreateIdentity(pOwn_"client.cert.der", pKey, "urn:test:protect", "testhost", "Protect Test")
}

Method Mode(pPath As %String) As %Integer
{
	Quit ##class(%File).Attributes($extract(pPath, 1, $length(pPath) - $select($extract(pPath, *) = "/": 1, 1: 0))) # 512
}

Method TestUnixModes()
{
	Quit:..Skipped(0)
	set tSC = ..MakeKey(.tOwn, .tKey)
	do $$$AssertStatusOK(tSC, "EnsureDirs and create identity")
	Quit:$$$ISERR(tSC)
	set tRoot = ##class(OPCUA.Security.Store).Root()
	do $$$AssertEquals(..Mode(tRoot), 448, "root is 0700")
	do $$$AssertEquals(..Mode(tOwn), 448, "own/ is 0700")
	do $$$AssertEquals(..Mode(tKey), 384, "key is 0600")
	// loosen everything, then ProtectPath restores the whole tree
	do ##class(%File).SetAttributes($extract(tRoot, 1, *-1), 493)
	do ##class(%File).SetAttributes($extract(tOwn, 1, *-1), 493)
	do ##class(%File).SetAttributes(tKey, 420)
	do $$$AssertStatusOK(##class(OPCUA.Security.Native).ProtectPath($extract(tRoot, 1, *-1), 1, 1), "ProtectPath recursive")
	do $$$AssertEquals(..Mode(tRoot), 448, "root back to 0700")
	do $$$AssertEquals(..Mode(tOwn), 448, "own/ back to 0700")
	do $$$AssertEquals(..Mode(tKey), 384, "key back to 0600")
	do $$$AssertTrue('##class(OPCUA.Security.Native).ProtectPath(tRoot_"missing", 1, 1), "a missing path is an error")
}

/// The SDDL of a path, from <tt>icacls /save</tt> (a UTF-16 file: path line, SDDL line).
Method Sddl(pPath As %String) As %String
{
	set tOut = ..Base_"acl-"_$increment(^||n)_".txt"
	set tRC = $ZF(-100, "/SHELL /STDOUT=""NUL"" /STDERR=""NUL""", "icacls", """"_$extract(pPath, 1, $length(pPath) - $select($extract(pPath, *) = "\": 1, 1: 0))_"""", "/save", """"_tOut_"""", "/q")
	Quit:tRC'=0 ""
	set tFile = ##class(%Stream.FileBinary).%New()
	do tFile.LinkToFile(tOut)
	set tData = $translate(tFile.Read(32000), $char(0, 255, 254))
	kill tFile
	do ##class(%File).Delete(tOut)
	// the first line is the path (which may itself contain "D:"); the SDDL line starts with D:
	set tData = $translate(tData, $char(13))
	for i = 1:1:$length(tData, $char(10)) {
		set tLine = $zstrip($piece(tData, $char(10), i), "<>W")
		if $extract(tLine, 1, 2) = "D:" Quit
		set tLine = ""
	}
	Quit tLine
}

/// The SID of the account running the test (this process), from whoami.
Method UserSid() As %String
{
	set tOut = ..Base_"whoami.txt"
	set tRC = $ZF(-100, "/SHELL /STDOUT="""_tOut_""" /STDERR=""NUL""", "whoami", "/user", "/fo", "csv", "/nh")
	Quit:tRC'=0 ""
	set tFile = ##class(%Stream.FileCharacter).%New()
	do tFile.LinkToFile(tOut)
	set tLine = tFile.ReadLine()
	kill tFile
	Quit $translate($piece(tLine, ",", 2), """ "_$char(13, 10))
}

/// Checks one path's DACL; the three expected principals only, and protected.
Method CheckProtected(pPath As %String, pUserSid As %String)
{
	set tSddl = ..Sddl(pPath)
	do $$$AssertTrue(tSddl '= "", "read the DACL of "_pPath)
	Quit:tSddl=""
	// "D:P(...)": the P right after D: is SE_DACL_PROTECTED (no inherited ACEs)
	do $$$AssertEquals($extract(tSddl, 3), "P", "DACL is protected on "_pPath_": "_tSddl)
	set tAllowed = $listbuild("SY", "BA", "S-1-5-18", "S-1-5-32-544", pUserSid)
	set tForbidden = $listbuild("BU", "AU", "WD", "IU", "NS", "S-1-5-32-545", "S-1-5-11", "S-1-1-0")
	set tAces = 0, tSawUser = 0
	set tAcl = $piece($piece(tSddl, "S:", 1), "(", 2, *)
	for i = 1:1:$length(tAcl, "(") {
		set tAce = $piece($piece(tAcl, "(", i), ")", 1)
		continue:tAce=""
		set tAces = tAces + 1
		set tSid = $piece(tAce, ";", 6)
		do $$$AssertTrue($listfind(tAllowed, tSid) > 0, "principal "_tSid_" is one of user/SYSTEM/Administrators on "_pPath)
		do $$$AssertEquals($listfind(tForbidden, tSid), 0, "no Users/Authenticated Users/Everyone ACE on "_pPath)
		if tSid = pUserSid set tSawUser = 1
	}
	do $$$AssertTrue((tAces >= 2) && (tAces <= 3), "2-3 ACEs on "_pPath_", got "_tAces)
	do $$$AssertTrue(tSawUser || (pUserSid = "S-1-5-18") || (pUserSid = "S-1-5-32-544"), "the IRIS account has an ACE on "_pPath)
}

Method TestWindowsDacl()
{
	Quit:..Skipped(1)
	set tUser = ..UserSid()
	do $$$AssertTrue(tUser '= "", "found the account SID")
	Quit:tUser=""
	set tSC = ..MakeKey(.tOwn, .tKey)
	do $$$AssertStatusOK(tSC, "EnsureDirs and create identity")
	Quit:$$$ISERR(tSC)
	set tRoot = ##class(OPCUA.Security.Store).Root()
	do ..CheckProtected(tRoot, tUser)
	do ..CheckProtected(tOwn, tUser)
	do ..CheckProtected(tKey, tUser)
	// an existing, looser tree is tightened the next time the store is touched
	set tRC = $ZF(-100, "/SHELL /STDOUT=""NUL"" /STDERR=""NUL""", "icacls", """"_$extract(tRoot, 1, *-1)_"""", "/grant", "*S-1-5-32-545:(OI)(CI)(M)", "/t", "/q")
	do $$$AssertEquals(tRC, 0, "test setup: granted Users on the tree")
	do $$$AssertStatusOK(##class(OPCUA.Security.Store).EnsureDirs(tOwn), "EnsureDirs again")
	do ..CheckProtected(tRoot, tUser)
	do ..CheckProtected(tKey, tUser)
}

}
