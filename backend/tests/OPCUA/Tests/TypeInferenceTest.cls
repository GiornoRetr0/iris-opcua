Include (OPCUA.Constants, %occInclude)

/// Tests that a column is typed from the node's declared DataType and ValueRank
/// (<method>OPCUA.DataSource.Generator.InferType</method>) rather than guessed
/// from what its value looks like.
///
/// Run against the docker-compose servers:
///   zn "OPCUA"
///   write ##class(OPCUA.Tests.TypeInferenceTest).Run()
///
/// The mapping section needs no server. The plc section covers a server that
/// leaves ValueRank open (-2), so the shape comes from the value. The
/// certified-server sections cover every built-in type as scalar, array and
/// matrix, including the values a guess gets wrong (a Boolean, Float or Double
/// that reads 0), and then store a row of the newly reachable types end to end;
/// they are skipped if the secure connection cannot be made.
Class OPCUA.Tests.TypeInferenceTest
{

/// Package the throwaway generated classes live in.
Parameter TestPackage = "OPCUA.Tests.Tmp";

/// Run the whole suite. Returns 1 if every test passed.
ClassMethod Run(pPlcURL As %String = "opc.tcp://plc", pSecureURL As %String = "opc.tcp://certified-server") As %Boolean
{
    set tPass = 0, tFail = 0

    write !, "=== DataType mapping (offline) ===", !
    do ..TestMapping(.tPass, .tFail)

    write !, "=== Open ValueRank against ", pPlcURL, " ===", !
    do ..TestPlc(pPlcURL, .tPass, .tFail)

    write !, "=== Declared types against ", pSecureURL, " ===", !
    do ..TestCertified(pSecureURL, .tPass, .tFail)

    write !, "=== Inferred types store a row, against ", pSecureURL, " ===", !
    do ..TestStorage(pSecureURL, .tPass, .tFail)

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

// ==================== mapping ====================

ClassMethod TestMapping(ByRef pPass, ByRef pFail) [ Private ]
{
    set tGen = "OPCUA.DataSource.Generator"
    // $LB(label, dataType, dimensions, expected)
    set tCases = $LB(
        $LB("Boolean", 1, 0, "OPCUA.Types.BooleanDataValue"),
        $LB("SByte", 2, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("UInt64", 9, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("Float", 10, 0, "OPCUA.Types.FloatDataValue"),
        $LB("Double", 11, 0, "OPCUA.Types.DoubleDataValue"),
        $LB("String", 12, 0, "OPCUA.Types.StringDataValue"),
        $LB("DateTime", 13, 0, "OPCUA.Types.TimeStampDataValue"),
        $LB("XmlElement", 16, 0, "OPCUA.Types.StringDataValue"),
        $LB("NodeId", 17, 0, "OPCUA.Types.NodeIdDataValue"),
        $LB("StatusCode", 19, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("QualifiedName", 20, 0, "OPCUA.Types.QualifiedNameDataValue"),
        $LB("LocalizedText", 21, 0, "OPCUA.Types.LocalizedTextDataValue"),
        $LB("Duration (subtype of Double)", 290, 0, "OPCUA.Types.DoubleDataValue"),
        $LB("UtcTime (subtype of DateTime)", 294, 0, "OPCUA.Types.TimeStampDataValue"),
        $LB("Boolean array", 1, 1, "OPCUA.Types.ArrayDataValue.Boolean"),
        $LB("Double array", 11, 1, "OPCUA.Types.ArrayDataValue.Double"),
        $LB("DateTime array", 13, 1, "OPCUA.Types.ArrayDataValue.TimeStamp"),
        $LB("NodeId array (no typed class)", 17, 1, "OPCUA.Types.Multidimensional"),
        $LB("Double matrix", 11, 2, "OPCUA.Types.Multidimensional"),
        $LB("Guid (unknown) falls back", 14, 0, ""),
        $LB("abstract Integer falls back", 27, 0, ""),
        $LB("other-namespace type falls back", "", 0, ""))
    for i=1:1:$LL(tCases) {
        set tCase = $LI(tCases, i)
        do ..Check($LI(tCase, 1), $ClassMethod(tGen, "MapDataTypeToIRIS", $LI(tCase, 2), $LI(tCase, 3)), $LI(tCase, 4), .pPass, .pFail)
    }

    // Every class the map can return must be a measurement class the schema
    // generator accepts as-is, or the column would silently become text.
    for tClass = "OPCUA.Types.NodeIdDataValue", "OPCUA.Types.QualifiedNameDataValue", "OPCUA.Types.LocalizedTextDataValue", "OPCUA.Types.Multidimensional", "OPCUA.Types.ArrayDataValue.TimeStamp", "OPCUA.Types.ArrayDataValue.Float" {
        do ..Check(tClass_" kept by MapToDataValueType", ##class(OPCUA.REST.SchemaService).MapToDataValueType(tClass), tClass, .pPass, .pFail)
    }
}

// ==================== live ====================

/// The mock server declares DataType Int64 but ValueRank Any (-2), so the
/// scalar shape has to come from the value.
ClassMethod TestPlc(pURL As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    set tClient = ..Connect(pURL, 0)
    if '$IsObject(tClient) {
        do ..Check("connect to "_pURL, 0, 1, .pPass, .pFail)
        quit
    }
    set tGen = "OPCUA.DataSource.Generator"
    do ..Check("SA1 (Int64, ValueRank -2)", $ClassMethod(tGen, "InferType", tClient, 1, "SA1", $$$OpcuaNodeIdTypeString), "OPCUA.Types.IntegerDataValue", .pPass, .pFail)
    do ..Check("missing node falls back to text", $ClassMethod(tGen, "InferType", tClient, 1, "NoSuchNode", $$$OpcuaNodeIdTypeString), "OPCUA.Types.StringDataValue", .pPass, .pFail)
    do tClient.Disconnect()
}

ClassMethod TestCertified(pURL As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    set tClient = ..Connect(pURL, 1)
    if '$IsObject(tClient) {
        write "  skip no secure connection to ", pURL, !
        quit
    }
    set tGen = "OPCUA.DataSource.Generator"
    // The open62541 demo server's Demo/Scalar, Demo/Array and Demo/Matrix folders.
    // Each Scalar node reads 0 / empty, which is exactly what a guess mistypes.
    // $LB(label, numeric node id in ns=1, expected)
    set tCases = $LB(
        $LB("Boolean reading 0", 51001, "OPCUA.Types.BooleanDataValue"),
        $LB("Byte", 51007, "OPCUA.Types.IntegerDataValue"),
        $LB("Float reading 0.0", 51028, "OPCUA.Types.FloatDataValue"),
        $LB("Double reading 0.0", 51031, "OPCUA.Types.DoubleDataValue"),
        $LB("empty String", 51034, "OPCUA.Types.StringDataValue"),
        $LB("DateTime", 51037, "OPCUA.Types.TimeStampDataValue"),
        $LB("NodeId", 51049, "OPCUA.Types.NodeIdDataValue"),
        $LB("LocalizedText", 51061, "OPCUA.Types.LocalizedTextDataValue"),
        $LB("Boolean array", 51002, "OPCUA.Types.ArrayDataValue.Boolean"),
        $LB("Int32 array", 51017, "OPCUA.Types.ArrayDataValue.Integer"),
        $LB("Double array", 51032, "OPCUA.Types.ArrayDataValue.Double"),
        $LB("Boolean matrix", 51003, "OPCUA.Types.Multidimensional"),
        $LB("folder is not a variable, falls back", 50001, "OPCUA.Types.StringDataValue"))
    for i=1:1:$LL(tCases) {
        set tCase = $LI(tCases, i)
        do ..Check($LI(tCase, 1), $ClassMethod(tGen, "InferType", tClient, 1, $LI(tCase, 2), $$$OpcuaNodeIdTypeNumeric), $LI(tCase, 3), .pPass, .pFail)
    }
    do ..Check("string node id", $ClassMethod(tGen, "InferType", tClient, 1, "the.answer", $$$OpcuaNodeIdTypeString), "OPCUA.Types.IntegerDataValue", .pPass, .pFail)
    do tClient.Disconnect()
}

/// Infer, generate, resolve, poll, write and read back a schema whose columns
/// use the classes only DataType inference produces -- Boolean, NodeId,
/// QualifiedName, LocalizedText, a TimeStamp array and a matrix -- so each is
/// shown to store, not merely to be named.
ClassMethod TestStorage(pURL As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    set tClient = ..Connect(pURL, 1)
    if '$IsObject(tClient) {
        write "  skip no secure connection to ", pURL, !
        quit
    }
    set tClass = ..#TestPackage_".TypeStorage"
    set tHandle = ""
    Try {
        // The device is the Demo folder (ns=1;i=50000); columns sit one folder down.
        // $LB(folder, node name, numeric node id)
        set tNodes = $LB($LB("Scalar", "Boolean", 51001), $LB("Scalar", "Double", 51031), $LB("Scalar", "NodeId", 51049),
            $LB("Scalar", "QualifiedName", 51058), $LB("Scalar", "LocalizedText", 51061), $LB("Scalar", "DateTime", 51037),
            $LB("Array", "Int32", 51017), $LB("Array", "DateTime", 51038), $LB("Matrix", "Double", 51033))
        set tCols = []
        for i=1:1:$LL(tNodes) {
            set tNode = $LI(tNodes, i)
            set tType = ##class(OPCUA.DataSource.Generator).InferType(tClient, 1, $LI(tNode, 3), $$$OpcuaNodeIdTypeNumeric)
            set tCol = {"displayName": ($LI(tNode, 2)), "inferredType": (tType), "relativePath": [($LI(tNode, 1)), ($LI(tNode, 2))]}
            do tCols.%Push(tCol)
        }

        do ..DropSchema(tClass)
        set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(tClass, "TmpTypeStorage", tCols, 1, .tColNS, .tSerial)
        do ..Check("schema generates from inferred types", $$$ISOK(tSC), 1, .pPass, .pFail)
        if $$$ISERR(tSC) { write "       ", $System.Status.GetOneErrorText(tSC), ! quit }

        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("ns=1;i=50000|Demo", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do ..Check("every column resolves", $$$ISOK(tSC) && ($LI(tMasks, 1) = $LB(1,1,1,1,1,1,1,1,1)), 1, .pPass, .pFail)
        quit:$$$ISERR(tSC)

        $$$ThrowOnError(tClient.ReadBulkSetupC(.tHandle, tSpec))
        $$$ThrowOnError(tClient.ReadBulkPollC(.tList, tHandle))
        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        $$$ThrowOnError(tWriter.BuildRow(.tList, $LI(tMasks, 1), "Demo", .tResultIdx, .tRow))
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do ..Check("row opens", $IsObject(tObj), 1, .pPass, .pFail)
        quit:'$IsObject(tObj)
        do ..Check("Boolean column is a BooleanDataValue", tObj.Scalar.Boolean.%ClassName(1), "OPCUA.Types.BooleanDataValue", .pPass, .pFail)
        do ..Check("Boolean value stored", tObj.Scalar.Boolean.Value, 0, .pPass, .pFail)
        do ..Check("Boolean keeps its server timestamp", tObj.Scalar.Boolean.ServerTimeStamp '= "", 1, .pPass, .pFail)
        do ..Check("Double column is a DoubleDataValue", tObj.Scalar.Double.%ClassName(1), "OPCUA.Types.DoubleDataValue", .pPass, .pFail)
        do ..Check("NodeId stores its identifier type", tObj.Scalar.NodeId.IdentifierType, 0, .pPass, .pFail)
        do ..Check("NodeId stores its namespace", tObj.Scalar.NodeId.Namespace, 0, .pPass, .pFail)
        do ..Check("QualifiedName column is a QualifiedNameDataValue", tObj.Scalar.QualifiedName.%ClassName(1), "OPCUA.Types.QualifiedNameDataValue", .pPass, .pFail)
        do ..Check("LocalizedText column is a LocalizedTextDataValue", tObj.Scalar.LocalizedText.%ClassName(1), "OPCUA.Types.LocalizedTextDataValue", .pPass, .pFail)
        do ..Check("DateTime stored", tObj.Scalar.DateTime.Value '= "", 1, .pPass, .pFail)
        do ..Check("Int32 array keeps all 10 elements", tObj.Array.Int32.Values.Count(), 10, .pPass, .pFail)
        do ..Check("DateTime array keeps all 10 elements", tObj.Array.DateTime.Values.Count(), 10, .pPass, .pFail)
        do ..Check("matrix is a Multidimensional", tObj.Matrix.Double.%ClassName(1), "OPCUA.Types.Multidimensional", .pPass, .pFail)
        do ..Check("matrix records 2 dimensions", tObj.Matrix.Double.NumberOfDimensions, 2, .pPass, .pFail)
        do ..Check("matrix rows are lists", $ListValid($ListGet(tObj.Matrix.Double.Values, 1)), 1, .pPass, .pFail)

        // And the SQL projection reads the same row.
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Scalar_Boolean_Value, Scalar_Boolean_ServerTS, Scalar_NodeId_IdentifierType, Matrix_Double_NumberOfDimensions FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do ..Check("SQL query runs", tRS.%SQLCODE, 0, .pPass, .pFail)
        if tRS.%Next() {
            do ..Check("SQL sees the Boolean value", tRS.%GetData(1), 0, .pPass, .pFail)
            do ..Check("SQL sees the Boolean server timestamp", tRS.%GetData(2) '= "", 1, .pPass, .pFail)
            do ..Check("SQL sees the NodeId identifier type", tRS.%GetData(3), 0, .pPass, .pFail)
            do ..Check("SQL sees the matrix dimensions", tRS.%GetData(4), 2, .pPass, .pFail)
        } else {
            do ..Check("SQL returns the row", 0, 1, .pPass, .pFail)
        }
    } Catch (e) {
        set pFail = pFail + 1
        write "  FAIL ", e.DisplayString(), !
    }
    if tHandle '= "" { Try { do tClient.ReadBulkClear(tHandle) } Catch (eClear) {} }
    do tClient.Disconnect()
    do ..DropSchema(tClass)
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

/// A connected client, or "" if the connection could not be made.
ClassMethod Connect(pURL As %String, pSecure As %Boolean) As OPCUA.Client [ Private ]
{
    set tClient = ""
    Try {
        do ##class(OPCUA.Utils).Initialize()
        set tClient = ##class(OPCUA.Client).%New()
        $$$ThrowOnError(tClient.Initialize())
        if pSecure {
            set tCerts = "/usr/irissys/uac/certs/"
            $$$ThrowOnError(tClient.SetupClient(, $$$OpcuaMessageSecurityModeSignAndEncrypt, "urn:secuac", tCerts_"secuac.crt.der", tCerts_"secuac.key.der", tCerts_"trustdir", tCerts_"crldir"))
            $$$ThrowOnError(tClient.Connect(pURL, "user1", "password"))
        } else {
            $$$ThrowOnError(tClient.SetupClient())
            $$$ThrowOnError(tClient.Connect(pURL))
        }
    } Catch (e) {
        set tClient = ""
    }
    quit tClient
}

}
