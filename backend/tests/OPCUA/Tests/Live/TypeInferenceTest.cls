Include (OPCUA.Constants, %occInclude)

/// Live half of the type-inference suite: a column is typed from the node's
/// declared DataType and ValueRank (<method>OPCUA.DataSource.Generator.InferType</method>)
/// rather than guessed from its value.
///
/// TestPlc covers a server that leaves ValueRank open (-2), so the shape comes
/// from the value. TestCertified and TestStorage cover every built-in type as
/// scalar, array and matrix on certified-server, including the values a guess gets
/// wrong (a Boolean, Float or Double that reads 0), and store a row of them end to
/// end. When certified-server cannot be reached they report <b>skipped</b>, never
/// passed; any other connect failure (certificate, credentials, library) fails. Its URL is <tt>^||OPCUA.Tests("secureUrl")</tt>, default
/// <tt>opc.tcp://certified-server</tt>.
Class OPCUA.Tests.Live.TypeInferenceTest Extends %UnitTest.TestCase
{

/// The plc server, as set by <method>OPCUA.Tests.Runner.Live</method>.
ClassMethod URL() As %String [ CodeMode = expression ]
{
$Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

/// The secured certified-server.
ClassMethod SecureURL() As %String [ CodeMode = expression ]
{
$Get(^||OPCUA.Tests("secureUrl"), "opc.tcp://certified-server")
}

/// Package the throwaway generated classes live in.
Parameter TestPackage = "OPCUA.Tests.Tmp";

// ==================== live ====================
/// The mock server declares DataType Int64 but ValueRank Any (-2), so the
/// scalar shape has to come from the value.
Method TestPlc()
{
    set pURL = ..URL()
    set tClient = ..Connect(pURL, 0, .tConnSC)
    if '$IsObject(tClient) {
        do $$$AssertFailure("connect to "_pURL_": "_$System.Status.GetErrorText(tConnSC))
        quit
    }
    set tGen = "OPCUA.DataSource.Generator"
    do $$$AssertEquals($ClassMethod(tGen, "InferType", tClient, 1, "SA1", $$$OpcuaNodeIdTypeString), "OPCUA.Types.IntegerDataValue", "SA1 (Int64, ValueRank -2)")
    do $$$AssertEquals($ClassMethod(tGen, "InferType", tClient, 1, "NoSuchNode", $$$OpcuaNodeIdTypeString), "OPCUA.Types.StringDataValue", "missing node falls back to text")
    do tClient.Disconnect()
}

Method TestCertified()
{
    set pURL = ..SecureURL()
    set tClient = ..Connect(pURL, 1, .tConnSC)
    if '$IsObject(tClient) {
        do ..NotConnected(pURL, tConnSC)
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
        do $$$AssertEquals($ClassMethod(tGen, "InferType", tClient, 1, $LI(tCase, 2), $$$OpcuaNodeIdTypeNumeric), $LI(tCase, 3), $LI(tCase, 1))
    }
    do $$$AssertEquals($ClassMethod(tGen, "InferType", tClient, 1, "the.answer", $$$OpcuaNodeIdTypeString), "OPCUA.Types.IntegerDataValue", "string node id")
    do tClient.Disconnect()
}

