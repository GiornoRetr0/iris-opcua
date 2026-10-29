Include (OPCUA.Constants, %occInclude, Ensemble)

/// Live tests for concurrent pipeline edits and honest restart reporting
/// (audit #10). Works on a throwaway pipeline in OPCUA.Pipeline.Production.
Class OPCUA.Tests.Live.PipelineConcurrencyTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpConcurrencySchema";

Parameter PipelineName = "TmpConcurrency";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

Parameter ListA = "i=85|ObjectsA";

Parameter ListB = "i=85|ObjectsB";

/// Whether our production was running before the tests, so it can be put back.
Property WasRunning As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
	do ..DoCleanup()
	do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	set ..WasRunning = (tName = ..#ProductionClass) && (tState = 1)
	set tSC = ..BuildSchema()
	Quit:$$$ISERR(tSC) tSC
	set tBody = {
		"dataSourceName": (..#PipelineName),
		"schemaClass": (..#SchemaClass),
		"mode": "polling",
		"url": (..URL()),
		"deviceNodePaths": (..#ListA),
		"callInterval": 2
	}
	Quit ##class(OPCUA.REST.DeployService).Deploy(tBody, .tResult)
}

Method OnAfterAllTests() As %Status
{
	kill ^||OPCUA.Tests("productionStatus"), ^IRIS.Temp.OPCUATests("conc")
	do ..DoCleanup()
	if ..WasRunning {
		do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
		do:tState'=1 ##class(Ens.Director).StartProduction(..#ProductionClass)
	}
	Quit $$$OK
}

/// Two rebinds of the same pipeline at once. Each either succeeds or is refused
/// as "in progress", and storage and the class end up holding the same one of
/// the two lists. Before the lock, the second save could rewrite the class from
/// a stale copy.
Method TestParallelRebinds()
{
	for tRound=1:1:3 {
		kill ^IRIS.Temp.OPCUATests("conc")
		job ##class(OPCUA.Tests.Live.PipelineConcurrencyTest).RebindJob(..#PipelineName, ..#ListA, ..URL(), "A")::5
		job ##class(OPCUA.Tests.Live.PipelineConcurrencyTest).RebindJob(..#PipelineName, ..#ListB, ..URL(), "B")::5
		for i=1:1:600 { quit:$Data(^IRIS.Temp.OPCUATests("conc","A"))&&$Data(^IRIS.Temp.OPCUATests("conc","B"))  hang 0.1 }

		set tOK = 0
		for tSlot = "A", "B" {
			set tRes = $Get(^IRIS.Temp.OPCUATests("conc", tSlot))
			do $$$AssertTrue(tRes '= "", "round "_tRound_": rebind "_tSlot_" finished")
			continue:tRes=""
			if $ListGet(tRes, 1) {
				set tOK = tOK + 1
			} else {
				do $$$AssertTrue($ListGet(tRes, 2) [ "in progress", "round "_tRound_": rebind "_tSlot_" either succeeds or says in progress: "_$ListGet(tRes, 2))
			}
		}
		do $$$AssertTrue(tOK >= 1, "round "_tRound_": at least one rebind succeeded")

		set tStored = ..StoredDevices()
		set tInClass = ..ClassDevices()
		do $$$AssertTrue((tStored = ..#ListA) || (tStored = ..#ListB), "round "_tRound_": stored list is exactly one of the two: "_tStored)
		do $$$AssertEquals(tInClass, tStored, "round "_tRound_": production class and storage agree")
	}
}

/// A rebind while the production is stopped saves the list and does not claim a
/// restart. A troubled production makes the call fail with "Device list saved,
/// but ..." and the list is still saved.
Method TestRebindWhenProductionNotRunning()
{
	do ##class(Ens.Director).GetProductionStatus(.tName, .tState)
	if (tName '= "") && (tName '= ..#ProductionClass) {
		do $$$LogMessage("Skipped: production '"_tName_"' holds the namespace")
		Quit
	}
	if tState = 1 {
		set tSC = ##class(Ens.Director).StopProduction(10, 1)
		do $$$AssertStatusOK(tSC, "stop our production")
	}

	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#PipelineName), "devices": (..#ListB)}, .tResult)
	do $$$AssertStatusOK(tSC, "rebind with the production stopped")
	do $$$AssertNotEquals(tResult.restarted, 1, "no restart claimed")
	do $$$AssertTrue(tResult.restartNote '= "", "the response says why there was no restart: "_tResult.restartNote)
	do $$$AssertEquals(..StoredDevices(), ..#ListB, "device list saved")

	// Troubled cannot be forced without faking Ensemble's runtime globals, so the
	// status seam stands in for it.
	set ^||OPCUA.Tests("productionStatus") = $ListBuild(..#ProductionClass, 4)
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#PipelineName), "devices": (..#ListA)}, .tResult2)
	kill ^||OPCUA.Tests("productionStatus")
	do $$$AssertNotTrue($$$ISOK(tSC), "rebind with a troubled production reports an error")
	set tText = $System.Status.GetOneStatusText(tSC)
	do $$$AssertTrue($Extract(tText, 1, $Length("Device list saved, but")) = "Device list saved, but", "error text: "_tText)
	do $$$AssertNotEquals(tResult2.restarted, 1, "no restart claimed")
	do $$$AssertEquals(..StoredDevices(), ..#ListA, "device list saved despite the failed restart")
}

/// JOB entry: run one rebind and record $LB(ok, error text).
ClassMethod RebindJob(pName As %String, pDevices As %String, pURL As %String, pSlot As %String)
{
	set tText = ""
	try {
		set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (pName), "devices": (pDevices)}, .tResult)
		set:$$$ISERR(tSC) tText = $System.Status.GetErrorText(tSC)
	} catch e {
		set tSC = e.AsStatus(), tText = e.DisplayString()
	}
	set ^IRIS.Temp.OPCUATests("conc", pSlot) = $ListBuild($$$ISOK(tSC), tText)
}

ClassMethod URL() As %String
{
	Quit $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

/// DeviceNodePaths as stored in Ens.Config, reread from disk.
ClassMethod StoredDevices() As %String
{
	set tName = ..#PipelineName, tProd = ..#ProductionClass, tValue = ""
	&sql(SELECT ID INTO :tId FROM Ens_Config.Item WHERE Production = :tProd AND Name = :tName)
	Quit:SQLCODE'=0 ""
	set tItem = ##class(Ens.Config.Item).%OpenId(tId, 0)
	Quit:'$IsObject(tItem) ""
	do tItem.%Reload()
	for i=1:1:tItem.Settings.Count() {
		set:tItem.Settings.GetAt(i).Name="DeviceNodePaths" tValue = tItem.Settings.GetAt(i).Value
	}
	Quit tValue
}

/// DeviceNodePaths as written into the production class's XData.
ClassMethod ClassDevices() As %String
{
	set tSC = ##class(Ens.Util.XML.Reader).ObjectFromXData(.tProd, ..#ProductionClass, "ProductionDefinition", "Ens.Config.Production")
	Quit:$$$ISERR(tSC) ""
	set tValue = ""
	for i=1:1:tProd.Items.Count() {
		set tItem = tProd.Items.GetAt(i)
		continue:tItem.Name'=..#PipelineName
		for j=1:1:tItem.Settings.Count() {
			set:tItem.Settings.GetAt(j).Name="DeviceNodePaths" tValue = tItem.Settings.GetAt(j).Value
		}
	}
	Quit tValue
}

ClassMethod DoCleanup()
{
	try {
		do ##class(OPCUA.REST.PipelineService).Delete({"name": (..#PipelineName)}, .tResult)
	} catch e {}
	set tName = ..#PipelineName
	&sql(DELETE FROM Ens_Config.Item WHERE Name = :tName)
	try {
		do:##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass) $classmethod(..#SchemaClass, "%KillExtent")
	} catch e {}
	do:##class(%Dictionary.ClassDefinition).%ExistsId(..#SchemaClass) $System.OBJ.Delete(..#SchemaClass, "-d")
	kill ^OPCUA.DataSource(..#SchemaClass)
}

/// A one-column schema that the plc's Objects folder resolves (SA1).
ClassMethod BuildSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#SchemaClass)
	set tDef.Description = "Throwaway schema for PipelineConcurrencyTest"
	set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE", tParam.Default = "TmpConcurrency"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE", tParam.Default = 1
	do tDef.Parameters.Insert(tParam)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "NodePath", tProp.Type = "%String"
	do tProp.Parameters.SetAt(500, "MAXLEN")
	do tDef.Properties.Insert(tProp)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "SA1", tProp.Type = "OPCUA.Types.IntegerDataValue"
	do tProp.Parameters.SetAt("SA1", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#SchemaClass, "ck-d")
}

}
