Include (OPCUA.Constants, %occInclude)

/// Offline half of the measurement-metadata suite: a wizard-generated device
/// schema keeps every measurement's own value, quality and timestamps instead of
/// collapsing them to a bare value plus one row-level timestamp pair. Covers type
/// mapping, schema shape, RowWriter (flat, nested, legacy, Bad readings, quality
/// changes, short input), the NoServerTS family, schema delete, subscription
/// batches and Projection errors. Needs no server and no native library.
Class OPCUA.Tests.Unit.MeasurementMetadataTest Extends OPCUA.Tests.MeasurementMetadataBase
{

// ==================== type mapping ====================

/// Every inferred type must land on a class that carries the metadata, and an
/// OPCUA.Types class the frontend already sent must pass through untouched.
Method TestTypeMapping()
{
    set tSvc = "OPCUA.REST.SchemaService"

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.DoubleDataValue"), "OPCUA.Types.DoubleDataValue", "DoubleDataValue passes through")

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.ArrayDataValue.Double"), "OPCUA.Types.ArrayDataValue.Double", "array DataValue passes through")

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "%Double"), "OPCUA.Types.DoubleDataValue", "%Double is wrapped")

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "%Boolean"), "OPCUA.Types.BooleanDataValue", "%Boolean is wrapped")

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", ""), "OPCUA.Types.StringDataValue", "unknown type falls back to a wrapper, not a bare string")

    // The whole point: nothing may map to a plain type any more.
    set tAnyPlain = 0
    for tIn = "", "%Double", "%Integer", "%Boolean", "%String", "%TimeStamp", "OPCUA.Types.StringDataValue" {
        set tOut = $classmethod(tSvc, "MapToDataValueType", tIn)
        if $Extract(tOut, 1) = "%" set tAnyPlain = 1
    }
    do $$$AssertEquals(tAnyPlain, 0, "no inferred type maps to a plain IRIS type")
}

// ==================== generated schema shape ====================

