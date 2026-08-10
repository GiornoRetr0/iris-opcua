Include (OPCUA.Constants, %occInclude)

/// Tests for <class>OPCUA.DataSource.Resolver</class>: nodepath parsing (offline)
/// and name-based resolution against a live OPC UA server.
///
/// Run against the docker-compose mock server:
///   zn "OPCUA"
///   write ##class(OPCUA.Tests.ResolverTest).Run("opc.tcp://plc")
///
/// Unlike <class>OPCUA.Tests.DataTest</class> (which needs the public
/// opcuaserver.com), this suite only needs the local plc container.
Class OPCUA.Tests.ResolverTest
{

/// Run the whole suite. Returns 1 if every test passed.
ClassMethod Run(pURL As %String = "opc.tcp://plc") As %Boolean
{
    set tPass = 0, tFail = 0

    write !, "=== Resolver: nodepath parsing (offline) ===", !
    do ..TestParsing(.tPass, .tFail)

    write !, "=== Resolver: live resolution against ", pURL, " ===", !
    do ..TestLiveResolution(pURL, .tPass, .tFail)

    write !, "=== Resolver: nested %SerialObject folders ===", !
    do ..TestNestedResolution(pURL, .tPass, .tFail)

    write !, "=== BrowseService: nodeClass from the C++ layer ===", !
    do ..TestNodeClass(pURL, .tPass, .tFail)

    write !, "=== BrowseService: measured hasChildren ===", !
    do ..TestChildProbe(pURL, .tPass, .tFail)

    write !, "-----------------------------------------", !
    write "passed: ", tPass, "   failed: ", tFail, !
    quit (tFail = 0)
}

/// Assert helper.
ClassMethod Check(pLabel As %String, pGot, pWant, ByRef pPass, ByRef pFail) [ Private ]
{
    if pGot = pWant {
        set pPass = pPass + 1
        write "  ok   ", pLabel, !
    } else {
        set pFail = pFail + 1
        write "  FAIL ", pLabel, " — got [", pGot, "] want [", pWant, "]", !
    }
}

/// Nodepath parsing needs no server.
ClassMethod TestParsing(ByRef pPass, ByRef pFail)
{
    // --- single forms ---
    do ..ParseOne("ns=2;s=Plant.AC1", .tNS, .tId, .tType, .tErr)
    do ..Check("ns=2;s=Plant.AC1 → ns", tNS, 2, .pPass, .pFail)
    do ..Check("ns=2;s=Plant.AC1 → id", tId, "Plant.AC1", .pPass, .pFail)
    do ..Check("ns=2;s=Plant.AC1 → idType", tType, $$$OpcuaNodeIdTypeString, .pPass, .pFail)

    do ..ParseOne("ns=2;i=1047", .tNS, .tId, .tType, .tErr)
    do ..Check("ns=2;i=1047 → ns", tNS, 2, .pPass, .pFail)
    do ..Check("ns=2;i=1047 → id", tId, 1047, .pPass, .pFail)
    do ..Check("ns=2;i=1047 → idType", tType, $$$OpcuaNodeIdTypeNumeric, .pPass, .pFail)

    do ..ParseOne("i=85", .tNS, .tId, .tType, .tErr)
    do ..Check("i=85 defaults to ns 0", tNS, 0, .pPass, .pFail)
    do ..Check("i=85 → id", tId, 85, .pPass, .pFail)

    // A string identifier may itself contain a semicolon-free path with dots/slashes
    do ..ParseOne("ns=1;s=SA1", .tNS, .tId, .tType, .tErr)
    do ..Check("ns=1;s=SA1 → id", tId, "SA1", .pPass, .pFail)

    // --- rejected forms ---
    do ..ParseOne("/Plant/AC1", .tNS, .tId, .tType, .tErr)
    do ..Check("browse-path form is rejected", (tErr '= ""), 1, .pPass, .pFail)

    do ..ParseOne("garbage", .tNS, .tId, .tType, .tErr)
    do ..Check("garbage is rejected", (tErr '= ""), 1, .pPass, .pFail)

    do ..ParseOne("ns=x;s=Foo", .tNS, .tId, .tType, .tErr)
    do ..Check("non-numeric namespace is rejected", (tErr '= ""), 1, .pPass, .pFail)

    do ..ParseOne("ns=2;i=notanumber", .tNS, .tId, .tType, .tErr)
    do ..Check("non-numeric i= is rejected", (tErr '= ""), 1, .pPass, .pFail)

    // --- multi-line setting, labels, comments, blank lines ---
    set tSetting = "ns=1;s=SA1|First"_$Char(10)_""_$Char(10)_"# a comment"_$Char(10)_"ns=1;s=SA2"
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do ..Check("multi-line parse succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
    do ..Check("blank + comment lines skipped → 2 devices", $LL(tDevices), 2, .pPass, .pFail)
    do ..Check("explicit label is used", $LI($LI(tDevices, 1), 4), "First", .pPass, .pFail)
    do ..Check("label defaults to the nodepath", $LI($LI(tDevices, 2), 4), "ns=1;s=SA2", .pPass, .pFail)

    // CRLF line endings (a Portal textarea may submit these)
    set tSetting = "ns=1;s=SA1"_$Char(13, 10)_"ns=1;s=SA2"
    do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do ..Check("CRLF line endings handled", $LL(tDevices), 2, .pPass, .pFail)

    // A bad line is reported but does not sink the good ones
    set tSetting = "ns=1;s=SA1"_$Char(10)_"garbage"_$Char(10)_"ns=1;s=SA2"
    do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tErrors)
    do ..Check("good lines survive a bad line", $LL(tDevices), 2, .pPass, .pFail)
    do ..Check("bad line is reported", $LL(tErrors), 1, .pPass, .pFail)

    // An entirely unusable setting is an error
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("", .tDevices, .tErrors)
    do ..Check("empty setting is an error", $$$ISERR(tSC), 1, .pPass, .pFail)
}

/// Parse one path, flattening the status into an error string for readability.
ClassMethod ParseOne(pPath As %String, Output pNS, Output pId, Output pType, Output pErr) [ Private ]
{
    set pErr = ""
    set tSC = ##class(OPCUA.DataSource.Resolver).ParseNodePath(pPath, .pNS, .pId, .pType)
    if $$$ISERR(tSC) set pErr = $System.Status.GetOneErrorText(tSC)
}

/// Resolve a throwaway schema against the live server.
///
/// Builds a schema whose columns are the plc mock server's own node names
/// (SA1, SA2, VT5) plus one deliberately absent column, then checks that the
/// resolver finds the real ones, misses the fake one, and reports it.
ClassMethod TestLiveResolution(pURL As %String, ByRef pPass, ByRef pFail)
{
    #dim tClient As OPCUA.Client
    set tSchema = "OPCUA.Tests.TmpResolverSchema"
    Try {
        // --- build a throwaway schema ---
        set tSC = ..BuildTempSchema(tSchema)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not build temp schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        // --- schema column introspection (no server needed) ---
        set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(tSchema, .tColumns, .tFolders)
        do ..Check("GetSchemaColumns succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        do ..Check("schema exposes 4 columns", $Get(tColumns), 4, .pPass, .pFail)

        // --- connect ---
        set tClient = ##class(OPCUA.Client).%New()
        set tSC = tClient.Initialize()
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL client initialize: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL connect to ", pURL, ": ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        // --- resolve two devices, both pointing at the Objects folder (i=85),
        //     which on the plc mock server holds SA1/SA2/VT5 directly ---
        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|DevA"_$Char(10)_"i=85|DevB", .tDevices, .tErrors)
        do ..Check("two devices parsed", $LL(tDevices), 2, .pPass, .pFail)

        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tSchema, tDevices, .tSpec, .tMasks, .tDiag)
        do ..Check("ResolveSpecification succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        // One mask per device, each as wide as the schema
        do ..Check("one mask per device", $LL(tMasks), 2, .pPass, .pFail)
        do ..Check("mask width = column count", $LL($LI(tMasks, 1)), 4, .pPass, .pFail)

        // SA1, SA2, VT5 exist on the mock server; NoSuchNode does not.
        // Mask index follows the schema's STORAGE order (which IRIS sorts
        // alphabetically), so look each column up by name rather than assuming
        // the order the properties were declared in.
        set tMask = $LI(tMasks, 1)
        kill tColPos
        for i=1:1:tColumns {
            set tColPos($LI(tColumns(i), 3)) = i
        }
        do ..Check("SA1 resolved", $LI(tMask, $Get(tColPos("SA1"))), 1, .pPass, .pFail)
        do ..Check("SA2 resolved", $LI(tMask, $Get(tColPos("SA2"))), 1, .pPass, .pFail)
        do ..Check("VT5 resolved", $LI(tMask, $Get(tColPos("VT5"))), 1, .pPass, .pFail)
        do ..Check("NoSuchNode left unresolved", $LI(tMask, $Get(tColPos("NoSuchNode"))), 0, .pPass, .pFail)

        // The unresolved column is reported once per device.
        do ..Check("missing column reported per device", $LL(tDiag), 2, .pPass, .pFail)
        if $LL(tDiag) >= 1 {
            do ..Check("diagnostic names the column", $LI($LI(tDiag, 1), 2), "NoSuchNode", .pPass, .pFail)
            do ..Check("diagnostic names the device", $LI($LI(tDiag, 1), 1), "DevA", .pPass, .pFail)
        }

        // Spec shape: marker + 3 resolved columns x 2 devices = 7 positions
        set tEntries = $LI(tSpec, 3)
        do ..Check("spec has marker + 6 entries", $LL(tEntries), 7, .pPass, .pFail)

        // Every emitted entry must carry a concrete node id, not the node NAME —
        // this is the whole point of resolution.
        set tAllConcrete = 1
        for i=2:1:$LL(tEntries) {
            set tEntry = $LI(tEntries, i)
            if $LI(tEntry, 4) = "" set tAllConcrete = 0
        }
        do ..Check("all entries carry a resolved node id", tAllConcrete, 1, .pPass, .pFail)

        // Devices must be distinguishable in the spec (per-device property paths)
        set tFirst = $LI($LI(tEntries, 2), 2)
        set tLast = $LI($LI(tEntries, $LL(tEntries)), 2)
        do ..Check("device 1 entries tagged _RS1", (tFirst [ "_RS1"), 1, .pPass, .pFail)
        do ..Check("device 2 entries tagged _RS2", (tLast [ "_RS2"), 1, .pPass, .pFail)

        // --- the spec must actually be usable by the C++ layer ---
        set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
        do ..Check("C++ accepts the resolved spec", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISOK(tSC) {
            set tSC = tClient.ReadBulkPollC(.tList, tHandle)
            do ..Check("poll with resolved spec succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
            if $$$ISOK(tSC) {
                do ..Check("poll returns 6 values + metadata", $LL(tList), 7, .pPass, .pFail)
                // Each returned DataValue should carry a value in position 4.
                set tGotValue = 0
                set tDV = $LI(tList, 2)
                if $ListValid(tDV) && ($LL(tDV) >= 4) && ($LI(tDV, 4) '= "") set tGotValue = 1
                do ..Check("first value is populated", tGotValue, 1, .pPass, .pFail)
            }
            do tClient.ReadBulkClear(tHandle)
        }

        // --- an unbrowsable device degrades gracefully, it does not throw ---
        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("ns=1;s=NoSuchDeviceAtAll|Ghost", .tGhost, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tSchema, tGhost, .tGSpec, .tGMasks, .tGDiag)
        do ..Check("unknown device does not error out", $$$ISOK(tSC), 1, .pPass, .pFail)
        do ..Check("unknown device yields all-zero mask", $LI(tGMasks, 1), $LB(0, 0, 0, 0), .pPass, .pFail)

    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }

    do:$IsObject($Get(tClient)) tClient.Disconnect()
    do ..DropTempSchema(tSchema)
}

/// Resolve a schema containing a nested %SerialObject folder.
///
/// Uses the standard OPC UA Server object (i=2253) as the device root, since it
/// exists on every server and reliably has both flat leaves (ServiceLevel,
/// Auditing) and a nested folder of leaves (ServerStatus/State, .../CurrentTime).
ClassMethod TestNestedResolution(pURL As %String, ByRef pPass, ByRef pFail)
{
    #dim tClient As OPCUA.Client
    set tSchema = "OPCUA.Tests.TmpNestedSchema"
    Try {
        set tSC = ..BuildNestedSchema(tSchema)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not build nested schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        // The folder's leaves must be reported as nested columns, and the
        // folder itself must be discoverable as a folder to descend into.
        set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(tSchema, .tColumns, .tFolders)
        do ..Check("GetSchemaColumns succeeds (nested)", $$$ISOK(tSC), 1, .pPass, .pFail)
        do ..Check("nested schema exposes 4 leaf columns", $Get(tColumns), 4, .pPass, .pFail)
        do ..Check("ServerStatus detected as a folder", ''$Data(tFolders("ServerStatus")), 1, .pPass, .pFail)

        // Exactly two of the four columns should be attributed to the folder.
        set tNested = 0
        for i=1:1:tColumns {
            if $LI(tColumns(i), 5) = "ServerStatus" set tNested = tNested + 1
        }
        do ..Check("two columns attributed to the folder", tNested, 2, .pPass, .pFail)

        set tClient = ##class(OPCUA.Client).%New()
        do tClient.Initialize()
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL connect: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=2253|Srv", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tSchema, tDevices, .tSpec, .tMasks, .tDiag)
        do ..Check("nested ResolveSpecification succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)

        // Every column — flat and nested — should resolve on a real server.
        do ..Check("all 4 nested-schema columns resolved", $LI(tMasks, 1), $LB(1, 1, 1, 1), .pPass, .pFail)
        do ..Check("no diagnostics for a fully matching device", $LL(tDiag), 0, .pPass, .pFail)

        // The nested leaves must resolve to their OWN node ids, i.e. the resolver
        // really descended a level rather than matching under the device root.
        set tEntries = $LI(tSpec, 3)
        kill tSeen
        for i=2:1:$LL(tEntries) {
            set tSeen($LI($LI(tEntries, i), 4)) = ""
        }
        do ..Check("ServerStatus/State resolved to its own id", ''$Data(tSeen(2259)), 1, .pPass, .pFail)
        do ..Check("ServerStatus/CurrentTime resolved to its own id", ''$Data(tSeen(2258)), 1, .pPass, .pFail)

        // And the C++ layer must accept and poll the nested spec.
        set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
        do ..Check("C++ accepts the nested spec", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISOK(tSC) {
            set tSC = tClient.ReadBulkPollC(.tList, tHandle)
            do ..Check("nested poll succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
            do:$$$ISOK(tSC) ..Check("nested poll returns 4 values + metadata", $LL(tList), 5, .pPass, .pFail)
            do tClient.ReadBulkClear(tHandle)
        }

    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }

    do:$IsObject($Get(tClient)) tClient.Disconnect()
    do ..DropTempSchema(tSchema_".ServerStatusType")
    do ..DropTempSchema(tSchema)
}

/// Build a throwaway schema with two flat columns and a %SerialObject folder
/// holding two more, mirroring what the wizard emits for nested selections.
ClassMethod BuildNestedSchema(pClassName As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    set tSerialClass = pClassName_".ServerStatusType"
    Try {
        do ..DropTempSchema(pClassName)
        do ..DropTempSchema(tSerialClass)

        // --- the folder's serial class first, as DeployService does ---
        set tDef = ##class(%Dictionary.ClassDefinition).%New(tSerialClass)
        set tDef.Description = "Throwaway serial object for OPCUA.Tests.ResolverTest."
        set tDef.Super = "%SerialObject"
        set tDef.PropertyClass = "OPCUA.DataSource.PropertyClass"
        for tName = "State", "CurrentTime" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%String"
            do tProp.Parameters.SetAt(tName, "OPCUANODENAME")
            do tDef.Properties.Insert(tProp)
        }
        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(tSerialClass, "ck-d")
        $$$ThrowOnError(tSC)

        // --- the main schema ---
        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Description = "Throwaway nested schema for OPCUA.Tests.ResolverTest."
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUADATASOURCE"
        set tParam.Default = "TmpNestedSchema"
        do tDef.Parameters.Insert(tParam)
        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUDEFAULTANAMESPACE"
        set tParam.Default = 0
        do tDef.Parameters.Insert(tParam)

        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "NodePath"
        set tProp.Type = "%String"
        do tProp.Parameters.SetAt(500, "MAXLEN")
        do tDef.Properties.Insert(tProp)
        for tName = "ServerTimeStamp", "SourceTimeStamp" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%TimeStamp"
            do tDef.Properties.Insert(tProp)
        }

        // Two flat leaves that exist on any server's Server object
        for tName = "ServiceLevel", "Auditing" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%String"
            do tProp.Parameters.SetAt(tName, "OPCUANODENAME")
            do tDef.Properties.Insert(tProp)
        }

        // The nested folder
        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "ServerStatus"
        set tProp.Type = tSerialClass
        do tProp.Parameters.SetAt("ServerStatus", "OPCUANODENAME")
        do tDef.Properties.Insert(tProp)

        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(pClassName, "ck-d")
        $$$ThrowOnError(tSC)
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Build a throwaway DeviceSchema whose column names match the plc mock server,
/// plus one column that deliberately does not exist there.
ClassMethod BuildTempSchema(pClassName As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropTempSchema(pClassName)

        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Description = "Throwaway schema for OPCUA.Tests.ResolverTest."
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUADATASOURCE"
        set tParam.Default = "TmpResolverSchema"
        do tDef.Parameters.Insert(tParam)

        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUDEFAULTANAMESPACE"
        set tParam.Default = 1
        do tDef.Parameters.Insert(tParam)

        // Row metadata, as the wizard emits it
        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "NodePath"
        set tProp.Type = "%String"
        do tProp.Parameters.SetAt(500, "MAXLEN")
        do tDef.Properties.Insert(tProp)

        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "ServerTimeStamp"
        set tProp.Type = "%TimeStamp"
        do tDef.Properties.Insert(tProp)

        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "SourceTimeStamp"
        set tProp.Type = "%TimeStamp"
        do tDef.Properties.Insert(tProp)

        // Columns. Three match nodes the plc mock server really exposes; the
        // fourth deliberately does not exist, to exercise the unresolved path.
        // IRIS sorts storage entries alphabetically regardless of the order
        // declared here, so the assertions look columns up by name.
        for tSpec = "SA1:%Integer", "SA2:%Integer", "VT5:%Integer", "NoSuchNode:%String" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = $Piece(tSpec, ":", 1)
            set tProp.Type = $Piece(tSpec, ":", 2)
            do tProp.Parameters.SetAt($Piece(tSpec, ":", 1), "OPCUANODENAME")
            do tDef.Properties.Insert(tProp)
        }

        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(pClassName, "ck-d")
        $$$ThrowOnError(tSC)
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// The C++ layer exports UA_NodeClass at browse reference position [6], and
/// <method>BrowseService.ClassifyNode</method> must prefer it over its
/// TypeDefinition heuristics.
///
/// This guards two things a prebuilt binary can silently take away:
///   1. that position [6] arrives populated at all (an older .so left it empty,
///      and every Method was then miscategorised as an Object), and
///   2. that the category derived from it is the one the webapp expects.
///
/// The Server object (ns=0;i=2253) is the fixture because it is mandated by the
/// spec, so every server has it, and it holds Objects, Variables and Methods
/// side by side -- Methods being the class the heuristics alone cannot see.
ClassMethod TestNodeClass(pURL As %String, ByRef pPass, ByRef pFail)
{
    #dim tClient As OPCUA.Client
    Try {
        set tClient = ##class(OPCUA.Client).%New()
        set tSC = tClient.Initialize()
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL client initialize: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL connect to ", pURL, ": ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = tClient.Browse(.tResults, $LB($$$OpcuaNodeIdTypeNumeric), $LB(0), $LB(2253))
        do ..Check("browse Server object succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) quit

        set tCount = ##class(OPCUA.REST.BrowseService).WalkBrowseResults(tResults, .tChildren)
        do ..Check("Server has children", (tCount > 0), 1, .pPass, .pFail)

        // Tally what came back, keyed by name, plus how many carried a nodeClass.
        set tWithClass = 0
        for i=1:1:tCount {
            set tName = $LI(tChildren(i), 1)
            set tByName(tName) = $LB($LI(tChildren(i), 6), $LI(tChildren(i), 8))
            if $LI(tChildren(i), 8) '= "" set tWithClass = tWithClass + 1
        }

        // (1) Every reference must carry one. An empty here means the loaded
        //     library predates the nodeClass export in UACExport.cpp.
        do ..Check("every child reports a nodeClass", tWithClass, tCount, .pPass, .pFail)

        // (2) The spec value must map to the category the webapp switches on.
        do ..CheckNodeClass("GetMonitoredItems", .tByName, $$$OpcuaNodeClassMethod, "method", .pPass, .pFail)
        do ..CheckNodeClass("ServerStatus", .tByName, $$$OpcuaNodeClassVariable, "variable", .pPass, .pFail)
        do ..CheckNodeClass("ServerCapabilities", .tByName, $$$OpcuaNodeClassObject, "object", .pPass, .pFail)
        do ..CheckNodeClass("NamespaceArray", .tByName, $$$OpcuaNodeClassVariable, "property", .pPass, .pFail)

    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    if $IsObject($Get(tClient)) do tClient.Disconnect()
}

/// A browse response never says whether a node has children, so BrowseService
/// probes one level ahead in a single batched browse and replaces the guess with a
/// count. This asserts the two halves that matter:
///
///   1. a bare variable reports hasChildren=false. It carries one
///      HasTypeDefinition reference, so a count that forgets to filter
///      non-child references marks every leaf expandable -- the original bug.
///   2. a node that really does have children still reports true, i.e. the fix
///      did not simply collapse everything.
///
/// The plc mock server is the right fixture precisely because its tags are bare.
ClassMethod TestChildProbe(pURL As %String, ByRef pPass, ByRef pFail)
{
    Try {
        set tBody = {}
        set tBody.url = pURL
        set tBody.nodeNs = 0
        set tBody.nodeId = 85

        set tSC = ##class(OPCUA.REST.BrowseService).Browse(tBody, .tNodes)
        do ..Check("browse Objects succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) quit

        kill tByName
        for i=0:1:tNodes.%Size()-1 {
            set tNode = tNodes.%Get(i)
            set tByName(tNode.displayName) = tNode.hasChildren
        }

        // (1) The bug: bare tags on the plc server must not look expandable.
        do ..Check("bare variable SA1 is a leaf", $Get(tByName("SA1")), 0, .pPass, .pFail)
        do ..Check("bare variable PROG is a leaf", $Get(tByName("PROG")), 0, .pPass, .pFail)

        // (2) The regression guard: a populated node stays expandable.
        do ..Check("Server object still expandable", $Get(tByName("Server")), 1, .pPass, .pFail)

        // Methods carry InputArguments/OutputArguments, so they are expandable too,
        // and that is measured here rather than assumed from the category.
        set tBody.nodeId = 2253
        set tSC = ##class(OPCUA.REST.BrowseService).Browse(tBody, .tSrv)
        do ..Check("browse Server succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISOK(tSC) {
            kill tSrvByName
            for i=0:1:tSrv.%Size()-1 {
                set tNode = tSrv.%Get(i)
                set tSrvByName(tNode.displayName) = tNode.hasChildren
            }
            do ..Check("method has argument children", $Get(tSrvByName("GetMonitoredItems")), 1, .pPass, .pFail)
            do ..Check("bare property is a leaf", $Get(tSrvByName("ServiceLevel")), 0, .pPass, .pFail)
        }

        // Opting out must restore the guess, so the flag genuinely bypasses the probe.
        set tBody.nodeId = 85
        set tBody.probeChildren = 0
        set tSC = ##class(OPCUA.REST.BrowseService).Browse(tBody, .tUnprobed)
        if $$$ISOK(tSC) {
            kill tRaw
            for i=0:1:tUnprobed.%Size()-1 {
                set tNode = tUnprobed.%Get(i)
                set tRaw(tNode.displayName) = tNode.hasChildren
            }
            do ..Check("probeChildren=0 keeps the guess", $Get(tRaw("SA1")), 1, .pPass, .pFail)
        }

    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
}

/// Assert one browsed child's nodeClass and derived category.
ClassMethod CheckNodeClass(pName As %String, ByRef pByName, pWantClass As %Integer, pWantCategory As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    if '$Data(pByName(pName)) {
        set pFail = pFail + 1
        write "  FAIL ", pName, " not found among Server's children", !
        quit
    }
    do ..Check(pName_" nodeClass", $LI(pByName(pName), 2), pWantClass, .pPass, .pFail)
    do ..Check(pName_" category", $LI(pByName(pName), 1), pWantCategory, .pPass, .pFail)
}

/// Remove the throwaway schema and its metadata.
ClassMethod DropTempSchema(pClassName As %String) [ Private ]
{
    Try {
        if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
            do $System.OBJ.Delete(pClassName, "-d")
        }
        kill ^OPCUA.DataSource(pClassName)
    } Catch (e) {}
}

}
