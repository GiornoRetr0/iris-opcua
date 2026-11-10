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

/// Smoke check: two rebinds of the same pipeline at once. Each either succeeds
/// or is refused as "in progress", and storage and the class end up holding the
/// same one of the two lists. Timing-dependent, so it also passed on the old
/// code; <method>TestRebindWhileLocked</method> is the deterministic check.
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

	// Suspended, the same way.
	set ^||OPCUA.Tests("productionStatus") = $ListBuild(..#ProductionClass, 3)
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#PipelineName), "devices": (..#ListB)}, .tResult3)
	kill ^||OPCUA.Tests("productionStatus")
	do $$$AssertNotTrue($$$ISOK(tSC), "rebind with a suspended production reports an error")
	set tText = $System.Status.GetOneStatusText(tSC)
	do $$$AssertEquals(tText, "Device list saved, but the running pipeline could not be restarted: production '"_..#ProductionClass_"' is suspended", "error text")
	do $$$AssertNotEquals(tResult3.restarted, 1, "no restart claimed")
	do $$$AssertEquals(..StoredDevices(), ..#ListB, "device list saved despite the suspended production")
}

/// Toggle with a troubled, then a suspended production: the new state is saved,
/// and the call says the production could not be updated.
Method TestToggleWhenProductionNotRunning()
{
	set tProdName = ..#ProductionClass
	set tWas = ..ItemEnabled()

	set ^||OPCUA.Tests("productionStatus") = $ListBuild(tProdName, 4)
	set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#PipelineName)}, .tResult)
	kill ^||OPCUA.Tests("productionStatus")
	set tState = $Select(tWas:"disabled", 1:"enabled")
	do $$$AssertEquals($System.Status.GetOneStatusText(tSC), "Pipeline "_tState_" and saved, but the production could not be updated: production '"_tProdName_"' is troubled", "troubled toggle error text")
	do $$$AssertEquals(..ItemEnabled(), 'tWas, "the new state was saved")
	do $$$AssertNotEquals(tResult.restarted, 1, "no restart claimed")

	set ^||OPCUA.Tests("productionStatus") = $ListBuild(tProdName, 3)
	set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#PipelineName)}, .tResult)
	kill ^||OPCUA.Tests("productionStatus")
	set tState = $Select(tWas:"enabled", 1:"disabled")
	do $$$AssertEquals($System.Status.GetOneStatusText(tSC), "Pipeline "_tState_" and saved, but the production could not be updated: production '"_tProdName_"' is suspended", "suspended toggle error text")
	do $$$AssertEquals(..ItemEnabled(), tWas, "toggled back and saved")
}

/// Delete with a troubled or suspended production: the pipeline is gone, and the
/// call says the production could not be updated.
Method TestDeleteWhenProductionNotRunning()
{
	for tState = 4, 3 {
		set tName = ..#PipelineName_"Del"_tState
		set tSC = ##class(OPCUA.REST.DeployService).Deploy({
			"dataSourceName": (tName),
			"schemaClass": (..#SchemaClass),
			"url": (..URL()),
			"deviceNodePaths": (..#ListA)
		}, .tDeployed)
		do $$$AssertStatusOK(tSC, "deploy "_tName)
		continue:$$$ISERR(tSC)

		set ^||OPCUA.Tests("productionStatus") = $ListBuild(..#ProductionClass, tState)
		set tSC = ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
		kill ^||OPCUA.Tests("productionStatus")
		set tText = $Select(tState=4:"troubled", 1:"suspended")
		do $$$AssertEquals($System.Status.GetOneStatusText(tSC), "Pipeline deleted, but the running production could not be updated: production '"_..#ProductionClass_"' is "_tText, tText_" delete error text")
		do $$$AssertEquals(..ItemRows(tName), 0, tText_": the pipeline is gone")
		do $$$AssertEquals(tResult.deleted, 1, tText_": the response says deleted")
	}
}

/// A rebind while another edit holds the lock is refused as "in progress". This
/// pins the Rebind, UpdateItem, Begin wiring without depending on timing.
Method TestRebindWhileLocked()
{
	kill ^IRIS.Temp.OPCUATests("conc")
	set ^IRIS.Temp.OPCUATests("conc", "hold") = 1
	job ##class(OPCUA.Tests.Live.PipelineConcurrencyTest).HoldLock()::5
	do $$$AssertTrue($Test, "lock-holding job started")
	for i=1:1:50 { quit:$Get(^IRIS.Temp.OPCUATests("conc", "held"))  hang 0.1 }
	do $$$AssertTrue($Get(^IRIS.Temp.OPCUATests("conc", "held")), "job holds the edit lock")

	set tBefore = ..StoredDevices()
	set tNew = $Select(tBefore=..#ListA:..#ListB, 1:..#ListA)
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#PipelineName), "devices": (tNew)}, .tResult)
	kill ^IRIS.Temp.OPCUATests("conc", "hold")
	do $$$AssertNotTrue($$$ISOK(tSC), "rebind is refused while the lock is held")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "in progress", "error says in progress: "_$System.Status.GetErrorText(tSC))
	do $$$AssertEquals(..StoredDevices(), tBefore, "the device list did not change")
}

/// JOB entry: hold the edit lock until the test kills the flag.
ClassMethod HoldLock()
{
	lock +^OPCUA.ProductionEdit
	set ^IRIS.Temp.OPCUATests("conc", "held") = 1
	for i=1:1:600 { quit:'$Get(^IRIS.Temp.OPCUATests("conc", "hold"))  hang 0.1 }
	lock -^OPCUA.ProductionEdit
}

ClassMethod ItemEnabled() As %Boolean
{
	set tName = ..#PipelineName, tProd = ..#ProductionClass
	&sql(SELECT Enabled INTO :tEnabled FROM Ens_Config.Item WHERE Production = :tProd AND Name = :tName)
	Quit $Select(SQLCODE=0:+tEnabled, 1:"")
}

ClassMethod ItemRows(pName As %String) As %Integer
{
	set tProd = ..#ProductionClass
	&sql(SELECT COUNT(*) INTO :tCount FROM Ens_Config.Item WHERE Production = :tProd AND Name = :pName)
	Quit $Select(SQLCODE=0:tCount, 1:-1)
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
	kill ^||OPCUA.Tests("productionStatus"), ^IRIS.Temp.OPCUATests("conc")
	for tName = ..#PipelineName, ..#PipelineName_"Del4", ..#PipelineName_"Del3" {
		try {
			do ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
		} catch e {}
		&sql(DELETE FROM Ens_Config.Item WHERE Name = :tName)
	}
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