/// A generated schema must declare DataValue properties and must NOT declare
/// the old row-level timestamp pair, because timestamps are per measurement now.
Method TestSchemaShape()
{
    set tClass = ..#TestPackage_".ShapeSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpShapeSchema", 1)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        kill tType
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(tClass)
        for i=1:1:tCD.Properties.Count() {
            set tProp = tCD.Properties.GetAt(i)
            set tType(tProp.Name) = tProp.Type
        }

        do $$$AssertEquals($Get(tType("Alpha")), "OPCUA.Types.DoubleDataValue", "Alpha is a DataValue")
        do $$$AssertEquals($Get(tType("Beta")), "OPCUA.Types.IntegerDataValue", "Beta is a DataValue")
        do $$$AssertEquals($Get(tType("Gamma")), "OPCUA.Types.StringDataValue", "Gamma is a DataValue")
        // The compiler normalises %String to its fully qualified name.
        do $$$AssertEquals($Get(tType("NodePath")), "%Library.String", "NodePath stays a plain string")
        do $$$AssertEquals($Data(tType("ServerTimeStamp")), 0, "no row-level ServerTimeStamp")
        do $$$AssertEquals($Data(tType("SourceTimeStamp")), 0, "no row-level SourceTimeStamp")

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
        do $$$AssertEquals(tCount, 3, "projection records 3 columns")
        do $$$AssertEquals(tAllCode2, 1, "every column recorded as a full DataValue")

        // SQL must expose the four fields per measurement.
        kill tField
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT * FROM "_..TableName(tClass)_" WHERE 1=0")
        set tMeta = tRS.%GetMetadata()
        for i=1:1:tMeta.columnCount {
            set tField($ZConvert(tMeta.columns.GetAt(i).colName, "U")) = ""
        }
        for tName = "ALPHA_VALUE", "ALPHA_STATUS", "ALPHA_SOURCETS", "ALPHA_SERVERTS" {
            do $$$AssertEquals(''$Data(tField(tName)), 1, "SQL exposes "_tName)
        }
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== flat row assembly ====================

/// Give the writer three measurements with deliberately distinct metadata and
/// one unresolved column, then read the stored row back both ways.
Method TestFlatRow()
{
    set tClass = ..#TestPackage_".FlatSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpFlatSchema", 1)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not read columns: "_$System.Status.GetOneErrorText(tSC))
            quit
        }
        do $$$AssertEquals(tColCount, 3, "schema has 3 columns")

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
        do $$$AssertEquals($$$ISOK(tSC), 1, "writer initializes")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=DevA", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "row builds")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }
        do $$$AssertEquals(tResultIdx, 3, "the unresolved column consumed no result entry")

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do $$$AssertEquals($$$ISOK(tSC), 1, "row saves")
        quit:$$$ISERR(tSC)

        // --- object readback ---
        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals($IsObject(tObj), 1, "row opens as an object")
        quit:'$IsObject(tObj)

        do $$$AssertEquals(tObj.NodePath, "ns=1;s=DevA", "NodePath stored")
        do $$$AssertEquals(tObj.Alpha.Value, 21.5, "Alpha value")
        do $$$AssertEquals(tObj.Alpha.Status, 7, "Alpha status")
        do $$$AssertEquals(tObj.Alpha.SourceTimeStamp, "2026-01-01 00:00:01", "Alpha source timestamp")
        do $$$AssertEquals(tObj.Alpha.ServerTimeStamp, "2026-01-01 00:00:02", "Alpha server timestamp")

        // Isolation: Gamma must carry its OWN metadata, not Alpha's.
        do $$$AssertEquals(tObj.Gamma.Value, "hello", "Gamma value")
        do $$$AssertEquals(tObj.Gamma.Status, 9, "Gamma status is its own")
        do $$$AssertEquals(tObj.Gamma.SourceTimeStamp, "2026-02-02 11:11:11", "Gamma source timestamp is its own")
        do $$$AssertEquals(tObj.Gamma.ServerTimeStamp, "2026-02-02 11:11:12", "Gamma server timestamp is its own")

        // --- SQL readback ---
        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Alpha_Value, Alpha_Status, Alpha_SourceTS, Beta_Value, Gamma_Value, Gamma_Status "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%Next(), 1, "SQL returns the row")
        do $$$AssertEquals(tRS.%GetData(1), 21.5, "SQL Alpha_Value")
        do $$$AssertEquals(tRS.%GetData(2), 7, "SQL Alpha_Status")
        do $$$AssertEquals(tRS.%GetData(3), "2026-01-01 00:00:01", "SQL Alpha_SourceTS")
        do $$$AssertEquals(tRS.%GetData(4), "", "SQL Beta_Value is empty for the unresolved column")
        do $$$AssertEquals(tRS.%GetData(5), "hello", "SQL Gamma_Value")
        do $$$AssertEquals(tRS.%GetData(6), 9, "SQL Gamma_Status")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== nested row assembly ====================

/// A measurement inside a folder must keep its own metadata too: the folder
/// serial object holds DataValue serial objects, nested two levels deep.
Method TestNestedRow()
{
    set tClass = ..#TestPackage_".NestedSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpNestedMetaSchema", 0)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate nested schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        // The folder property must be a generated serial class whose own
        // properties are DataValues — not a DataValue itself.
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(tClass)
        set tFolderType = ""
        for i=1:1:tCD.Properties.Count() {
            if tCD.Properties.GetAt(i).Name = "Motor" set tFolderType = tCD.Properties.GetAt(i).Type
        }
        do $$$AssertEquals(tFolderType, ..#TestPackage_".NestedSchema.MotorType", "Motor is a generated serial class")
        if tFolderType '= "" {
            kill tSubType
            set tSD = ##class(%Dictionary.CompiledClass).%OpenId(tFolderType)
            if $IsObject(tSD) {
                for i=1:1:tSD.Properties.Count() {
                    set tSubType(tSD.Properties.GetAt(i).Name) = tSD.Properties.GetAt(i).Type
                }
            }
            do $$$AssertEquals($Get(tSubType("Temperature")), "OPCUA.Types.DoubleDataValue", "Motor.Temperature is a DataValue")
            do $$$AssertEquals($Get(tSubType("Speed")), "OPCUA.Types.IntegerDataValue", "Motor.Speed is a DataValue")
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        $$$ThrowOnError(tSC)
        do $$$AssertEquals(tColCount, 3, "nested schema exposes 3 leaf columns")

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
        do $$$AssertEquals($$$ISOK(tSC), 1, "nested writer initializes")
        quit:$$$ISERR(tSC)

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=2;s=AC1", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "nested row builds")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do $$$AssertEquals($$$ISOK(tSC), 1, "nested row saves")
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals($IsObject(tObj), 1, "nested row opens")
        quit:'$IsObject(tObj)

        do $$$AssertEquals(tObj.Humidity.Value, 45, "flat Humidity value survives alongside the folder")
        do $$$AssertEquals(tObj.Humidity.Status, 1, "flat Humidity status")
        do $$$AssertEquals(tObj.Motor.Temperature.Value, 21.5, "Motor.Temperature value")
        do $$$AssertEquals(tObj.Motor.Temperature.Status, 2, "Motor.Temperature status")
        do $$$AssertEquals(tObj.Motor.Temperature.SourceTimeStamp, "2026-03-03 02:02:02", "Motor.Temperature source timestamp")
        do $$$AssertEquals(tObj.Motor.Temperature.ServerTimeStamp, "2026-03-03 02:02:03", "Motor.Temperature server timestamp")
        do $$$AssertEquals(tObj.Motor.Speed.Status, 3, "Motor.Speed keeps its own metadata")
        do $$$AssertEquals(tObj.Motor.Speed.SourceTimeStamp, "2026-03-03 03:03:03", "Motor.Speed source timestamp is its own")

        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Motor_Temperature_Value, Motor_Temperature_SourceTS, Motor_Speed_Value, Humidity_Value "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%Next(), 1, "SQL returns the nested row")
        do $$$AssertEquals(tRS.%GetData(1), 21.5, "SQL Motor_Temperature_Value")
        do $$$AssertEquals(tRS.%GetData(2), "2026-03-03 02:02:02", "SQL Motor_Temperature_SourceTS")
        do $$$AssertEquals(tRS.%GetData(3), 1500, "SQL Motor_Speed_Value")
        do $$$AssertEquals(tRS.%GetData(4), 45, "SQL Humidity_Value")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== legacy plain schema ====================

/// A schema already deployed with plain columns and a row-level timestamp pair
/// must keep writing exactly as before — the change must not strand it.
/// A Bad reading carries a status and timestamps but no value:
/// $LB(sourceTS, serverTS, status, <null>). The generated schema must keep the
/// status, and a legacy plain schema must store NULL rather than fail on the
/// missing value.
Method TestBadReading()
{
    // 0x808A0000 BadNotConnected
    set tBad = $LB("2026-05-05 05:05:05", "2026-05-05 05:05:06", 2156527616, )

    set tClass = ..#TestPackage_".BadSchema"
    Try {
        $$$ThrowOnError(..BuildGeneratedSchema(tClass, "TmpBadSchema", 1))
        $$$ThrowOnError(..ColumnIndex(tClass, .tIdx, .tColCount))
        set tMask = "", tInput = $LB("")
        for i=1:1:tColCount {
            set tMask = tMask _ $LB(1)
            set tInput = tInput _ $LB($Select($LI(tIdx(i), 1) = "Alpha":tBad, 1:$LB("2026-05-05 05:05:05", "2026-05-05 05:05:06", 0, 1)))
        }
        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "DevA", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "row with a Bad reading builds")
        $$$ThrowOnError(tSC)
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))
        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals(tObj.Alpha.Status, 2156527616, "Bad reading keeps its status")
        do $$$AssertEquals(tObj.Alpha.SourceTimeStamp, "2026-05-05 05:05:05", "Bad reading keeps its source timestamp")
        do $$$AssertEquals(tObj.Alpha.Value, "", "Bad reading has no value")
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Alpha_Status, Alpha_Value FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%Next(), 1, "SQL returns the row")
        do $$$AssertEquals(tRS.%GetData(1), 2156527616, "SQL Alpha_Status is BadNotConnected")
        do $$$AssertEquals(tRS.%GetData(2), "", "SQL Alpha_Value is empty")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)

    set tClass = ..#TestPackage_".BadLegacySchema"
    Try {
        $$$ThrowOnError(..BuildLegacyPlainSchema(tClass))
        $$$ThrowOnError(..ColumnIndex(tClass, .tIdx, .tColCount))
        set tMask = "", tInput = $LB("")
        for i=1:1:tColCount {
            set tMask = tMask _ $LB(1)
            set tInput = tInput _ $LB(tBad)
        }
        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "Old", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "legacy row with a Bad reading builds")
        $$$ThrowOnError(tSC)
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))
        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals(tObj.Alpha, "", "legacy column stores NULL for a Bad reading")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

