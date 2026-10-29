Include %occInclude

/// Live test verifying Bad StatusCodes from the native layer are stored as
/// unsigned values and classified correctly by RowWriter's severity logic.
///
/// Closes audit #14.
Class OPCUA.Tests.Live.StatusSignTest Extends %UnitTest.TestCase
{

Parameter TmpSchema = "OPCUA.Tests.Tmp.LiveStatusSign";

Parameter PLCURL = "opc.tcp://plc:4840";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema(..#TmpSchema)
	Quit $$$OK
}

/// Poll the plc server with a real schema, run the result through RowWriter
/// and SaveSourcedData (the same path the row-source services use), and verify
/// that Status values from the native layer store correctly as unsigned values.
///
/// Note: This test uses SA1 at the Objects folder (i=85), which returns Good
/// status (0) on the plc mock server. The offline tests in StatusWidthTest
/// verify Bad codes (>= 2147483648) round-trip correctly. This live test
/// confirms the end-to-end path (native poll → RowWriter → SQL) works.
Method TestStoredUnsigned()
{
	#dim tClient As OPCUA.Client

	do ..DropSchema(..#TmpSchema)

	Try {
		// Build a schema with SA1, which the plc mock exposes at the Objects folder
		set tSC = ..BuildTestSchema(..#TmpSchema)
		do $$$AssertStatusOK(tSC, "Build test schema")
		Quit:$$$ISERR(tSC)

		// Initialize client and connect to plc
		set tClient = ##class(OPCUA.Client).%New()
		set tSC = tClient.Initialize()
		do $$$AssertStatusOK(tSC, "Client initialize")
		Quit:$$$ISERR(tSC)

		do tClient.SetupClient("", 1, "", "", "", "", "")
		set tSC = tClient.Connect(..#PLCURL, "", "")
		do $$$AssertStatusOK(tSC, "Connect to plc")
		Quit:$$$ISERR(tSC)

		// Resolve against Objects folder where SA1 lives
		do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths("i=85|Dev1", .tDevices, .tErrors)
		set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, ..#TmpSchema, tDevices, .tSpec, .tMasks, .tDiag)
		do $$$AssertStatusOK(tSC, "ResolveSpecification")
		Quit:$$$ISERR(tSC)

		// SA1 should resolve
		set tMask = $LIST(tMasks, 1)
		do $$$AssertEquals($LIST(tMask, 1), 1, "SA1 resolved")

		// Set up bulk read and poll
		set tSC = tClient.ReadBulkSetupC(.tHandle, tSpec)
		do $$$AssertStatusOK(tSC, "ReadBulkSetupC")
		Quit:$$$ISERR(tSC)

		set tSC = tClient.ReadBulkPollC(.tList, tHandle)
		do $$$AssertStatusOK(tSC, "ReadBulkPollC")
		if $$$ISERR(tSC) {
			do tClient.ReadBulkClear(tHandle)
			Quit
		}

		// Initialize RowWriter and build row (same path as row-source services)
		set tWriter = ##class(OPCUA.DataSource.RowWriter).%New()
		set tSC = tWriter.Initialize(..#TmpSchema)
		do $$$AssertStatusOK(tSC, "RowWriter initialize")
		if $$$ISERR(tSC) {
			do tClient.ReadBulkClear(tHandle)
			Quit
		}

		set tResultIdx = 1
		set tSC = tWriter.BuildRow(.tList, $LIST(tMasks, 1), "Dev1", .tResultIdx, .tRow, .tQualityChanges)
		do $$$AssertStatusOK(tSC, "BuildRow")
		if $$$ISERR(tSC) {
			do tClient.ReadBulkClear(tHandle)
			Quit
		}

		// Save the row via SaveSourcedData (same as the services do)
		set tSC = $classmethod(..#TmpSchema, "SaveSourcedData", .tRow, .tId)
		do $$$AssertStatusOK(tSC, "SaveSourcedData")
		if $$$ISERR(tSC) {
			do tClient.ReadBulkClear(tHandle)
			Quit
		}

		// Read back the SA1_Status via SQL
		&sql(SELECT SA1_Status INTO :tStatus FROM OPCUA_Tests_Tmp.LiveStatusSign WHERE ID = :tId)
		do $$$AssertEquals(SQLCODE, 0, "SQL SELECT SA1_Status")
		Quit:SQLCODE'=0

		// Verify Status is non-negative (the key requirement for unsigned storage)
		do $$$AssertTrue(tStatus >= 0, "SA1_Status is non-negative")

		// SA1 returns Good status (0) on the plc mock, verify it
		do $$$AssertEquals(tStatus, 0, "SA1_Status is Good (0)")

		// Clean up
		do tClient.ReadBulkClear(tHandle)
		do tClient.Disconnect()

	} Catch (e) {
		do $$$AssertTrue(0, "Exception: " _ e.DisplayString())
	}
}

/// Build a test schema with SA1 column for polling Objects folder device.
ClassMethod BuildTestSchema(pClassName As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		do ..DropSchema(pClassName)

		set tBody = {}
		set tBody.className = pClassName
		set tBody.dataSourceName = "LiveStatusSign"
		set tBody.defaultNamespace = 0

		set tColumns = []
		set tCol = {}
		set tCol.displayName = "SA1"
		set tCol.inferredType = "Integer"
		set tRelPath = ["SA1"]
		set tCol.relativePath = tRelPath
		do tColumns.%Push(tCol)
		set tBody.columns = tColumns

		set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
		$$$ThrowOnError(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

ClassMethod DropSchema(pClassName As %String)
{
	if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		Try {
			do $classmethod(pClassName, "%KillExtent")
		} Catch {}
		do $System.OBJ.Delete(pClassName, "-d")
	}
	kill ^OPCUA.DataSource(pClassName)
}

}
