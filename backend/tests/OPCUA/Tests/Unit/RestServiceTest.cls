Include (%occInclude, Ensemble)

/// Offline tests for the pipeline REST services: <class>OPCUA.REST.PipelineService</class>
/// List (with health), Toggle, Delete and Rebind, and the
/// <class>OPCUA.REST.SchemaService</class> Delete refusal while a pipeline uses a
/// schema. Needs no server, no native library and no running production.
///
/// Works on a throwaway production, <tt>OPCUA.Tests.Tmp.RestProduction</tt>, that
/// is never started and is rebuilt before every test. <tt>^||OPCUA.Tests("production")</tt>
/// points the services at it, and <tt>^||OPCUA.Tests("productionStatus")</tt>
/// stands in for it running where a test needs that.
///
/// Not covered here, because they need more than this: enabling a pipeline
/// (starts the pipeline production) and a rebind that gets past validation (browses
/// the server). Live.PipelineConcurrencyTest and Live.RestStatusTest cover those.
Class OPCUA.Tests.Unit.RestServiceTest Extends %UnitTest.TestCase
{

Parameter Production = "OPCUA.Tests.Tmp.RestProduction";

Parameter Schema = "OPCUA.Tests.Tmp.RestSchema";

/// Enabled, polling, with categories.
Parameter OnItem = "Rest.On";

/// Disabled, subscription, a name with a space and a hyphen.
Parameter OffItem = "Rest Off-1";

Method OnBeforeAllTests() As %Status
{
	Quit ..CreateSchema()
}

Method OnAfterAllTests() As %Status
{
	do ..DropProduction()
	do ..DropSchema()
	kill ^||OPCUA.Tests("production"), ^||OPCUA.Tests("productionStatus")
	do ..ClearMonitor()
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("productionStatus")
	do ..ClearMonitor()
	set ^||OPCUA.Tests("production") = ..#Production
	Quit ..CreateProduction()
}

Method OnAfterOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("productionStatus")
	do ..ClearMonitor()
	Quit $$$OK
}

