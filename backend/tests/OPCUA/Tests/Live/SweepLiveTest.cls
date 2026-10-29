Include (OPCUA.Constants, %occInclude, Ensemble)

/// Live: one bad pipeline must not take the whole GET /pipelines down.
///
/// Deploys two throwaway pipelines against plc. One gets a DeviceNodePaths of
/// only a comment (how a pipeline is paused from the Portal); the other is
/// healthy. Then one item's description is forced to fail.
Class OPCUA.Tests.Live.SweepLiveTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpSweepLiveSchema";

Parameter Paused = "TmpSweepPaused";

Parameter Healthy = "TmpSweepHealthy";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

Method OnBeforeAllTests() As %Status
{
	do ..DoCleanup()
	set tSC = ..BuildSchema()
	Quit:$$$ISERR(tSC) tSC
	set tURL = $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
	for tName = ..#Paused, ..#Healthy {
		set tSC = ##class(OPCUA.REST.DeployService).Deploy({
			"dataSourceName": (tName), "schemaClass": (..#SchemaClass), "mode": "polling",
			"url": (tURL), "deviceNodePaths": "i=85|Objects", "callInterval": 2
		}, .tResult)
		Return:$$$ISERR(tSC) tSC
	}
	// Pause one from the "Portal": its only device line becomes a comment.
	Quit ..SetDevicePaths(..#Paused, "# i=85|Objects paused")
}

Method OnAfterAllTests() As %Status
{
	kill ^||OPCUA.Tests("failPipelineItem")
	do ..DoCleanup()
	Quit $$$OK
}

/// A pipeline whose device list is only comments lists with no devices.
Method TestListWithPausedPipeline()
{
	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	do $$$AssertStatusOK(tSC, "List answers with a comment-only pipeline present")
	Quit:$$$ISERR(tSC)
	set tPaused = ..Find(tList, ..#Paused), tHealthy = ..Find(tList, ..#Healthy)
	do $$$AssertTrue($IsObject(tPaused), "paused pipeline is listed")
	do $$$AssertTrue($IsObject(tHealthy), "healthy pipeline is listed")
	Quit:'$IsObject(tPaused)||'$IsObject(tHealthy)
	do $$$AssertEquals(tPaused.rowSources.%Size(), 0, "paused pipeline has no devices")
	do $$$AssertEquals(tPaused.error, "", "and no error")
	do $$$AssertEquals(tHealthy.rowSources.%Size(), 1, "healthy pipeline has its device")
}

/// An unexpected failure describing one pipeline is that item's error; the
/// others are still listed.
Method TestListItemFailure()
{
	set ^||OPCUA.Tests("failPipelineItem") = ..#Healthy
	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	kill ^||OPCUA.Tests("failPipelineItem")
	do $$$AssertStatusOK(tSC, "List answers when one item fails")
	Quit:$$$ISERR(tSC)
	set tPaused = ..Find(tList, ..#Paused), tHealthy = ..Find(tList, ..#Healthy)
	do $$$AssertTrue($IsObject(tHealthy), "failing pipeline is still listed")
	do $$$AssertTrue($IsObject(tPaused), "the other pipeline is listed")
	Quit:'$IsObject(tPaused)||'$IsObject(tHealthy)
	do $$$AssertTrue(tHealthy.error [ "Forced", "failing item carries its error: '"_tHealthy.error_"'")
	do $$$AssertEquals(tPaused.error, "", "the other item has no error")
}

ClassMethod Find(pList As %DynamicArray, pName As %String) As %DynamicObject
{
	for i=0:1:pList.%Size()-1 {
		Return:pList.%Get(i).name=pName pList.%Get(i)
	}
	Quit ""
}

/// Set an item's DeviceNodePaths the way the Portal does: saved config, no API.
ClassMethod SetDevicePaths(pName As %String, pValue As %String) As %Status
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
	Quit:'$IsObject(tProd) $$$ERROR($$$GeneralError, "no pipeline production")
	for i=1:1:tProd.Items.Count() {
		set tItem = tProd.Items.GetAt(i)
		continue:tItem.Name'=pName
		for j=1:1:tItem.Settings.Count() {
			set tS = tItem.Settings.GetAt(j)
			if tS.Name = "DeviceNodePaths" set tS.Value = pValue
		}
	}
	set tSC = tProd.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit tProd.SaveToClass()
}

/// Never throws: test cleanup must not fail the run.
ClassMethod DoCleanup()
{
	for tName = ..#Paused, ..#Healthy {
		Try {
			do ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
		} Catch (eDelete) {
			// Cleanup is best effort; the SQL delete below catches leftovers.
		}
		&sql(DELETE FROM Ens_Config.Item WHERE Name = :tName)
	}
	Try {
		if ##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass) {
			do $classmethod(..#SchemaClass, "%KillExtent")
		}
		if ##class(%Dictionary.ClassDefinition).%ExistsId(..#SchemaClass) {
			do $System.OBJ.Delete(..#SchemaClass, "-d")
		}
		kill ^OPCUA.DataSource(..#SchemaClass)
	} Catch (e) {
		// Cleanup is best effort.
	}
}

ClassMethod BuildSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#SchemaClass)
	set tDef.Description = "Throwaway schema for SweepLiveTest"
	set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE"
	set tParam.Default = "TmpSweepLive"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE"
	set tParam.Default = 1
	do tDef.Parameters.Insert(tParam)
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "NodePath"
	set tProp.Type = "%String"
	do tProp.Parameters.SetAt(500, "MAXLEN")
	do tDef.Properties.Insert(tProp)
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "SA1"
	set tProp.Type = "OPCUA.Types.IntegerDataValue"
	do tProp.Parameters.SetAt("SA1", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)
	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#SchemaClass, "ck-d")
}

}