/// Infer, generate, resolve, poll, write and read back a schema whose columns
/// use the classes only DataType inference produces -- Boolean, NodeId,
/// QualifiedName, LocalizedText, a TimeStamp array and a matrix -- so each is
/// shown to store, not merely to be named.
Method TestStorage()
{
    set pURL = ..SecureURL()
    set tClient = ..Connect(pURL, 1, .tConnSC)
    if '$IsObject(tClient) {
        do ..NotConnected(pURL, tConnSC)
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
        do $$$AssertEquals($$$ISOK(tSC), 1, "schema generates from inferred types")
        if $$$ISERR(tSC) { do $$$LogMessage($System.Status.GetOneErrorText(tSC)) quit }

        do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("ns=1;i=50000|Demo", .tDevices, .tErrors)
        set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClass, tDevices, .tSpec, .tMasks, .tDiag)
        do $$$AssertEquals($$$ISOK(tSC) && ($LI(tMasks, 1) = $LB(1,1,1,1,1,1,1,1,1)), 1, "every column resolves")
        quit:$$$ISERR(tSC)

        $$$ThrowOnError(tClient.ReadBulkSetupC(.tHandle, tSpec))
        $$$ThrowOnError(tClient.ReadBulkPollC(.tList, tHandle))
        set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
        $$$ThrowOnError(tWriter.Initialize(tClass))
        set tResultIdx = 1
        $$$ThrowOnError(tWriter.BuildRow(.tList, $LI(tMasks, 1), "Demo", .tResultIdx, .tRow))
        $$$ThrowOnError($classmethod(tClass, "SaveSourcedData", .tRow, .tId))

        set tObj = $classmethod(tClass, "%OpenId", tId)
        do $$$AssertEquals($IsObject(tObj), 1, "row opens")
        quit:'$IsObject(tObj)
        do $$$AssertEquals(tObj.Scalar.Boolean.%ClassName(1), "OPCUA.Types.BooleanDataValue", "Boolean column is a BooleanDataValue")
        do $$$AssertEquals(tObj.Scalar.Boolean.Value, 0, "Boolean value stored")
        do $$$AssertEquals(tObj.Scalar.Boolean.ServerTimeStamp '= "", 1, "Boolean keeps its server timestamp")
        do $$$AssertEquals(tObj.Scalar.Double.%ClassName(1), "OPCUA.Types.DoubleDataValue", "Double column is a DoubleDataValue")
        do $$$AssertEquals(tObj.Scalar.NodeId.IdentifierType, 0, "NodeId stores its identifier type")
        do $$$AssertEquals(tObj.Scalar.NodeId.Namespace, 0, "NodeId stores its namespace")
        do $$$AssertEquals(tObj.Scalar.QualifiedName.%ClassName(1), "OPCUA.Types.QualifiedNameDataValue", "QualifiedName column is a QualifiedNameDataValue")
        do $$$AssertEquals(tObj.Scalar.LocalizedText.%ClassName(1), "OPCUA.Types.LocalizedTextDataValue", "LocalizedText column is a LocalizedTextDataValue")
        do $$$AssertEquals(tObj.Scalar.DateTime.Value '= "", 1, "DateTime stored")
        do $$$AssertEquals(tObj.Array.Int32.Values.Count(), 10, "Int32 array keeps all 10 elements")
        do $$$AssertEquals(tObj.Array.DateTime.Values.Count(), 10, "DateTime array keeps all 10 elements")
        do $$$AssertEquals(tObj.Matrix.Double.%ClassName(1), "OPCUA.Types.Multidimensional", "matrix is a Multidimensional")
        do $$$AssertEquals(tObj.Matrix.Double.NumberOfDimensions, 2, "matrix records 2 dimensions")
        do $$$AssertEquals($ListValid($ListGet(tObj.Matrix.Double.Values, 1)), 1, "matrix rows are lists")

        // And the SQL projection reads the same row.
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Scalar_Boolean_Value, Scalar_Boolean_ServerTS, Scalar_NodeId_IdentifierType, Matrix_Double_NumberOfDimensions FROM "_..TableName(tClass)_" WHERE ID = ?", tId)
        do $$$AssertEquals(tRS.%SQLCODE, 0, "SQL query runs")
        if tRS.%Next() {
            do $$$AssertEquals(tRS.%GetData(1), 0, "SQL sees the Boolean value")
            do $$$AssertEquals(tRS.%GetData(2) '= "", 1, "SQL sees the Boolean server timestamp")
            do $$$AssertEquals(tRS.%GetData(3), 0, "SQL sees the NodeId identifier type")
            do $$$AssertEquals(tRS.%GetData(4), 2, "SQL sees the matrix dimensions")
        } else {
            do $$$AssertEquals(0, 1, "SQL returns the row")
        }
    } Catch (e) {
        do $$$AssertFailure(e.DisplayString())
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

/// No secure session: skipped only if certified-server was not reached (nothing
/// was checked). Anything else (bad certificate, rejected credentials, the
/// library not loading) is a broken setup, and fails.
Method NotConnected(pURL As %String, pSC As %Status)
{
    if ##class(OPCUA.Tests.ServerReach).IsUnreachable(pSC) {
        do $$$AssertSkipped("certified-server unreachable ("_pURL_"): "_$System.Status.GetErrorText(pSC))
    } else {
        do $$$AssertFailure("could not connect to "_pURL_": "_$System.Status.GetErrorText(pSC))
    }
}

/// A connected client, or "" (and why in <var>pSC</var>) if the connection could
/// not be made. <tt>^||OPCUA.Tests("certDir")</tt> overrides the certificate
/// directory (test-only, to show a bad certificate fails rather than skips).
ClassMethod Connect(pURL As %String, pSecure As %Boolean, Output pSC As %Status) As OPCUA.Client [ Private ]
{
    set tClient = "", pSC = $$$OK
    Try {
        $$$ThrowOnError(##class(OPCUA.Utils).Initialize())
        set tClient = ##class(OPCUA.Client).%New()
        $$$ThrowOnError(tClient.Initialize())
        if pSecure {
            set tCerts = $Get(^||OPCUA.Tests("certDir"), "/usr/irissys/uac/certs/")
            $$$ThrowOnError(tClient.SetupClient(, $$$OpcuaMessageSecurityModeSignAndEncrypt, "urn:secuac", tCerts_"secuac.crt.der", tCerts_"secuac.key.der", tCerts_"trustdir", tCerts_"crldir"))
            $$$ThrowOnError(tClient.Connect(pURL, "user1", "password"))
        } else {
            $$$ThrowOnError(tClient.SetupClient())
            $$$ThrowOnError(tClient.Connect(pURL))
        }
    } Catch (e) {
        set tClient = "", pSC = e.AsStatus()
    }
    quit tClient
}

}
