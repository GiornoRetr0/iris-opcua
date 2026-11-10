Include (OPCUA.Constants, %occInclude)

/// Offline tests for <method>OPCUA.DataSource.Resolver.ParseNodePath</method>,
/// <method>OPCUA.DataSource.Resolver.ParseDeviceNodePaths</method> and
/// <method>OPCUA.DataSource.Resolver.NameKey</method>. Needs no server.
Class OPCUA.Tests.Unit.ResolverParsingTest Extends %UnitTest.TestCase
{

/// Nodepath parsing needs no server.
Method TestParsing()
{
    // --- single forms ---
    do ..ParseOne("ns=2;s=Plant.AC1", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals(tNS, 2, "ns=2;s=Plant.AC1 → ns")
    do $$$AssertEquals(tId, "Plant.AC1", "ns=2;s=Plant.AC1 → id")
    do $$$AssertEquals(tType, $$$OpcuaNodeIdTypeString, "ns=2;s=Plant.AC1 → idType")

    do ..ParseOne("ns=2;i=1047", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals(tNS, 2, "ns=2;i=1047 → ns")
    do $$$AssertEquals(tId, 1047, "ns=2;i=1047 → id")
    do $$$AssertEquals(tType, $$$OpcuaNodeIdTypeNumeric, "ns=2;i=1047 → idType")

    do ..ParseOne("i=85", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals(tNS, 0, "i=85 defaults to ns 0")
    do $$$AssertEquals(tId, 85, "i=85 → id")

    // A string identifier may itself contain a semicolon-free path with dots/slashes
    do ..ParseOne("ns=1;s=SA1", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals(tId, "SA1", "ns=1;s=SA1 → id")

    // --- rejected forms ---
    do ..ParseOne("/Plant/AC1", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals((tErr '= ""), 1, "browse-path form is rejected")

    do ..ParseOne("garbage", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals((tErr '= ""), 1, "garbage is rejected")

    do ..ParseOne("ns=x;s=Foo", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals((tErr '= ""), 1, "non-numeric namespace is rejected")

    do ..ParseOne("ns=2;i=notanumber", .tNS, .tId, .tType, .tErr)
    do $$$AssertEquals((tErr '= ""), 1, "non-numeric i= is rejected")

    // --- multi-line setting, labels, comments, blank lines ---
    set tSetting = "ns=1;s=SA1|First"_$Char(10)_""_$Char(10)_"# a comment"_$Char(10)_"ns=1;s=SA2"
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do $$$AssertEquals($$$ISOK(tSC), 1, "multi-line parse succeeds")
    do $$$AssertEquals($LL(tDevices), 2, "blank + comment lines skipped → 2 devices")
    do $$$AssertEquals($LI($LI(tDevices, 1), 4), "First", "explicit label is used")
    do $$$AssertEquals($LI($LI(tDevices, 2), 4), "ns=1;s=SA2", "label defaults to the nodepath")

    // CRLF line endings (a Portal textarea may submit these)
    set tSetting = "ns=1;s=SA1"_$Char(13, 10)_"ns=1;s=SA2"
    do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do $$$AssertEquals($LL(tDevices), 2, "CRLF line endings handled")

    // A bad line is reported but does not sink the good ones
    set tSetting = "ns=1;s=SA1"_$Char(10)_"garbage"_$Char(10)_"ns=1;s=SA2"
    do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do $$$AssertEquals($LL(tDevices), 2, "good lines survive a bad line")
    do $$$AssertEquals($LL(tErrors), 1, "bad line is reported")

    // An entirely unusable setting is an error
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("", .tDevices, .tErrors)
    do $$$AssertEquals($$$ISERR(tSC), 1, "empty setting is an error")

    // --- name keys: exact, nothing stripped ---
    // A digits-only name once keyed to "" and broke the whole device's browse.
    do $$$AssertEquals(##class(OPCUA.DataSource.Resolver).NameKey("42"), "42", "NameKey keeps a digits-only name")
    do $$$AssertEquals(##class(OPCUA.DataSource.Resolver).NameKey("10:30 Shift"), "10:30 Shift", "NameKey keeps a leading N: part")
    do $$$AssertEquals(##class(OPCUA.DataSource.Resolver).NameKey("Temp")=##class(OPCUA.DataSource.Resolver).NameKey("temp"), 0, "NameKey is case-sensitive")
}

/// Parse one path, flattening the status into an error string for readability.
ClassMethod ParseOne(pPath As %String, Output pNS, Output pId, Output pType, Output pErr) [ Private ]
{
    set pErr = ""
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseNodePath(pPath, .pNS, .pId, .pType)
    if $$$ISERR(tSC) set pErr = $System.Status.GetOneErrorText(tSC)
}

}
