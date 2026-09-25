Include (OPCUA.Constants, %occInclude)

/// Tests that a wizard-generated device schema keeps every measurement's own
/// value, quality and timestamps instead of collapsing them to a bare value
/// plus one row-level timestamp pair.
///
/// Run against the docker-compose mock server:
///   zn "OPCUA"
///   write ##class(OPCUA.Tests.MeasurementMetadataTest).Run("opc.tcp://plc")
///
/// The offline sections need no server; only <method>TestLiveRow</method> does.
Class OPCUA.Tests.MeasurementMetadataTest
{

/// Package the throwaway generated classes live in.
Parameter TestPackage = "OPCUA.Tests.Tmp";

/// Run the whole suite. Returns 1 if every test passed.
ClassMethod Run(pURL As %String = "opc.tcp://plc") As %Boolean
{
    set tPass = 0, tFail = 0

    write !, "=== Type mapping (offline) ===", !
    do ..TestTypeMapping(.tPass, .tFail)

    write !, "=== Generated schema shape (offline) ===", !
    do ..TestSchemaShape(.tPass, .tFail)

    write !, "=== Row assembly, flat schema (offline) ===", !
    do ..TestFlatRow(.tPass, .tFail)

    write !, "=== Row assembly, nested folder (offline) ===", !
    do ..TestNestedRow(.tPass, .tFail)

    write !, "=== Legacy plain schema still writes (offline) ===", !
    do ..TestLegacyPlainRow(.tPass, .tFail)

    write !, "=== Live poll against ", pURL, " ===", !
    do ..TestLiveRow(pURL, .tPass, .tFail)

    write !, "=== Live subscription against ", pURL, " ===", !
    do ..TestLiveSubscription(pURL, .tPass, .tFail)

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

// ==================== type mapping ====================

/// Every inferred type must land on a class that carries the metadata, and an
/// OPCUA.Types class the frontend already sent must pass through untouched.
ClassMethod TestTypeMapping(ByRef pPass, ByRef pFail)
{
    set tSvc = "OPCUA.REST.SchemaService"

    do ..Check("DoubleDataValue passes through",
        $classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.DoubleDataValue"),
        "OPCUA.Types.DoubleDataValue", .pPass, .pFail)

    do ..Check("array DataValue passes through",
        $classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.ArrayDataValue.Double"),
        "OPCUA.Types.ArrayDataValue.Double", .pPass, .pFail)

    do ..Check("%Double is wrapped",
        $classmethod(tSvc, "MapToDataValueType", "%Double"),
        "OPCUA.Types.DoubleDataValue", .pPass, .pFail)

    do ..Check("%Boolean is wrapped",
        $classmethod(tSvc, "MapToDataValueType", "%Boolean"),
        "OPCUA.Types.BooleanDataValue", .pPass, .pFail)

    do ..Check("unknown type falls back to a wrapper, not a bare string",
        $classmethod(tSvc, "MapToDataValueType", ""),
        "OPCUA.Types.StringDataValue", .pPass, .pFail)

    // The whole point: nothing may map to a plain type any more.
    set tAnyPlain = 0
    for tIn = "", "%Double", "%Integer", "%Boolean", "%String", "%TimeStamp", "OPCUA.Types.StringDataValue" {
        set tOut = $classmethod(tSvc, "MapToDataValueType", tIn)
        if $Extract(tOut, 1) = "%" set tAnyPlain = 1
    }
    do ..Check("no inferred type maps to a plain IRIS type", tAnyPlain, 0, .pPass, .pFail)
}

// ==================== generated schema shape ====================

/// A generated schema must declare DataValue properties and must NOT declare
/// the old row-level timestamp pair, because timestamps are per measurement now.
ClassMethod TestSchemaShape(ByRef pPass, ByRef pFail)
{
    set tClass = ..#TestPackage_".ShapeSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpShapeSchema", 1)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not generate schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        kill tType
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(tClass)
        for i=1:1:tCD.Properties.Count() {
            set tProp = tCD.Properties.GetAt(i)
            set tType(tProp.Name) = tProp.Type
        }

        do ..Check("Alpha is a DataValue", $Get(tType("Alpha")), "OPCUA.Types.DoubleDataValue", .pPass, .pFail)
        do ..Check("Beta is a DataValue", $Get(tType("Beta")), "OPCUA.Types.IntegerDataValue", .pPass, .pFail)
        do ..Check("Gamma is a DataValue", $Get(tType("Gamma")), "OPCUA.Types.StringDataValue", .pPass, .pFail)
        // The compiler normalises %String to its fully qualified name.
        do ..Check("NodePath stays a plain string", $Get(tType("NodePath")), "%Library.String", .pPass, .pFail)
        do ..Check("no row-level ServerTimeStamp", $Data(tType("ServerTimeStamp")), 0, .pPass, .pFail)
        do ..Check("no row-level SourceTimeStamp", $Data(tType("SourceTimeStamp")), 0, .pPass, .pFail)

        // The projection must record each measurement as a standard OPC UA
        // structure (code 2), which is what makes the C layer hand back the
        // full DataValue rather than a bare scalar.
        set tSpec = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(tClass)
        set tEntries = $LI(tSpec, 3)
        set tAllCode2 = 1, tCount = 0
        for i=2:1:$LL(tEntries) {
            set tEntry = $LI(tEntries, i)
            continue:tEntry=""
            set tCount = tCount + 1
            if $LI(tEntry, 1) '= 2 set tAllCode2 = 0
        }
        do ..Check("projection records 3 columns", tCount, 3, .pPass, .pFail)
        do ..Check("every column recorded as a full DataValue", tAllCode2, 1, .pPass, .pFail)

        // SQL must expose the four fields per measurement.
        kill tField
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM "_..TableName(tClass)_" WHERE 1=0")
        set tMeta = tRS.%GetMetadata()
        for i=1:1:tMeta.columnCount {
            set tField($ZConvert(tMeta.columns.GetAt(i).colName, "U")) = ""
        }
        for tName = "ALPHA_VALUE", "ALPHA_STATUS", "ALPHA_SOURCETIMESTAMP", "ALPHA_SERVERTIMESTAMP" {
            do ..Check("SQL exposes "_tName, ''$Data(tField(tName)), 1, .pPass, .pFail)
        }
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    do ..DropSchema(tClass)
}

// ==================== flat row assembly ====================

/// Give the writer three measurements with deliberately distinct metadata and
/// one unresolved column, then read the stored row back both ways.
ClassMethod TestFlatRow(ByRef pPass, ByRef pFail)
{
    set tClass = ..#TestPackage_".FlatSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpFlatSchema", 1)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not generate schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not read columns: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }
        do ..Check("schema has 3 columns", tColCount, 3, .pPass, .pFail)

        // Beta is the unresolved one: it must store NULL without shifting the
        // values of the columns on either side of it.
        set tMask = ""
        for i=1:1:tColCount {
            set tMask = tMask _ $LB($Select($LI(tIdx(i), 1) = "Beta": 0, 1: 1))
        }

        // One synthetic DataValue per resolved column, in mask order, each with
        // its own status and timestamps. Storage order is source, server,
        // status, value — see OPCUA.Types.AbstractDataValue.
        kill tWant
        set tWant("Alpha") = $LB("2026-01-01 00:00:01", "2026-01-01 00:00:02", 7, 21.5)
        set tWant("Gamma") = $LB("2026-02-02 11:11:11", "2026-02-02 11:11:12", 9, "hello")

        set tInput = $LB("")
        for i=1:1:tColCount {
            continue:'+$LI(tMask, i)
            set tInput = tInput _ $LB(tWant($LI(tIdx(i), 1)))
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        do ..Check("writer initializes", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=DevA", .tResultIdx, .tRow)
        do ..Check("row builds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }
        do ..Check("the unresolved column consumed no result entry", tResultIdx, 3, .pPass, .pFail)

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do ..Check("row saves", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        // --- object readback ---
        set tObj = $classmethod(tClass, "%OpenId", tId)
        do ..Check("row opens as an object", $IsObject(tObj), 1, .pPass, .pFail)
        quit:'$IsObject(tObj)

        do ..Check("NodePath stored", tObj.NodePath, "ns=1;s=DevA", .pPass, .pFail)
        do ..Check("Alpha value", tObj.Alpha.Value, 21.5, .pPass, .pFail)
        do ..Check("Alpha status", tObj.Alpha.Status, 7, .pPass, .pFail)
        do ..Check("Alpha source timestamp", tObj.Alpha.SourceTimeStamp, "2026-01-01 00:00:01", .pPass, .pFail)
        do ..Check("Alpha server timestamp", tObj.Alpha.ServerTimeStamp, "2026-01-01 00:00:02", .pPass, .pFail)

        // Isolation: Gamma must carry its OWN metadata, not Alpha's.
        do ..Check("Gamma value", tObj.Gamma.Value, "hello", .pPass, .pFail)
        do ..Check("Gamma status is its own", tObj.Gamma.Status, 9, .pPass, .pFail)
        do ..Check("Gamma source timestamp is its own", tObj.Gamma.SourceTimeStamp, "2026-02-02 11:11:11", .pPass, .pFail)
        do ..Check("Gamma server timestamp is its own", tObj.Gamma.ServerTimeStamp, "2026-02-02 11:11:12", .pPass, .pFail)

        // --- SQL readback ---
        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Alpha_Value, Alpha_Status, Alpha_SourceTimeStamp, Beta_Value, Gamma_Value, Gamma_Status "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do ..Check("SQL returns the row", tRS.%Next(), 1, .pPass, .pFail)
        do ..Check("SQL Alpha_Value", tRS.%GetData(1), 21.5, .pPass, .pFail)
        do ..Check("SQL Alpha_Status", tRS.%GetData(2), 7, .pPass, .pFail)
        do ..Check("SQL Alpha_SourceTimeStamp", tRS.%GetData(3), "2026-01-01 00:00:01", .pPass, .pFail)
        do ..Check("SQL Beta_Value is empty for the unresolved column", tRS.%GetData(4), "", .pPass, .pFail)
        do ..Check("SQL Gamma_Value", tRS.%GetData(5), "hello", .pPass, .pFail)
        do ..Check("SQL Gamma_Status", tRS.%GetData(6), 9, .pPass, .pFail)
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    do ..DropSchema(tClass)
}

// ==================== nested row assembly ====================

/// A measurement inside a folder must keep its own metadata too: the folder
/// serial object holds DataValue serial objects, nested two levels deep.
ClassMethod TestNestedRow(ByRef pPass, ByRef pFail)
{
    set tClass = ..#TestPackage_".NestedSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpNestedMetaSchema", 0)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not generate nested schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        // The folder property must be a generated serial class whose own
        // properties are DataValues — not a DataValue itself.
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(tClass)
        set tFolderType = ""
        for i=1:1:tCD.Properties.Count() {
            if tCD.Properties.GetAt(i).Name = "Motor" set tFolderType = tCD.Properties.GetAt(i).Type
        }
        do ..Check("Motor is a generated serial class", tFolderType, ..#TestPackage_".NestedSchema.MotorType", .pPass, .pFail)
        if tFolderType '= "" {
            kill tSubType
            set tSD = ##class(%Dictionary.CompiledClass).%OpenId(tFolderType)
            if $IsObject(tSD) {
                for i=1:1:tSD.Properties.Count() {
                    set tSubType(tSD.Properties.GetAt(i).Name) = tSD.Properties.GetAt(i).Type
                }
            }
            do ..Check("Motor.Temperature is a DataValue", $Get(tSubType("Temperature")), "OPCUA.Types.DoubleDataValue", .pPass, .pFail)
            do ..Check("Motor.Speed is a DataValue", $Get(tSubType("Speed")), "OPCUA.Types.IntegerDataValue", .pPass, .pFail)
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        $$$ThrowOnError(tSC)
        do ..Check("nested schema exposes 3 leaf columns", tColCount, 3, .pPass, .pFail)

        kill tWant
        set tWant("Humidity") = $LB("2026-03-03 01:01:01", "2026-03-03 01:01:02", 1, 45)
        set tWant("Temperature") = $LB("2026-03-03 02:02:02", "2026-03-03 02:02:03", 2, 21.5)
        set tWant("Speed") = $LB("2026-03-03 03:03:03", "2026-03-03 03:03:04", 3, 1500)

        set tMask = "", tInput = $LB("")
        for i=1:1:tColCount {
            set tMask = tMask _ $LB(1)
            set tInput = tInput _ $LB(tWant($LI(tIdx(i), 1)))
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        do ..Check("nested writer initializes", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=2;s=AC1", .tResultIdx, .tRow)
        do ..Check("nested row builds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do ..Check("nested row saves", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do ..Check("nested row opens", $IsObject(tObj), 1, .pPass, .pFail)
        quit:'$IsObject(tObj)

        do ..Check("flat Humidity value survives alongside the folder", tObj.Humidity.Value, 45, .pPass, .pFail)
        do ..Check("flat Humidity status", tObj.Humidity.Status, 1, .pPass, .pFail)
        do ..Check("Motor.Temperature value", tObj.Motor.Temperature.Value, 21.5, .pPass, .pFail)
        do ..Check("Motor.Temperature status", tObj.Motor.Temperature.Status, 2, .pPass, .pFail)
        do ..Check("Motor.Temperature source timestamp", tObj.Motor.Temperature.SourceTimeStamp, "2026-03-03 02:02:02", .pPass, .pFail)
        do ..Check("Motor.Temperature server timestamp", tObj.Motor.Temperature.ServerTimeStamp, "2026-03-03 02:02:03", .pPass, .pFail)
        do ..Check("Motor.Speed keeps its own metadata", tObj.Motor.Speed.Status, 3, .pPass, .pFail)
        do ..Check("Motor.Speed source timestamp is its own", tObj.Motor.Speed.SourceTimeStamp, "2026-03-03 03:03:03", .pPass, .pFail)

        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Motor_Temperature_Value, Motor_Temperature_SourceTimeStamp, Motor_Speed_Value, Humidity_Value "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do ..Check("SQL returns the nested row", tRS.%Next(), 1, .pPass, .pFail)
        do ..Check("SQL Motor_Temperature_Value", tRS.%GetData(1), 21.5, .pPass, .pFail)
        do ..Check("SQL Motor_Temperature_SourceTimeStamp", tRS.%GetData(2), "2026-03-03 02:02:02", .pPass, .pFail)
        do ..Check("SQL Motor_Speed_Value", tRS.%GetData(3), 1500, .pPass, .pFail)
        do ..Check("SQL Humidity_Value", tRS.%GetData(4), 45, .pPass, .pFail)
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    do ..DropSchema(tClass)
}

// ==================== legacy plain schema ====================

/// A schema already deployed with plain columns and a row-level timestamp pair
/// must keep writing exactly as before — the change must not strand it.
ClassMethod TestLegacyPlainRow(ByRef pPass, ByRef pFail)
{
    set tClass = ..#TestPackage_".LegacySchema"
    Try {
        set tSC = ..BuildLegacyPlainSchema(tClass)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not build legacy schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        $$$ThrowOnError(tSC)
        do ..Check("legacy schema has 2 columns", tColCount, 2, .pPass, .pFail)

        kill tWant
        set tWant("Alpha") = $LB("2026-04-04 04:04:04", "2026-04-04 04:04:05", 0, 12.25)
        set tWant("Beta") = $LB("2026-04-04 05:05:05", "2026-04-04 05:05:06", 0, 99)

        set tMask = "", tInput = $LB("")
        for i=1:1:tColCount {
            set tMask = tMask _ $LB(1)
            set tInput = tInput _ $LB(tWant($LI(tIdx(i), 1)))
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        do ..Check("legacy writer initializes", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=Old", .tResultIdx, .tRow)
        do ..Check("legacy row builds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do ..Check("legacy row saves", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        quit:'$IsObject(tObj)
        do ..Check("legacy column stores the bare value", tObj.Alpha, 12.25, .pPass, .pFail)
        do ..Check("legacy second column stores the bare value", tObj.Beta, 99, .pPass, .pFail)
        do ..Check("legacy row keeps its row-level source timestamp", tObj.SourceTimeStamp, "2026-04-04 04:04:04", .pPass, .pFail)
        do ..Check("legacy row keeps its row-level server timestamp", tObj.ServerTimeStamp, "2026-04-04 04:04:05", .pPass, .pFail)
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    do ..DropSchema(tClass)
}

// ==================== live poll ====================

/// End-to-end against a real server: generate a schema from node names the mock
/// server exposes, resolve it, poll, and confirm the stored measurements carry
/// real values and real timestamps rather than empty metadata.
ClassMethod TestLiveRow(pURL As %String, ByRef pPass, ByRef pFail)
{
    #dim tClient As OPCUA.Client
    set tClass = ..#TestPackage_".LiveSchema"
    Try {
        set tSC = ..BuildLiveSchema(tClass)
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not generate live schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

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

        // Two devices both rooted at the Objects folder, where the mock server
        // holds SA1/SA2/VT5 directly.
        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|DevA"_$Char(10)_"i=85|DevB", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do ..Check("resolution succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)
        do ..Check("all columns resolved on the mock server", $LI(tMasks, 1), $LB(1, 1, 1), .pPass, .pFail)

        set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
        do ..Check("C layer accepts the spec", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tSC = tClient.ReadBulkPollC(.tList, tHandle)
        do ..Check("poll succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            do tClient.ReadBulkClear(tHandle)
            quit
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        do ..Check("live writer initializes", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            do tClient.ReadBulkClear(tHandle)
            quit
        }

        // Write both devices from the one flat result, exactly as the services do.
        set tResultIdx = 1
        kill tIds
        for iDev=1:1:$LL(tMasks) {
            set tSC = tWriter.BuildRow(.tList, $LI(tMasks, iDev), $LI($LI(tDevices, iDev), 4), .tResultIdx, .tRow)
            $$$ThrowOnError(tSC)
            set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
            $$$ThrowOnError(tSC)
            set tIds(iDev) = tId
        }
        do tClient.ReadBulkClear(tHandle)

        do ..Check("both devices produced a row", $Get(tIds(2)) '= "", 1, .pPass, .pFail)

        set tObj = $classmethod(tClass, "%OpenId", $Get(tIds(1)))
        do ..Check("live row opens", $IsObject(tObj), 1, .pPass, .pFail)
        quit:'$IsObject(tObj)

        do ..Check("device label stored as NodePath", tObj.NodePath, "DevA", .pPass, .pFail)
        do ..Check("SA1 has a real value", tObj.SA1.Value '= "", 1, .pPass, .pFail)
        do ..Check("SA1 has a source timestamp", tObj.SA1.SourceTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("SA1 has a server timestamp", tObj.SA1.ServerTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("SA1 status is good", tObj.SA1.Status, 0, .pPass, .pFail)
        do ..Check("SA2 has its own source timestamp", tObj.SA2.SourceTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("VT5 has a real value", tObj.VT5.Value '= "", 1, .pPass, .pFail)

        // Every measurement on the row must be populated — a single shared
        // timestamp pair would leave the others blank.
        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT COUNT(*) FROM "_..TableName(tClass)_
            " WHERE SA1_SourceTimeStamp IS NOT NULL AND SA2_SourceTimeStamp IS NOT NULL AND VT5_SourceTimeStamp IS NOT NULL")
        do tRS.%Next()
        do ..Check("both rows carry a timestamp for every measurement", tRS.%GetData(1), 2, .pPass, .pFail)
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    do:$IsObject($Get(tClient)) tClient.Disconnect()
    do ..DropSchema(tClass)
}

/// The subscription transport feeds the same writer, so a change notification
/// must store the same four fields per measurement as a poll does. This is the
/// check that stops the two collection modes drifting apart again.
ClassMethod TestLiveSubscription(pURL As %String, ByRef pPass, ByRef pFail)
{
    #dim tClient As OPCUA.Client
    set tClass = ..#TestPackage_".SubSchema"
    set tHandle = ""
    Try {
        set tSC = ..BuildLiveSchema(tClass, "TmpSubMetaSchema")
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL could not generate schema: ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tClient = ##class(OPCUA.Client).%New()
        do tClient.Initialize()
        do tClient.SetupClient("", 1, "", "", "", "", "")
        set tSC = tClient.Connect(pURL, "", "")
        if $$$ISERR(tSC) {
            set pFail = pFail + 1
            write "  FAIL connect to ", pURL, ": ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|SubDev", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do ..Check("subscription resolution succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tPublishing = 200, tLifetime = 10000, tKeepAlive = 10, tSampling = 200
        set tSC = tClient.CreateSubscriptionSetB(.tHandle, tSpec, .tPublishing, .tLifetime, .tKeepAlive, 100, tSampling, 1, 0)
        do ..Check("subscription created from the resolved spec", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        // The first publish cycle may be empty; give the server a few chances.
        set tBatch = "", tQty = 0
        for i=1:1:10 {
            set tSC = tClient.PollSubscriptionSet(.tList, tHandle, 1000, 0, 1)
            quit:$$$ISERR(tSC)
            set tQty = $LI(tList, 2)
            if tQty > 0 {
                set tBatch = $LI(tList, 3)
                quit
            }
            hang 0.3
        }
        do ..Check("subscription poll succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
        do ..Check("a notification arrived", (tQty > 0), 1, .pPass, .pFail)
        quit:tQty'>0

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        set tSC = tWriter.Initialize(tClass)
        $$$ThrowOnError(tSC)

        // One notification is shaped exactly like one poll result, which is why
        // both services can hand it to the same writer unchanged.
        set tNotification = $LI(tBatch, 1)
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tNotification, $LI(tMasks, 1), "SubDev", .tResultIdx, .tRow)
        do ..Check("notification builds a row", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) {
            write "       ", $System.Status.GetOneErrorText(tSC), !
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do ..Check("notification row saves", $$$ISOK(tSC), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        quit:'$IsObject(tObj)
        do ..Check("subscribed SA1 has a value", tObj.SA1.Value '= "", 1, .pPass, .pFail)
        do ..Check("subscribed SA1 has a source timestamp", tObj.SA1.SourceTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("subscribed SA1 has a server timestamp", tObj.SA1.ServerTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("subscribed SA2 has its own source timestamp", tObj.SA2.SourceTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("subscribed VT5 has a value", tObj.VT5.Value '= "", 1, .pPass, .pFail)
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }
    // Tear down exactly the way TCPSubscriptionInboundAdapter.OnTearDown() does.
    // Calling DeleteSubscriptionSet() and then Disconnect() aborts the process
    // with a double free inside the native library, so the shipping adapter does
    // not do it either and neither does this test.
    if $IsObject($Get(tClient)) {
        Try { do tClient.ReadBulkClear(tHandle) } Catch (eClear) {}
        do tClient.Disconnect()
    }
    do ..DropSchema(tClass)
}

// ==================== fixtures ====================

/// Generate a schema through the real wizard path, so the test exercises
/// OPCUA.REST.SchemaService rather than a hand-built approximation.
/// pFlat 1 = three flat columns; 0 = one flat column plus a two-leaf folder.
ClassMethod BuildGeneratedSchema(pClassName As %String, pDSName As %String, pFlat As %Boolean) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tCols = []
        if pFlat {
            do tCols.%Push(..Column("Alpha", "OPCUA.Types.DoubleDataValue", $LB("Alpha")))
            do tCols.%Push(..Column("Beta", "OPCUA.Types.IntegerDataValue", $LB("Beta")))
            do tCols.%Push(..Column("Gamma", "OPCUA.Types.StringDataValue", $LB("Gamma")))
        } else {
            do tCols.%Push(..Column("Humidity", "OPCUA.Types.IntegerDataValue", $LB("Humidity")))
            do tCols.%Push(..Column("Temperature", "OPCUA.Types.DoubleDataValue", $LB("Motor", "Temperature")))
            do tCols.%Push(..Column("Speed", "OPCUA.Types.IntegerDataValue", $LB("Motor", "Speed")))
        }

        kill tColNS
        set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, pDSName, tCols, 1, .tColNS, .tSerial)
        $$$ThrowOnError(tSC)
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// A schema whose columns are node names the plc mock server really exposes.
ClassMethod BuildLiveSchema(pClassName As %String, pDSName As %String = "TmpLiveMetaSchema") As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tCols = []
        for tName = "SA1", "SA2", "VT5" {
            do tCols.%Push(..Column(tName, "OPCUA.Types.IntegerDataValue", $LB(tName)))
        }

        kill tColNS
        set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, pDSName, tCols, 1, .tColNS, .tSerial)
        $$$ThrowOnError(tSC)
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// A schema in the old shape: plain columns plus one row-level timestamp pair.
/// Written by hand because the generator deliberately cannot produce it any more.
ClassMethod BuildLegacyPlainSchema(pClassName As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        do ..DropSchema(pClassName)

        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Description = "Throwaway pre-metadata schema for OPCUA.Tests.MeasurementMetadataTest."
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        for tSpec = "OPCUADATASOURCE:TmpLegacySchema", "OPCUDEFAULTANAMESPACE:1", "OPCUAPIPELINEVERSION:2" {
            set tParam = ##class(%Dictionary.ParameterDefinition).%New()
            set tParam.Name = $Piece(tSpec, ":", 1)
            set tParam.Default = $Piece(tSpec, ":", 2)
            do tDef.Parameters.Insert(tParam)
        }

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

        for tSpec = "Alpha:%Double", "Beta:%Integer" {
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
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// One column description in the shape the frontend posts to /schemas.
ClassMethod Column(pDisplayName As %String, pInferredType As %String, pRelPath As %List) As %DynamicObject [ Private ]
{
    set tCol = {}
    set tCol.displayName = pDisplayName
    set tCol.inferredType = pInferredType
    set tPath = []
    for i=1:1:$LL(pRelPath) {
        do tPath.%Push($LI(pRelPath, i))
    }
    set tCol.relativePath = tPath
    Quit tCol
}

/// Map column index → $LB(nodeName, folderName), in the order the masks use.
ClassMethod ColumnIndex(pClassName As %String, Output pIndex, Output pCount) As %Status [ Private ]
{
    kill pIndex
    set pCount = 0
    set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(pClassName, .tColumns, .tFolders)
    Quit:$$$ISERR(tSC) tSC
    set pCount = tColumns
    for i=1:1:tColumns {
        set pIndex(i) = $LB($LI(tColumns(i), 3), $LI(tColumns(i), 5))
    }
    Quit $$$OK
}

/// SQL table name for a class.
ClassMethod TableName(pClassName As %String) As %String [ Private ]
{
    Quit $Translate($Piece(pClassName, ".", 1, *-1), ".", "_")_"."_$Piece(pClassName, ".", *)
}

/// Delete a throwaway schema and any serial classes generated beneath it.
ClassMethod DropSchema(pClassName As %String) [ Private ]
{
    Try { do $classmethod(pClassName, "%KillExtent") } Catch (e) {}
    Try { do $System.OBJ.Delete(pClassName_".*", "-d") } Catch (e) {}
    Try { do $System.OBJ.Delete(pClassName, "-d") } Catch (e) {}
    kill ^OPCUA.DataSource(pClassName)
}

}
