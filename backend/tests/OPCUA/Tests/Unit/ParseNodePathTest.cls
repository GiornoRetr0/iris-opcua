Include (OPCUA.Constants, %occInclude)

/// Edge cases of <method>OPCUA.DataSource.Resolver.ParseNodePath</method> and the
/// line handling around it in <method>OPCUA.DataSource.Resolver.ParseDeviceNodePaths</method>.
/// The webapp's <tt>parseNodeId()</tt> mirrors ParseNodePath, so both must accept
/// and reject the same text. Needs no server.
Class OPCUA.Tests.Unit.ParseNodePathTest Extends %UnitTest.TestCase
{

Method TestStringId()
{
    do ..Parse("ns=2;s=AC1", .tSC, .tNS, .tId, .tType)
    do $$$AssertStatusOK(tSC, "ns=2;s=AC1 parses")
    do $$$AssertEquals(tNS, 2, "namespace 2")
    do $$$AssertEquals(tId, "AC1", "string id AC1")
    do $$$AssertEquals(tType, $$$OpcuaNodeIdTypeString, "string id type")
}

Method TestNumericId()
{
    do ..Parse("ns=2;i=42", .tSC, .tNS, .tId, .tType)
    do $$$AssertStatusOK(tSC, "ns=2;i=42 parses")
    do $$$AssertEquals(tNS, 2, "namespace 2")
    do $$$AssertEquals(tId, 42, "numeric id 42")
    do $$$AssertEquals(tType, $$$OpcuaNodeIdTypeNumeric, "numeric id type")
}

/// Without ns= the namespace is 0.
Method TestDefaultNamespace()
{
    do ..Parse("s=AC1", .tSC, .tNS, .tId, .tType)
    do $$$AssertStatusOK(tSC, "s=AC1 parses")
    do $$$AssertEquals(tNS, 0, "namespace defaults to 0")
    do $$$AssertEquals(tId, "AC1", "string id AC1")
}

Method TestEmptyStringId()
{
    do ..Parse("ns=2;s=", .tSC)
    do $$$AssertStatusNotOK(tSC, "ns=2;s= is rejected")
    do $$$AssertTrue(..Text(tSC) [ "empty string identifier", "error names the empty identifier: "_..Text(tSC))
}

Method TestNonNumericNamespace()
{
    do ..Parse("ns=x;s=A", .tSC)
    do $$$AssertStatusNotOK(tSC, "ns=x;s=A is rejected")
    do $$$AssertTrue(..Text(tSC) [ "namespace must be numeric", "error says the namespace must be numeric: "_..Text(tSC))

    do ..Parse("ns=;s=A", .tSC)
    do $$$AssertStatusNotOK(tSC, "an empty namespace is rejected")
}

/// Only the first semicolon ends the namespace; the identifier keeps the rest.
Method TestSemicolonInId()
{
    do ..Parse("ns=2;s=A;B", .tSC, .tNS, .tId, .tType)
    do $$$AssertStatusOK(tSC, "ns=2;s=A;B parses")
    do $$$AssertEquals(tNS, 2, "namespace 2")
    do $$$AssertEquals(tId, "A;B", "the identifier keeps its semicolon")
}

/// Surrounding whitespace is not part of the nodepath, as in the webapp's
/// parseNodeId(), which trims first. Whitespace inside it still is.
Method TestSurroundingWhitespace()
{
    do ..Parse("  ns=2;s=AC1"_$Char(9)_" ", .tSC, .tNS, .tId, .tType)
    do $$$AssertStatusOK(tSC, "a nodepath with surrounding spaces and a tab parses")
    do $$$AssertEquals(tNS, 2, "namespace 2")
    do $$$AssertEquals(tId, "AC1", "the identifier has no trailing whitespace")

    do ..Parse("ns=2; s=AC1", .tSC)
    do $$$AssertStatusNotOK(tSC, "whitespace after the separator is rejected, as in parseNodeId()")

    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("   ns=2;s=AC1   |   Line 1   ", .tDevices, .tErrors)
    do $$$AssertStatusOK(tSC, "a padded device line parses")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 1), 2), "AC1", "device id trimmed")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 1), 4), "Line 1", "label trimmed")
}

/// "|label" belongs to the device line, not to the nodepath.
Method TestLabelSuffix()
{
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("ns=2;s=AC1|Line 1"_$Char(10)_"ns=2;s=AC2|"_$Char(10)_"ns=2;s=AC3|a|b", .tDevices, .tErrors)
    do $$$AssertStatusOK(tSC, "labelled lines parse")
    do $$$AssertEquals($ListLength(tDevices), 3, "three devices")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 1), 2), "AC1", "the label is not part of the id")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 1), 4), "Line 1", "explicit label")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 2), 4), "ns=2;s=AC2", "an empty label falls back to the nodepath")
    do $$$AssertEquals($ListGet($ListGet(tDevices, 3), 4), "a|b", "everything after the first bar is the label")

    // ParseNodePath alone has no label syntax: the bar is part of a string id.
    do ..Parse("ns=2;s=AC1|Line 1", .tSC, , .tId)
    do $$$AssertEquals(tId, "AC1|Line 1", "ParseNodePath keeps a bar in a string id")
}

/// "ns=2" with no ";" has a numeric-looking namespace and no identifier. It must
/// be an error, not namespace 2 with an empty id.
Method TestNamespaceWithoutSeparator()
{
    do ..Parse("ns=2", .tSC, .tNS, .tId)
    do $$$AssertStatusNotOK(tSC, "ns=2 is rejected")
    do $$$AssertTrue(..Text(tSC) [ "missing node identifier", "error says the identifier is missing: "_..Text(tSC))

    do ..Parse("ns=2 ;s=A", .tSC)
    do $$$AssertStatusNotOK(tSC, "a space before the separator is rejected")
}

ClassMethod Parse(pPath As %String, Output pSC As %Status, Output pNS, Output pId, Output pType)
{
    set pSC = ##class(OPCUA.DataSource.Resolver).ParseNodePath(pPath, .pNS, .pId, .pType)
}

ClassMethod Text(pSC As %Status) As %String
{
    Quit $Select($$$ISERR(pSC):$System.Status.GetOneErrorText(pSC), 1:"")
}

}