/// List returns the pipelines of the production being edited, each with its
/// settings, mode and categories. Stopped is the health of every item while the
/// production is not running.
Method TestListShape()
{
	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	do $$$AssertStatusOK(tSC, "List")
	do $$$AssertEquals(tList.%Size(), 2, "the two items of the tmp production, and nothing else")

	set tOn = ..Entry(tList, ..#OnItem)
	do $$$AssertTrue($IsObject(tOn), "'"_..#OnItem_"' is listed")
	Quit:'$IsObject(tOn)
	do $$$AssertEquals(tOn.enabled, 1, "enabled")
	do $$$AssertEquals(tOn.mode, "polling", "polling mode")
	do $$$AssertEquals(tOn.pipelineVersion, 2, "row-source pipeline")
	do $$$AssertEquals(tOn.dataSourceClass, ..#Schema, "schema")
	do $$$AssertEquals(tOn.deviceNodePaths, "ns=1;s=SA1|Dev A", "device list")
	do $$$AssertEquals(tOn.serverUrl, "opc.tcp://plc", "server URL")
	do $$$AssertEquals(tOn.categories.%ToJSON(), "[""A"",""B""]", "categories as an array")
	do $$$AssertEquals(tOn.tableName, ##class(OPCUA.REST.SchemaService).TableName(..#Schema), "table name")
	do $$$AssertEquals(tOn.%GetTypeOf("rowCount"), "number", "row count is a number")
	do $$$AssertEquals(tOn.rowCount, 0, "no rows yet")
	do $$$AssertEquals(tOn.productionRunning, 0, "production not running")
	do $$$AssertEquals(tOn.running, 0, "not running")
	do $$$AssertEquals(tOn.health, "stopped", "health is stopped while the production is not running")
	do $$$AssertEquals(tOn.rowSources.%Size(), 1, "one row source per device")

	set tOff = ..Entry(tList, ..#OffItem)
	do $$$AssertTrue($IsObject(tOff), "'"_..#OffItem_"' is listed")
	Quit:'$IsObject(tOff)
	do $$$AssertEquals(tOff.enabled, 0, "disabled")
	do $$$AssertEquals(tOff.mode, "subscription", "subscription mode")
	do $$$AssertEquals(tOff.health, "stopped", "stopped")
}

/// With the production running, health tells disabled, starting, ok and error apart.
Method TestListHealth()
{
	set ^||OPCUA.Tests("productionStatus") = $ListBuild(..#Production, 1)

	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	do $$$AssertStatusOK(tSC, "List")
	do $$$AssertEquals(..Entry(tList, ..#OnItem).productionRunning, 1, "production running")
	do $$$AssertEquals(..Entry(tList, ..#OnItem).health, "starting", "enabled with no completed cycle is starting")
	do $$$AssertEquals(..Entry(tList, ..#OffItem).health, "disabled", "a disabled item is disabled")

	$$$SetHostMonitor(..#OnItem, $$$eMonitorStatus, "OK")
	set $$$EnsHostMonitorRoot($namespace, ..#OnItem, $$$eMonitorCount) = 7
	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	set tOn = ..Entry(tList, ..#OnItem)
	do $$$AssertEquals(tOn.health, "ok", "a host reporting OK is ok")
	do $$$AssertEquals(tOn.cycles, 7, "cycles come from the host monitor")
	do $$$AssertNotEquals(tOn.lastActivity, "", "last activity is reported")

	$$$SetHostMonitor(..#OnItem, $$$eMonitorStatus, "Error")
	set tSC = ##class(OPCUA.REST.PipelineService).List({}, .tList)
	do $$$AssertEquals(..Entry(tList, ..#OnItem).health, "error", "a host reporting anything else is error")
}

/// Disabling saves the item disabled and says honestly that nothing restarted.
Method TestToggleDisable()
{
	set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#OnItem)}, .tRes)
	do $$$AssertStatusOK(tSC, "Toggle")
	do $$$AssertEquals(tRes.enabled, 0, "reported disabled")
	do $$$AssertEquals(tRes.restarted, 0, "restarted is 0: the production is not running")
	do $$$AssertTrue(tRes.restartNote [ "not running", "the note says why: "_tRes.restartNote)
	do $$$AssertEquals(..StoredEnabled(..#OnItem), 0, "stored disabled")
	set tTag = ..ClassItemTag(..#OnItem)
	do $$$AssertTrue(tTag [ "Enabled=""false""", "saved disabled to the class: "_tTag)
	do $$$AssertEquals(..StoredEnabled(..#OffItem), 0, "the other item is untouched")
}

Method TestToggleRefusals()
{
	set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": "NoSuchPipeline"}, .tRes)
	do $$$AssertStatusNotOK(tSC, "an unknown pipeline is refused")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 404, "unknown pipeline is 404")

	set tSC = ##class(OPCUA.REST.PipelineService).Toggle({}, .tRes)
	do $$$AssertStatusNotOK(tSC, "a missing name is refused")
	do $$$AssertEquals(..StoredEnabled(..#OnItem), 1, "nothing changed")
}

/// Delete removes the item from storage and the class, keeps the schema, and
/// reports who else still uses it. Schema delete refuses until the last pipeline
/// on it is gone, then succeeds.
Method TestDeleteKeepsSchemaAndRefusal()
{
	set tSC = ##class(OPCUA.REST.PipelineService).Delete({"name": (..#OffItem)}, .tRes)
	do $$$AssertStatusOK(tSC, "Delete '"_..#OffItem_"'")
	do $$$AssertEquals(tRes.deleted, 1, "deleted")
	do $$$AssertEquals(tRes.schemaClass, ..#Schema, "reports its schema")
	do $$$AssertEquals(tRes.schemaRetained, 1, "schema retained")
	do $$$AssertEquals(tRes.schemaStillUsedBy.%Size(), 1, "one pipeline still uses the schema")
	do $$$AssertEquals(tRes.schemaStillUsedBy.%Get(0).name, ..#OnItem, "and it is named")
	do $$$AssertEquals(..StoredEnabled(..#OffItem), "", "gone from storage")
	do $$$AssertNotTrue(..ClassHas(..#OffItem), "gone from the class")
	set tProdName = ..#Production, tItemName = ..#OffItem
	&sql(SELECT COUNT(*) INTO :tRows FROM Ens_Config.Item WHERE Production = :tProdName AND Name = :tItemName)
	do $$$AssertEquals(SQLCODE, 0, "config item count query runs")
	do $$$AssertEquals(tRows, 0, "no orphan config item row")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema class kept")

	set tSC = ##class(OPCUA.REST.SchemaService).Delete({"name": (..#Schema)}, .tRes)
	do $$$AssertStatusNotOK(tSC, "schema delete refused while '"_..#OnItem_"' uses it")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 409, "refusal is 409")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ ..#OnItem, "refusal names the pipeline: "_$System.Status.GetErrorText(tSC))
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema survives the refusal")

	set tSC = ##class(OPCUA.REST.PipelineService).Delete({"name": (..#OnItem)}, .tRes)
	do $$$AssertStatusOK(tSC, "Delete '"_..#OnItem_"'")
	do $$$AssertEquals(tRes.schemaStillUsedBy.%Size(), 0, "nothing uses the schema now")

	set tSC = ##class(OPCUA.REST.SchemaService).Delete({"name": (..#Schema)}, .tRes)
	do $$$AssertStatusOK(tSC, "schema delete succeeds once unused")
	do $$$AssertNotTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema class gone")
	// The next test needs it again.
	do $$$AssertStatusOK(..CreateSchema(), "schema recreated")
}

Method TestDeleteRefusals()
{
	set tSC = ##class(OPCUA.REST.PipelineService).Delete({"name": "NoSuchPipeline"}, .tRes)
	do $$$AssertStatusNotOK(tSC, "an unknown pipeline is refused")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 404, "unknown pipeline is 404")

	set tSC = ##class(OPCUA.REST.PipelineService).Delete({}, .tRes)
	do $$$AssertStatusNotOK(tSC, "a missing name is refused")
	do $$$AssertEquals(..StoredEnabled(..#OnItem), 1, "nothing was removed")
	do $$$AssertEquals(..StoredEnabled(..#OffItem), 0, "nothing was removed")
}

/// Rebind refuses before touching anything when the request is unusable. The
/// stored device list stays as it was.
Method TestRebindRefusals()
{
	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"devices": "ns=1;s=SA2"}, .tRes)
	do $$$AssertStatusNotOK(tSC, "a missing name is refused")

	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#OnItem)}, .tRes)
	do $$$AssertStatusNotOK(tSC, "a missing device list is refused")
	do $$$AssertTrue($System.Status.GetErrorText(tSC) [ "No devices supplied", "error says no devices: "_$System.Status.GetErrorText(tSC))

	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": (..#OnItem), "devices": ("garbage"_$Char(10)_"ns=x;s=A")}, .tRes)
	do $$$AssertStatusNotOK(tSC, "a list with no usable device is refused")
	set tText = $System.Status.GetErrorText(tSC)
	do $$$AssertTrue((tText [ "Line 1 (garbage)") && (tText [ "Line 2 (ns=x;s=A)"), "every bad line is reported: "_tText)
	do $$$AssertEquals(tRes.updated, 0, "not updated")

	set tSC = ##class(OPCUA.REST.PipelineService).Rebind({"name": "NoSuchPipeline", "devices": "ns=1;s=SA2"}, .tRes)
	do $$$AssertStatusNotOK(tSC, "an unknown pipeline is refused")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 404, "unknown pipeline is 404")

	do $$$AssertEquals(..StoredDevices(..#OnItem), "ns=1;s=SA1|Dev A", "the stored device list is unchanged")
}

// ==================== fixtures ====================

ClassMethod Entry(pList As %DynamicArray, pName As %String) As %DynamicObject
{
	for i=0:1:pList.%Size()-1 {
		return:pList.%Get(i).name=pName pList.%Get(i)
	}
	Quit ""
}

/// The stored item, reread from disk, or "".
ClassMethod StoredItem(pName As %String) As Ens.Config.Item
{
	set tProd = ##class(Ens.Config.Production).%OpenId(..#Production, 0)
	Quit:'$IsObject(tProd) ""
	do tProd.%Reload()
	for i=1:1:tProd.Items.Count() {
		set tItem = tProd.Items.GetAt(i)
		do tItem.%Reload()
		return:tItem.Name=pName tItem
	}
	Quit ""
}

/// The stored item's Enabled flag, or "" when there is no such item.
ClassMethod StoredEnabled(pName As %String) As %String
{
	set tItem = ..StoredItem(pName)
	Quit $Select($IsObject(tItem):+tItem.Enabled, 1:"")
}

ClassMethod StoredDevices(pName As %String) As %String
{
	set tItem = ..StoredItem(pName)
	Quit:'$IsObject(tItem) ""
	for i=1:1:tItem.Settings.Count() {
		return:tItem.Settings.GetAt(i).Name="DeviceNodePaths" tItem.Settings.GetAt(i).Value
	}
	Quit ""
}

ClassMethod ClassHas(pText As %String) As %Boolean
{
	set tX = ##class(%Dictionary.XDataDefinition).%OpenId(..#Production_"||ProductionDefinition", 0)
	Quit:'$IsObject(tX) 0
	do tX.%Reload()
	Quit tX.Data.Read(1000000) [ pText
}

/// The item's opening tag in the production class's XData, or "".
ClassMethod ClassItemTag(pName As %String) As %String
{
	set tX = ##class(%Dictionary.XDataDefinition).%OpenId(..#Production_"||ProductionDefinition", 0)
	Quit:'$IsObject(tX) ""
	do tX.%Reload()
	set tXml = tX.Data.Read(1000000)
	set tAt = $Find(tXml, "Name="""_pName_"""")
	Quit:tAt=0 ""
	Quit "<Item "_$Piece($Extract(tXml, tAt - $Length(pName) - 7, *), ">", 1)_">"
}

ClassMethod ClearMonitor()
{
	kill $$$EnsHostMonitorRoot($namespace, ..#OnItem), $$$EnsHostMonitorRoot($namespace, ..#OffItem)
}

ClassMethod CreateSchema() As %Status
{
	do ..DropSchema()
	set tCols = [{"displayName": "SA1", "inferredType": "OPCUA.Types.IntegerDataValue", "relativePath": ["SA1"]}]
	Quit ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(..#Schema, "TmpRestSchema", tCols, 1, .tColNS, .tSerial)
}

ClassMethod DropSchema()
{
	set tSchema = ..#Schema
	if ##class(%Dictionary.CompiledClass).%ExistsId(tSchema) {
		try { do $classmethod(tSchema, "%KillExtent") } catch eKill {}
	}
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tSchema) $System.OBJ.Delete(tSchema, "-d")
	kill ^OPCUA.DataSource(tSchema)
}

ClassMethod CreateProduction() As %Status
{
	do ..DropProduction()
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Production)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for RestServiceTest. Never started."

	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#Production_""">")
	do tX.Data.Write("<Item Name="""_..#OnItem_""" Category=""A,B"" ClassName=""OPCUA.Service.TCPPollingRowSourceService"" PoolSize=""1"" Enabled=""true"">")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DataSourceClass"">"_..#Schema_"</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DeviceNodePaths"">ns=1;s=SA1|Dev A</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""URL"">opc.tcp://plc</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""CallInterval"">5</Setting>")
	do tX.Data.Write("</Item>")
	do tX.Data.Write("<Item Name="""_..#OffItem_""" ClassName=""OPCUA.Service.TCPSubscriptionRowSourceService"" PoolSize=""1"" Enabled=""false"">")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DataSourceClass"">"_..#Schema_"</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DeviceNodePaths"">ns=1;s=SA2</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""URL"">opc.tcp://plc</Setting>")
	do tX.Data.Write("</Item>")
	do tX.Data.Write("</Production>")
	do tDef.XDatas.Insert(tX)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	set tSC = $System.OBJ.Compile(..#Production, "ck-d")
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(Ens.Config.Production).LoadFromClass(..#Production)
}

ClassMethod DropProduction()
{
	set tProd = ..#Production
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
}

}
