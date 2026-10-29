Include (%occInclude, OPCUA.Constants)

/// Offline tests for the AI-pattern sweep (audit "AI-style patterns to watch"
/// and the remaining "Ignored statuses"): one method per fixed method, each
/// showing the wrong behaviour the old code had. Needs the native library
/// loaded (it is in the image), but no OPC UA server.
Class OPCUA.Tests.Unit.SweepTest Extends %UnitTest.TestCase
{

/// A throwaway device schema whose compiled spec the tests remove.
Parameter Schema = "OPCUA.Tests.Tmp.SweepSchema";

/// A throwaway persistent class with two generated serial folders.
Parameter SerialMain = "OPCUA.Tests.Tmp.SweepSerial";

/// Released by the test to let the lock-holding job finish.
Parameter ReleaseLock = "^IRIS.Temp.OPCUASweepRelease";

Method OnAfterAllTests() As %Status
{
	do ..DropSchema()
	do ..DropSerialClasses()
	kill ^IRIS.Temp.OPCUASweep
	Quit $$$OK
}

/// A row that cannot be opened again is an error, not an empty return.
Method TestCreateObjectFromSourceData()
{
	set tClass = "OPCUA.Tests.AttributesTestDS"
	set tGlobal = $ListGet(^OPCUA.DataSource(tClass), 2)
	set tBefore = +$Get(@tGlobal)
	set tData = "not a storage list"
	set tObj = "", tErr = ""
	Try {
		set tObj = ##class(OPCUA.Tests.AttributesTestDS).CreateObjectFromSourceData(.tData)
	} Catch (e) {
		set tErr = e.DisplayString()
	}
	do $$$AssertTrue(tErr '= "", "CreateObjectFromSourceData throws when the saved row cannot be opened (returned '"_tObj_"')")
	do $$$AssertTrue(tErr [ "<LIST>", "the error carries the open failure: "_tErr)

	// Drop the unreadable row the save wrote.
	for tId=tBefore+1:1:+$Get(@tGlobal) { kill @tGlobal@(tId) }
	set @tGlobal = tBefore
}

/// A failed read keeps its reason, in the status and in readError.
Method TestSafeReadValue()
{
	// Not an object: the call itself throws.
	set tSC = ##class(OPCUA.REST.ReadService).SafeReadValue("", "x", 1, $$$OpcuaNodeIdTypeString, .tResults, .tOK)
	do $$$AssertNotTrue($$$ISOK(tSC), "SafeReadValue returns the caught error, not $$$OK")
	do $$$AssertEquals(tOK, 0, "and reports the read as failed")

	// An initialized but unconnected client: the native read fails.
	set tClient = ##class(OPCUA.Client).%New()
	do $$$AssertStatusOK(tClient.Initialize(), "client initialize")
	set tExpected = ##class(OPCUA.REST.Error).Text(tClient.ReadValueAttribute(.tR, "x", 1, $$$OpcuaNodeIdTypeString))
	do $$$AssertTrue(tExpected '= "", "an unconnected read fails: "_tExpected)
	set tSC = ##class(OPCUA.REST.ReadService).SafeReadAndParse(tClient, 1, "x", $$$OpcuaNodeIdTypeString, "x", .tResult)
	do $$$AssertStatusOK(tSC, "SafeReadAndParse still answers")
	do $$$AssertTrue(tResult.readError [ tExpected, "readError names the reason: "_tResult.readError)
}

/// A native error list without a message still decodes to a real status.
Method TestDecodeError()
{
	set tSC = "", tErr = ""
	Try {
		set tSC = ##class(OPCUA.Client).DecodeError($ListBuild(1, $$$ErrorTypeOPCUA, 2158886912))
	} Catch (e) {
		set tErr = e.DisplayString()
	}
	do $$$AssertEquals(tErr, "", "DecodeError does not throw on a missing message")
	do $$$AssertNotTrue($$$ISOK(tSC), "it returns an error status")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "2158886912", "naming the code: "_$System.Status.GetErrorText(tSC))
}

/// An unreadable client state counts as disconnected, so the adapter reconnects.
Method TestConnectedState()
{
	set tClient = ##class(OPCUA.Client).%New()
	do $$$AssertStatusOK(tClient.Initialize(), "client initialize")
	// Initialized but never set up: the library refuses the state enquiry.
	do $$$AssertNotTrue($$$ISOK(tClient.GetClientState("", .tC)), "state enquiry fails on an unset client")
	set tState = ##class(OPCUA.Adapter.Common).ConnectedState(tClient, .tReset)
	do $$$AssertEquals(tState, 0, "ConnectedState is 0 (disconnected), not the -1 placeholder")
	do $$$AssertEquals(tReset, 0, "and no reset is reported")
}

/// A count that cannot be taken is unknown (""), not 0 rows.
Method TestGetRowCount()
{
	kill ^IRIS.Temp.OPCUARowCount("OPCUA.Utils")
	// OPCUA.Utils exists but has no table, so the COUNT(*) fails (SQLCODE -30).
	set tCount = ##class(OPCUA.REST.PipelineService).GetRowCount("OPCUA.Utils")
	do $$$AssertEquals(tCount, "", "GetRowCount is empty for a failed count, got '"_tCount_"'")
	do $$$AssertEquals($Data(^IRIS.Temp.OPCUARowCount("OPCUA.Utils")), 0, "a failed count is not cached")

	// A pipeline whose schema class is gone: unknown too, not 0 rows.
	set tCount = ##class(OPCUA.REST.PipelineService).GetRowCount("OPCUA.Tests.Tmp.NoSuchSchema")
	do $$$AssertEquals(tCount, "", "GetRowCount is empty for a missing class, got '"_tCount_"'")
}

/// A failed dynamic query throws instead of reading as an empty result.
Method TestExecQuery()
{
	set tErr = ""
	Try {
		set tRS = ##class(OPCUA.Utils).ExecQuery("SELECT ID FROM OPCUA_Tests_Tmp.NoSuchTable WHERE ID = ?", 1)
	} Catch (e) {
		set tErr = $System.Status.GetErrorText(e.AsStatus())
	}
	do $$$AssertTrue(tErr [ "-30", "ExecQuery throws the SQL error: "_tErr)

	set tRS = ##class(OPCUA.Utils).ExecQuery("SELECT 1 AS One")
	do $$$AssertTrue(tRS.%Next() && (tRS.One = 1), "a good query still returns rows")
}

/// A schema whose columns cannot be read says so, instead of having 0 columns.
Method TestDescribeSchema()
{
	set tSC = ..CreateSchema()
	do $$$AssertStatusOK(tSC, "create test schema")
	Quit:$$$ISERR(tSC)
	kill ^OPCUA.DataSource(..#Schema)

	set tSC = ##class(OPCUA.REST.SchemaService).Get({"name": (..#Schema)}, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Get fails for a schema without a compiled spec")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "No compiled OPC UA spec", "and gives the reason: "_$System.Status.GetErrorText(tSC))

	set tSC = ##class(OPCUA.REST.SchemaService).List({}, .tList)
	do $$$AssertStatusOK(tSC, "List still answers")
	set tItem = ""
	for i=0:1:tList.%Size()-1 {
		if tList.%Get(i).schemaClass = ..#Schema set tItem = tList.%Get(i)
	}
	do $$$AssertTrue($IsObject(tItem), "List includes the schema")
	Quit:'$IsObject(tItem)
	do $$$AssertTrue(tItem.columnsError [ "No compiled OPC UA spec", "List reports columnsError: '"_tItem.columnsError_"'")
}

/// A failed serial delete is reported, even when a later one succeeds.
Method TestDeleteSerialSubclasses()
{
	set tSC = ..CreateSerialClasses()
	do $$$AssertStatusOK(tSC, "create test classes")
	Quit:$$$ISERR(tSC)

	// The first serial folder in property order is the one to fail.
	set tDef = ##class(%Dictionary.CompiledClass).%OpenId(..#SerialMain)
	set tLocked = ""
	for i=1:1:tDef.Properties.Count() {
		set tType = tDef.Properties.GetAt(i).Type
		if $Extract(tType, 1, $Length(..#SerialMain) + 1) = (..#SerialMain_".") set tLocked = tType quit
	}
	do $$$AssertTrue(tLocked '= "", "found the first serial folder: "_tLocked)
	Quit:tLocked=""

	// Another process holding the class lock makes $System.OBJ.Delete fail (#5864).
	set tRelease = ..#ReleaseLock
	lock +@tRelease
	kill ^IRIS.Temp.OPCUASweep(tLocked)
	job ..HoldClassLock(tLocked)
	set tJob = $ZChild
	for n=1:1:100 { quit:$Get(^IRIS.Temp.OPCUASweep(tLocked))  hang 0.1 }
	do $$$AssertTrue($Get(^IRIS.Temp.OPCUASweep(tLocked)), "helper job holds the lock on "_tLocked)

	set tSC = ##class(OPCUA.REST.PipelineService).DeleteSerialSubclasses(..#SerialMain)

	lock -@tRelease
	for n=1:1:100 { quit:'$Data(^$JOB(tJob))  hang 0.1 }

	do $$$AssertNotTrue($$$ISOK(tSC), "DeleteSerialSubclasses reports the failed delete")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ tLocked, "naming the class: "_$System.Status.GetErrorText(tSC))
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(tLocked), "the locked class is still there")
}

/// Job entry point: hold <var>pClass</var>'s definition lock until the test
/// releases <parameter>ReleaseLock</parameter>.
ClassMethod HoldClassLock(pClass As %String)
{
	lock +^oddDEF(pClass)
	set ^IRIS.Temp.OPCUASweep(pClass) = 1
	set tRelease = ..#ReleaseLock
	lock +@tRelease:30
	lock
	kill ^IRIS.Temp.OPCUASweep(pClass)
}

ClassMethod CreateSchema() As %Status
{
	do ..DropSchema()
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Schema)
	set tDef.Super = "OPCUA.DataSource.DeviceSchema,%Persistent"
	set tDef.Description = "Throwaway schema for SweepTest"
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE"
	set tParam.Default = "SweepDevice"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE"
	set tParam.Default = "1"
	do tDef.Parameters.Insert(tParam)
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "Temperature"
	set tProp.Type = "OPCUA.Types.DoubleDataValue"
	do tProp.Parameters.SetAt("Temperature", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#Schema, "ck-d")
}

ClassMethod DropSchema()
{
	set tSchema = ..#Schema
	if ##class(%Dictionary.ClassDefinition).%ExistsId(tSchema) {
		do $classmethod(tSchema, "%KillExtent")
		do $System.OBJ.Delete(tSchema, "-d")
	}
	kill ^OPCUA.DataSource(tSchema)
}

/// A persistent class with two serial folders named the way
/// SchemaService.SerialClassName names them (Main.&lt;Folder&gt;Type).
ClassMethod CreateSerialClasses() As %Status
{
	do ..DropSerialClasses()
	set tMain = ##class(%Dictionary.ClassDefinition).%New(..#SerialMain)
	set tMain.Super = "%Persistent"
	for tFolder = "Alpha", "Omega" {
		set tSerial = ##class(%Dictionary.ClassDefinition).%New(..#SerialMain_"."_tFolder_"Type")
		set tSerial.Super = "%SerialObject"
		set tP = ##class(%Dictionary.PropertyDefinition).%New()
		set tP.Name = "Reading"
		set tP.Type = "%String"
		do tSerial.Properties.Insert(tP)
		set tSC = tSerial.%Save()
		Return:$$$ISERR(tSC) tSC

		set tP = ##class(%Dictionary.PropertyDefinition).%New()
		set tP.Name = tFolder
		set tP.Type = ..#SerialMain_"."_tFolder_"Type"
		do tMain.Properties.Insert(tP)
	}
	set tSC = tMain.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#SerialMain_".AlphaType,"_..#SerialMain_".OmegaType,"_..#SerialMain, "ck-d")
}

ClassMethod DropSerialClasses()
{
	for tName = ..#SerialMain_".AlphaType", ..#SerialMain_".OmegaType", ..#SerialMain {
		do:##class(%Dictionary.ClassDefinition).%ExistsId(tName) $System.OBJ.Delete(tName, "-d")
	}
}

}
