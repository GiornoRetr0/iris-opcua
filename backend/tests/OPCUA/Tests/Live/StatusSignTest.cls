Include (%occInclude, OPCUA.Constants)

/// Live: a Bad StatusCode delivered by the native layer is stored unsigned.
///
/// Polls plc with one existing node and one nonexistent NodeId through the
/// spec-based bulk read the row-source services use, hands the result to
/// RowWriter and SaveSourcedData, and reads the row back by SQL. Closes audit #14.
Class OPCUA.Tests.Live.StatusSignTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.LiveStatusSign";

Parameter TmpTable = "OPCUA_Tests_Tmp.LiveStatusSign";

Parameter PLCURL = "opc.tcp://plc:4840";

/// A string NodeId in plc's namespace that no device has.
Parameter MissingNodeId = "NoSuchNode_StatusSign";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	Quit $$$OK
}

Method TestStoredUnsigned()
{
	#dim tClient As OPCUA.Client
	set tHandle = ""
	do ..DropSchema(..#TmpSchema)
	Try {
		set tSC = ..BuildTestSchema(..#TmpSchema)
		do $$$AssertStatusOK(tSC, "Build test schema")
		Quit:$$$ISERR(tSC)

		set tClient = ##class(OPCUA.Client).%New()
		set tSC = tClient.Initialize()
		do $$$AssertStatusOK(tSC, "Client initialize")
		Quit:$$$ISERR(tSC)
		do tClient.SetupClient("", 1, "", "", "", "", "")
		set tSC = tClient.Connect(..#PLCURL, "", "")
		do $$$AssertStatusOK(tSC, "Connect to plc")
		Quit:$$$ISERR(tSC)

		// Build the read spec in the Resolver's format, by hand: the Resolver
		// would drop the unresolved column instead of polling it.
		set tSC = ..BuildReadSpec(..#TmpSchema, .tSpec)
		do $$$AssertStatusOK(tSC, "Build read spec")
		Quit:$$$ISERR(tSC)

		set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
		do $$$AssertStatusOK(tSC, "ReadBulkSetupC accepts the spec")
		Quit:$$$ISERR(tSC)
		set tSC = tClient.ReadBulkPollC(.tList, tHandle)
		do $$$AssertStatusOK(tSC, "ReadBulkPollC")
		Quit:$$$ISERR(tSC)

		// One slot per node: the missing node comes back in place as Bad.
		do $$$AssertEquals($ListLength(tList), 3, "poll returns a slot for both nodes")
		set tBadDV = $ListGet(tList, 3)
		set tNative = $ListGet(tBadDV, 3)
		do $$$AssertTrue(tNative >= 2147483648, "native Bad code is unsigned: "_tNative)
		do $$$AssertEquals($ListGet(tBadDV, 4), "", "native Bad reading has no value")

		set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
		set tSC = tWriter.Initialize(..#TmpSchema)
		do $$$AssertStatusOK(tSC, "RowWriter initialize")
		Quit:$$$ISERR(tSC)

		set tMask = $LB(1, 1)
		do $$$AssertStatusOK(tWriter.CheckInput(.tList, $LB(tMask)), "CheckInput accepts the poll result")
		set tResultIdx = 1
		set tSC = tWriter.BuildRow(.tList, tMask, "StatusSignDev", .tResultIdx, .tRow, .tChanges)
		do $$$AssertStatusOK(tSC, "BuildRow")
		Quit:$$$ISERR(tSC)

		// Change entries are $LB(columnIndex, oldSeverity, newSeverity, status).
		set tSev2 = "", tChangeStatus = ""
		for i=1:1:$ListLength(tChanges) {
			set tChange = $ListGet(tChanges, i)
			if $ListGet(tChange, 1) = 2 {
				set tSev2 = $ListGet(tChange, 3)
				set tChangeStatus = $ListGet(tChange, 4)
			}
		}
		do $$$AssertEquals(tSev2, 2, "RowWriter severity for column 2 is Bad")
		do $$$AssertEquals(tChangeStatus, tNative, "RowWriter reports the native code")

		set tSC = $classmethod(..#TmpSchema, "SaveSourcedData", .tRow, .tId)
		do $$$AssertStatusOK(tSC, "SaveSourcedData")
		Quit:$$$ISERR(tSC)

		set tRS = ##class(%SQL.Statement).%ExecDirect(,
			"SELECT SA1_Status, Unresolved_Status, Unresolved_Value FROM "_..#TmpTable_" WHERE ID = ?", tId)
		do $$$AssertEquals(tRS.%SQLCODE, 0, "SELECT the stored row")
		do $$$AssertTrue(tRS.%Next(), "stored row found")
		set tStatus1 = tRS.%GetData(1), tStatus2 = tRS.%GetData(2), tValue2 = tRS.%GetData(3)
		do $$$AssertEquals(tStatus1, 0, "column 1 _Status is 0 (got "_tStatus1_")")
		do $$$AssertEquals(tStatus2, tNative, "column 2 _Status equals the native code "_tNative_" (got "_tStatus2_")")
		do $$$AssertTrue(tStatus2 >= 2147483648, "column 2 _Status is >= 2147483648")
		do $$$AssertEquals(tValue2, "", "column 2 _Value is NULL (got "_tValue2_")")
		// ObjectScript reads the code back whatever the type; an xDBC client reads
		// it by the column's declared type, and INTEGER (4) overflows above 2^31-1.
		set tODBCType = tRS.%GetMetadata().columns.GetAt(2).ODBCType
		do $$$AssertEquals(tODBCType, -5, "column 2 _Status is BIGINT (-5) to xDBC clients (got "_tODBCType_")")
	} Catch (e) {
		do $$$AssertTrue(0, "Exception: "_e.DisplayString())
	}
	if $IsObject($Get(tClient)) {
		do:tHandle'="" tClient.ReadBulkClear(tHandle)
		do tClient.Disconnect()
	}
}

/// Schema with SA1 (exists on plc's Objects folder) and Unresolved (does not).
ClassMethod BuildTestSchema(pClassName As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tCols = []
		for tName = "SA1", "Unresolved" {
			set tCol = {"displayName":(tName), "inferredType":"OPCUA.Types.IntegerDataValue"}
			set tCol.relativePath = [(tName)]
			do tCols.%Push(tCol)
		}
		set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, "TmpLiveStatusSign", tCols, 1, .tColNS, .tSerial, 1)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// The spec ResolveSpecification would produce for one device rooted at
/// Objects (i=85), except that column 2 keeps a NodeId plc doesn't have.
ClassMethod BuildReadSpec(pClassName As %String, Output pSpec As %List) As %Status [ Private ]
{
	set pSpec = ""
	set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(pClassName, .tColumns, .tFolders)
	Quit:$$$ISERR(tSC) tSC
	Quit:tColumns'=2 $$$ERROR($$$GeneralError, "expected 2 columns, got "_tColumns)
	set tBase = ^OPCUA.DataSource(pClassName)
	set tEntries = $LB("")
	// Columns come in projection order; the assertions need SA1 first.
	Quit:$ListGet(tColumns(1),3)'="SA1" $$$ERROR($$$GeneralError, "column 1 is "_$ListGet(tColumns(1), 3)_", expected SA1")
	Quit:$ListGet(tColumns(2),3)'="Unresolved" $$$ERROR($$$GeneralError, "column 2 is "_$ListGet(tColumns(2), 3)_", expected Unresolved")
	for iCol=1:1:2 {
		set tCol = tColumns(iCol)
		set tNodeId = $Select(iCol=1:"SA1", 1:..#MissingNodeId)
		set tEntries = tEntries _ $LB($LB(2, $ListGet(tCol, 1)_"_RS1", 1, tNodeId, $ListGet(tCol, 4)))
	}
	set pSpec = $LB($ListGet(tBase, 1), $ListGet(tBase, 2), tEntries)
	Quit $$$OK
}

ClassMethod DropSchema(pClassName As %String) [ Private ]
{
	Try { do $classmethod(pClassName, "%KillExtent") } Catch (e) {}
	Try { do $System.OBJ.Delete(pClassName, "-d") } Catch (e) {}
	kill ^OPCUA.DataSource(pClassName)
}

}