/// BuildRow reports a column only when its quality changes, per device, and
/// LogQualityChanges turns one device's changes into a single event-log line.
Method TestQualityChanges()
{
    set tClass = ..#TestPackage_".QualitySchema"
    Try {
        $$$ThrowOnError(..BuildGeneratedSchema(tClass, "TmpQualitySchema", 1))
        $$$ThrowOnError(..ColumnIndex(tClass, .tIdx, .tColCount))
        for i=1:1:tColCount { set tPos($LI(tIdx(i), 1)) = i }
        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))

        // Good, then Alpha BadNotConnected + Gamma UncertainLastUsableValue, the
        // same again, then all Good (Alpha as Good_Clamped, still Good).
        set tBad = 2156527616, tUncertain = 1083179008, tClamped = 3145728
        set tCycles = $LB($LB(0, 0, 0), $LB(tBad, 0, tUncertain), $LB(tBad, 0, tUncertain), $LB(tClamped, 0, 0))
        set tWantCounts = $LB(0, 2, 0, 2)
        for c=1:1:$LL(tCycles) {
            set tChanges = ..QualityCycle(tWriter, "DevA", .tPos, $LI(tCycles, c), $LB(1, 1, 1))
            do $$$AssertEquals($LL(tChanges), $LI(tWantCounts, c), "cycle "_c_" reports "_$LI(tWantCounts, c)_" change(s)")
            set tCycleChanges(c) = tChanges
        }
        set tAlpha = ""
        for i=1:1:$LL(tCycleChanges(2)) { set:$LI($LI(tCycleChanges(2), i), 1)=tPos("Alpha") tAlpha = $LI(tCycleChanges(2), i) }
        do $$$AssertEquals($LI(tAlpha, 2)_">"_$LI(tAlpha, 3), "0>2", "Alpha went Good -> Bad")
        do $$$AssertEquals($LI(tAlpha, 4), tBad, "Alpha change carries its status")

        // A second device has its own history: a Bad first reading is a change
        // with no previous severity; the masked-out column is never reported.
        set tChanges = ..QualityCycle(tWriter, "DevB", .tPos, $LB(tBad, tBad, 0), $LB(1, 0, 1))
        do $$$AssertEquals($LL(tChanges), 1, "new device, Bad first reading, masked column ignored")
        do $$$AssertEquals($LI($LI(tChanges, 1), 2), "", "first reading has no previous severity")

        // One log line for the device, naming the column and the status.
        // Counted by source class: looking up the status name may first load the
        // native library in this process, which logs a line of its own.
        set tBefore = +$Order(^Ens.Util.LogD(""), -1)
        do tWriter.LogQualityChanges("DevA", tCycleChanges(2))
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Util.Log WHERE ID > ? AND SourceClass = 'OPCUA.DataSource.RowWriter'", tBefore)
        set tEntries = 0, tLogId = ""
        while tRS.%Next() { set tEntries = tEntries + 1, tLogId = tRS.%GetData(1) }
        do $$$AssertEquals(tEntries, 1, "one event-log entry for the device")
        set tLog = ##class(Ens.Util.Log).%OpenId(tLogId)
        set tText = $Select($IsObject(tLog):tLog.Text, 1:"")
        do $$$AssertEquals($Select($IsObject(tLog):tLog.Type, 1:""), 3, "entry is a warning")
        do $$$AssertEquals(tText [ "Device 'DevA'", 1, "entry names the device")
        do $$$AssertEquals(tText [ "BadNotConnected", 1, "entry names the status")
        do $$$AssertEquals((tText [ "Alpha") && (tText [ "Gamma"), 1, "entry names both columns")
        do $$$LogMessage(tText)
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

Method TestLegacyPlainRow()
{
    set tClass = ..#TestPackage_".LegacySchema"
    Try {
        set tSC = ..BuildLegacyPlainSchema(tClass)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not build legacy schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        $$$ThrowOnError(tSC)
        do $$$AssertEquals(tColCount, 2, "legacy schema has 2 columns")

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
        do $$$AssertEquals($$$ISOK(tSC), 1, "legacy writer initializes")
        quit:$$$ISERR(tSC)

        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=Old", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "legacy row builds")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }

        set tSC = $classmethod(tClass, "SaveSourcedData", .tRow, .tId)
        do $$$AssertEquals($$$ISOK(tSC), 1, "legacy row saves")
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId)
        quit:'$IsObject(tObj)
        do $$$AssertEquals(tObj.Alpha, 12.25, "legacy column stores the bare value")
        do $$$AssertEquals(tObj.Beta, 99, "legacy second column stores the bare value")
        do $$$AssertEquals(tObj.SourceTimeStamp, "2026-04-04 04:04:04", "legacy row keeps its row-level source timestamp")
        do $$$AssertEquals(tObj.ServerTimeStamp, "2026-04-04 04:04:05", "legacy row keeps its row-level server timestamp")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== no server timestamp ====================

/// Every full measurement type has a NoServerTS counterpart without the
/// property, and the mapping goes both ways.
Method TestNoServerTSTypes()
{
    set tSvc = "OPCUA.REST.SchemaService"

    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.DoubleDataValue", 0), "OPCUA.Types.NoServerTS.DoubleDataValue", "DoubleDataValue maps to its counterpart")
    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.ArrayDataValue.Integer", 0), "OPCUA.Types.NoServerTS.ArrayDataValue.Integer", "array type maps to its counterpart")
    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "%Boolean", 0), "OPCUA.Types.NoServerTS.BooleanDataValue", "%Boolean maps to the counterpart wrapper")
    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "", 0), "OPCUA.Types.NoServerTS.StringDataValue", "unknown type falls back to the counterpart string")
    do $$$AssertEquals($classmethod(tSvc, "MapToDataValueType", "OPCUA.Types.NoServerTS.DoubleDataValue"), "OPCUA.Types.DoubleDataValue", "a counterpart sent with the default maps back to the full type")

    set tBad = ""
    set tAll = $LB("BooleanDataValue", "DoubleDataValue", "FloatDataValue", "IntegerDataValue", "StringDataValue", "TimeStampDataValue", "LocalizedTextDataValue", "NodeIdDataValue", "QualifiedNameDataValue", "Multidimensional", "ArrayDataValue.Boolean", "ArrayDataValue.Double", "ArrayDataValue.Float", "ArrayDataValue.Integer", "ArrayDataValue.String", "ArrayDataValue.TimeStamp")
    for iType=1:1:$LL(tAll) {
        set tShort = $LI(tAll, iType)
        set tFull = "OPCUA.Types."_tShort
        set tShortType = $classmethod(tSvc, "MapToDataValueType", tFull, 0)
        if tShortType '= ("OPCUA.Types.NoServerTS."_tShort) { set tBad = tBad_" "_tShort_"(map)" continue }
        if '##class(%Dictionary.CompiledClass).%ExistsId(tShortType) { set tBad = tBad_" "_tShort_"(missing)" continue }
        if ##class(%Dictionary.CompiledProperty).%ExistsId(tShortType_"||ServerTimeStamp") { set tBad = tBad_" "_tShort_"(has ServerTimeStamp)" continue }
        if '##class(OPCUA.DataSource.Resolver).IsMeasurementType(tShortType) { set tBad = tBad_" "_tShort_"(not a measurement)" continue }
        // Same payload, in the same order, one position earlier.
        set tFullVals = ..StorageValues(tFull), tShortVals = ..StorageValues(tShortType)
        if $LI(tShortVals, 3, *) '= $LI(tFullVals, 4, *) { set tBad = tBad_" "_tShort_"(payload)" }
    }
    do $$$AssertEquals(tBad, "", "every counterpart exists, lacks ServerTimeStamp, keeps the payload")
    do $$$AssertEquals(##class(OPCUA.DataSource.Resolver).OmitsServerTimeStamp("OPCUA.Types.DoubleDataValue"), 0, "full types are not flagged as omitting the server timestamp")
}

/// A flat schema created without server timestamps: no SQL column for them,
/// and each measurement keeps value, status, source timestamp and its whole
/// payload, including a two-field LocalizedText and a Bad reading's null value.
Method TestNoServerTSFlat()
{
    set tClass = ..#TestPackage_".NoSrvFlatSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpNoSrvFlatSchema", 2, 0)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        kill tType
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(tClass)
        for i=1:1:tCD.Properties.Count() {
            set tType(tCD.Properties.GetAt(i).Name) = tCD.Properties.GetAt(i).Type
        }
        do $$$AssertEquals($Get(tType("Alpha")), "OPCUA.Types.NoServerTS.DoubleDataValue", "Alpha is a NoServerTS DataValue")
        do $$$AssertEquals($Get(tType("Gamma")), "OPCUA.Types.NoServerTS.LocalizedTextDataValue", "Gamma is a NoServerTS LocalizedText")

        set tSpec = ##class(OPCUA.DataSource.Projection).GetOPCUAConfigSpec(tClass)
        set tEntries = $LI(tSpec, 3), tAllCode2 = 1, tCount = 0
        for i=2:1:$LL(tEntries) {
            set tEntry = $LI(tEntries, i)
            continue:tEntry=""
            set tCount = tCount + 1
            if $LI(tEntry, 1) '= 2 set tAllCode2 = 0
        }
        do $$$AssertEquals(tCount, 3, "projection records 3 columns")
        do $$$AssertEquals(tAllCode2, 1, "every column is still read as a full DataValue")

        set tFields = ..SqlFields(tClass)
        for tName = "ALPHA_VALUE", "ALPHA_STATUS", "ALPHA_SOURCETS", "GAMMA_TEXT", "GAMMA_LOCALE" {
            do $$$AssertEquals(tFields [ (","_tName_","), 1, "SQL exposes "_tName)
        }
        set tAnyServer = tFields [ "SERVERTS"
        do $$$AssertEquals(tAnyServer, 0, "SQL has no server timestamp column at all")

        $$$ThrowOnError(..ColumnIndex(tClass, .tIdx, .tColCount))
        set tMask = ""
        for i=1:1:tColCount {
            set tMask = tMask _ $LB($Select($LI(tIdx(i), 1) = "Beta": 0, 1: 1))
        }
        kill tWant
        set tWant("Alpha") = $LB("2026-01-01 00:00:01", "2026-01-01 00:00:02", 7, 21.5)
        set tWant("Gamma") = $LB("2026-02-02 11:11:11", "2026-02-02 11:11:12", 9, "Hallo", "de-DE")
        set tInput = $LB("")
        for i=1:1:tColCount {
            continue:'+$LI(tMask, i)
            set tInput = tInput _ $LB(tWant($LI(tIdx(i), 1)))
        }

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=DevA", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "row builds")
        $$$ThrowOnError(tSC)
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals($IsObject(tObj), 1, "row opens as an object")
        quit:'$IsObject(tObj)
        do $$$AssertEquals(tObj.Alpha.Value, 21.5, "Alpha value")
        do $$$AssertEquals(tObj.Alpha.Status, 7, "Alpha status")
        do $$$AssertEquals(tObj.Alpha.SourceTimeStamp, "2026-01-01 00:00:01", "Alpha source timestamp")
        do $$$AssertEquals(tObj.Beta.Value, "", "Beta is empty for the unresolved column")
        do $$$AssertEquals(tObj.Gamma.Text, "Hallo", "Gamma text")
        do $$$AssertEquals(tObj.Gamma.Locale, "de-DE", "Gamma locale (second payload field)")
        do $$$AssertEquals(tObj.Gamma.Status, 9, "Gamma status is its own")
        do $$$AssertEquals(tObj.Gamma.SourceTimeStamp, "2026-02-02 11:11:11", "Gamma source timestamp is its own")

        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Alpha_Value, Alpha_Status, Alpha_SourceTS, Beta_Value, Gamma_Text, Gamma_Locale, Gamma_Status "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%Next(), 1, "SQL returns the row")
        do $$$AssertEquals(tRS.%GetData(1), 21.5, "SQL Alpha_Value")
        do $$$AssertEquals(tRS.%GetData(2), 7, "SQL Alpha_Status")
        do $$$AssertEquals(tRS.%GetData(3), "2026-01-01 00:00:01", "SQL Alpha_SourceTS")
        do $$$AssertEquals(tRS.%GetData(4), "", "SQL Beta_Value is empty")
        do $$$AssertEquals(tRS.%GetData(5), "Hallo", "SQL Gamma_Text")
        do $$$AssertEquals(tRS.%GetData(6), "de-DE", "SQL Gamma_Locale")
        do $$$AssertEquals(tRS.%GetData(7), 9, "SQL Gamma_Status")

        // A Bad reading: status and source timestamp survive, the value is null.
        set tBadMask = "", tBadInput = $LB("")
        for i=1:1:tColCount {
            set tBadMask = tBadMask _ $LB(1)
            set tName = $LI(tIdx(i), 1)
            set tBadInput = tBadInput _ $LB($Case(tName,
                "Alpha":$LB("2026-05-05 05:05:05", "2026-05-05 05:05:06", 2156527616, ),
                "Beta":$LB("2026-05-05 05:05:05", "2026-05-05 05:05:06", 0, 3),
                :$LB("2026-05-05 05:05:05", "2026-05-05 05:05:06", 0, "x", "en")))
        }
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tBadInput, tBadMask, "ns=1;s=DevB", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "row with a Bad reading builds")
        $$$ThrowOnError(tSC)
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tBadId))
        set tObj = $classmethod(tClass, "%OpenId", tBadId)
        do $$$AssertEquals(tObj.Alpha.Status, 2156527616, "Bad reading keeps its status")
        do $$$AssertEquals(tObj.Alpha.SourceTimeStamp, "2026-05-05 05:05:05", "Bad reading keeps its source timestamp")
        do $$$AssertEquals(tObj.Alpha.Value, "", "Bad reading has no value")
        do $$$AssertEquals(tObj.Beta.Value, 3, "Beta beside it keeps its value")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

/// A folder's measurements lose the server timestamp too, and keep their own
/// value, status and source timestamp beside a flat column.
Method TestNoServerTSNested()
{
    set tClass = ..#TestPackage_".NoSrvNestedSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpNoSrvNestedSchema", 0, 0)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate nested schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }

        set tFolderType = tClass_".MotorType"
        do $$$AssertEquals(##class(%Dictionary.CompiledProperty).%OpenId(tFolderType_"||Temperature").Type, "OPCUA.Types.NoServerTS.DoubleDataValue", "Motor.Temperature is a NoServerTS DataValue")
        set tFields = ..SqlFields(tClass)
        for tName = "MOTOR_TEMPERATURE_VALUE", "MOTOR_TEMPERATURE_STATUS", "MOTOR_TEMPERATURE_SOURCETS", "HUMIDITY_SOURCETS" {
            do $$$AssertEquals(tFields [ (","_tName_","), 1, "SQL exposes "_tName)
        }
        do $$$AssertEquals(tFields [ ",MOTOR_TEMPERATURE_SERVERTS,", 0, "SQL has no Motor_Temperature_ServerTS")
        do $$$AssertEquals(tFields [ "SERVERTS", 0, "SQL has no server timestamp column at all")

        $$$ThrowOnError(..ColumnIndex(tClass, .tIdx, .tColCount))
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
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        set tSC = tWriter.BuildRow(.tInput, tMask, "ns=2;s=AC1", .tResultIdx, .tRow)
        do $$$AssertEquals($$$ISOK(tSC), 1, "nested row builds")
        $$$ThrowOnError(tSC)
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals($IsObject(tObj), 1, "nested row opens")
        quit:'$IsObject(tObj)
        do $$$AssertEquals(tObj.Humidity.Value, 45, "flat Humidity value")
        do $$$AssertEquals(tObj.Humidity.SourceTimeStamp, "2026-03-03 01:01:01", "flat Humidity source timestamp")
        do $$$AssertEquals(tObj.Motor.Temperature.Value, 21.5, "Motor.Temperature value")
        do $$$AssertEquals(tObj.Motor.Temperature.Status, 2, "Motor.Temperature status")
        do $$$AssertEquals(tObj.Motor.Temperature.SourceTimeStamp, "2026-03-03 02:02:02", "Motor.Temperature source timestamp")
        do $$$AssertEquals(tObj.Motor.Speed.Value, 1500, "Motor.Speed value")
        do $$$AssertEquals(tObj.Motor.Speed.Status, 3, "Motor.Speed keeps its own metadata")
        do $$$AssertEquals(tObj.Motor.Speed.SourceTimeStamp, "2026-03-03 03:03:03", "Motor.Speed source timestamp is its own")

        set tRS = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Motor_Temperature_Value, Motor_Temperature_SourceTS, Motor_Speed_Status, Humidity_Value "_
            "FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%Next(), 1, "SQL returns the nested row")
        do $$$AssertEquals(tRS.%GetData(1), 21.5, "SQL Motor_Temperature_Value")
        do $$$AssertEquals(tRS.%GetData(2), "2026-03-03 02:02:02", "SQL Motor_Temperature_SourceTS")
        do $$$AssertEquals(tRS.%GetData(3), 3, "SQL Motor_Speed_Status")
        do $$$AssertEquals(tRS.%GetData(4), 45, "SQL Humidity_Value")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== short input ====================

/// An empty slot in a poll result stores NULL for that one column, and the
/// device after it is still built. A result list of the wrong length is refused
/// by CheckInput, because every reading after a gap would shift columns.
Method TestShortInput()
{
    set tClass = ..#TestPackage_".ShortInputSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpShortInputSchema", 1)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }
        set tSC = ..ColumnIndex(tClass, .tIdx, .tColCount)
        $$$ThrowOnError(tSC)

        // Two devices, every column resolved. Device 1's second reading is an
        // empty slot; everything else is a real DataValue.
        set tMask = ""
        for i=1:1:tColCount { set tMask = tMask _ $LB(1) }
        set tMasks = $LB(tMask, tMask)
        set tInput = $LB("")
        for iDev=1:1:2 {
            for i=1:1:tColCount {
                if (iDev = 1) && (i = 2) {
                    // $LB() is one undefined element: what $List throws on
                    set tInput = tInput _ $LB()
                    continue
                }
                set tInput = tInput _ $LB($LB("2026-04-04 04:04:0"_iDev, "2026-04-04 04:04:0"_iDev, 0, $Select($LI(tIdx(i), 1) = "Gamma":"g"_iDev, 1:(iDev * 10) + i)))
            }
        }
        do $$$AssertEquals($ListData(tInput, 3), 0, "slot 3 is empty")

        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))

        set tResultIdx = 1
        for iDev=1:1:2 {
            set tSC = tWriter.BuildRow(.tInput, tMask, "ns=1;s=Dev"_iDev, .tResultIdx, .tRow)
            do $$$AssertEquals($$$ISOK(tSC), 1, "device "_iDev_" row builds")
            if $$$ISERR(tSC) {
                do $$$LogMessage($System.Status.GetOneErrorText(tSC))
                quit
            }
            $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tNewId))
            set tId(iDev) = tNewId
        }
        quit:$$$ISERR(tSC)

        set tObj = $classmethod(tClass, "%OpenId", tId(1))
        do $$$AssertEquals($IsObject(tObj), 1, "device 1 row opens")
        quit:'$IsObject(tObj)
        set tName2 = $LI(tIdx(2), 1), tName3 = $LI(tIdx(3), 1)
        do $$$AssertEquals($Property($Property(tObj, tName2), "Value"), "", "device 1 empty slot stores NULL")
        do $$$AssertEquals($Property($Property(tObj, tName3), "Value"), $Select(tName3 = "Gamma":"g1", 1:13), "device 1 next column keeps its own value")

        set tObj = $classmethod(tClass, "%OpenId", tId(2))
        do $$$AssertEquals($IsObject(tObj), 1, "device 2 row opens")
        quit:'$IsObject(tObj)
        do $$$AssertEquals($Property($Property(tObj, tName2), "Value"), $Select(tName2 = "Gamma":"g2", 1:22), "device 2 keeps its own value")

        do $$$AssertEquals($$$ISOK(tWriter.CheckInput(.tInput, tMasks)), 1, "CheckInput accepts a full list")

        // A dropped reading makes the list one short: refused, not shifted.
        set tShort = $List(tInput, 1, $LL(tInput) - 1)
        set tSC = tWriter.CheckInput(.tShort, tMasks)
        do $$$AssertEquals($$$ISERR(tSC), 1, "CheckInput refuses a short list")
        do $$$AssertEquals($System.Status.GetOneErrorText(tSC) [ "Got 5 readings for 6 resolved columns", 1, "refusal gives both counts")
        set tEmpty = ""
        do $$$AssertEquals($$$ISERR(tWriter.CheckInput(.tEmpty, tMasks)), 1, "CheckInput refuses an empty result")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== subscription batches ====================

/// A failed notification is counted the same wherever it sits in the batch, and
/// never becomes the batch's status. OnTask used to keep only the last
/// notification's status, so a failure in last place sent a mostly successful
/// batch down the connection-error path, and one anywhere else was only traced.
Method TestSubscriptionBatch()
{
    Try {
        set tAdapter = ##class(OPCUA.Adapter.TCPSubscriptionInboundAdapter).%New()
        for tCase = "last", "first", "two", "throw", "clean" {
            set tHost = ##class(OPCUA.Tests.FakeBatchHost).%New()
            set tAdapter.BusinessHost = tHost
            set tBatch = $Case(tCase, "last":$LB("n1", "n2", "bad3"), "first":$LB("bad1", "n2", "n3"), "two":$LB("n1", "bad2", "bad3"), "throw":$LB("throw", "n2", "n3"), :$LB("n1", "n2", "n3"))
            set tWant = $Case(tCase, "last":"failed bad3", "first":"failed bad1", "two":"failed bad2", "throw":"thrown by throw", :"")

            do tAdapter.ProcessBatch(tBatch, 3, .tDone, .tErrors, .tFirst)
            do $$$AssertEquals($ListToString(tHost.Received), $ListToString(tBatch), tCase_": every notification handed in")
            do $$$AssertEquals(tDone, $Case(tCase, "two":1, "clean":3, :2), tCase_": processed count")
            do $$$AssertEquals(tErrors, $Case(tCase, "two":2, "clean":0, :1), tCase_": error count")
            do $$$AssertEquals($$$ISERR(tFirst), (tWant '= ""), tCase_": first error set only on failure")
            do $$$AssertEquals($Select($$$ISOK(tFirst):"", 1:$System.Status.GetOneErrorText(tFirst)) [ tWant, 1, tCase_": first error is the first failure")
            do $$$AssertEquals(tHost.%WaitForNextCallInterval, 1, tCase_": wait flag set")
        }
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
}

// ==================== projection errors ====================

/// A property with no OPCUANAMESPACE, and no class default, fails the compile
/// with the Projection's own message. It used to fail with <UNDEFINED> cls. A
/// schema with no data columns compiles: ProcessObj used to throw <UNDEFINED> tSC.
Method TestProjectionErrors()
{
    set tClass = ..#TestPackage_".ProjectionSchema"
    Try {
        set tSC = ..CompileDefinition(tClass, "Temp", 0)
        do $$$AssertEquals($$$ISERR(tSC), 1, "missing namespace fails the compile")
        set tText = $System.Status.GetErrorText(tSC)
        do $$$AssertEquals(tText [ "OPCUANAMESPACE parameter is not defined for property Temp", 1, "error is the Projection's message")
        do $$$AssertEquals(tText [ "OPCUDEFAULTANAMESPACE", 1, "error names the real class parameter")
        do $$$AssertEquals(tText [ "<UNDEFINED>", 0, "error is not an <UNDEFINED>")
        do ..DropSchema(tClass)

        set tSC = ..CompileDefinition(tClass, "NodePath", 1)
        do $$$AssertEquals($$$ISOK(tSC), 1, "schema with no data columns compiles")
        if $$$ISERR(tSC) do $$$LogMessage($System.Status.GetErrorText(tSC))
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

// ==================== schema delete ====================

/// Deleting a schema removes its rows. The data global is named after the
/// class, so rows left behind would reappear in a new schema of the same name.
Method TestSchemaDelete()
{
    set tClass = ..#TestPackage_".DeleteSchema"
    Try {
        set tSC = ..BuildGeneratedSchema(tClass, "TmpDeleteSchema", 0)
        if $$$ISERR(tSC) {
            do $$$AssertFailure("could not generate schema: "_$System.Status.GetOneErrorText(tSC))
            quit
        }
        set tGlobal = $LI(^OPCUA.DataSource(tClass), 2)
        set tSerial = ##class(%Dictionary.CompiledProperty).%OpenId(tClass_"||Motor").Type

        // Element 1 is the %%CLASSNAME slot, empty as in every RowWriter row.
        set tRow = $LB("")
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))
        do $$$AssertEquals($Data(@tGlobal) > 0, 1, "row is stored before delete")

        set tSC = ##class(OPCUA.REST.SchemaService).Delete({"className": (tClass)}, .tResult)
        do $$$AssertEquals($$$ISOK(tSC), 1, "Delete succeeds")
        if $$$ISERR(tSC) {
            do $$$LogMessage($System.Status.GetOneErrorText(tSC))
            quit
        }
        do $$$AssertEquals(tResult.deleted, 1, "Delete reports deleted")
        do $$$AssertEquals($Data(@tGlobal), 0, "data global is gone")
        do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%ExistsId(tClass), 0, "schema class is gone")
        do $$$AssertEquals(##class(%Dictionary.ClassDefinition).%ExistsId(tSerial), 0, "folder serial class is gone")
        do $$$AssertEquals($Data(^OPCUA.DataSource(tClass)), 0, "projection entry is gone")

        // A new schema with the same name, and a different layout, must start empty.
        set tCols = []
        do tCols.%Push(..Column("Pressure", "OPCUA.Types.DoubleDataValue", $LB("Pressure")))
        $$$ThrowOnError(##class(OPCUA.REST.SchemaService).GenerateSchemaClass(tClass, "TmpDeleteSchema", tCols, 1, .tColNS, .tSerials))
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName(tClass))
        do tRS.%Next()
        do $$$AssertEquals(tRS.%GetData(1), 0, "recreated schema has no rows")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }
    do ..DropSchema(tClass)
}

}
