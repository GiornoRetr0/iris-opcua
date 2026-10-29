Include (%occInclude, Ensemble)

/// Offline tests for schema usage tracking across multiple productions.
///
/// Creates a throwaway production, <tt>OPCUA.Tests.Tmp.ClientProd</tt>, with an
/// item using a temporary schema. Confirms that <tt>SchemaService.Delete</tt>
/// refuses to delete the schema while it is in use, and that usage information
/// includes the production name and managed flag.
Class OPCUA.Tests.Unit.SchemaUsageTest Extends %UnitTest.TestCase
{

Parameter ClientProduction = "OPCUA.Tests.Tmp.ClientProd";

Parameter Schema = "OPCUA.Tests.Tmp.DeviceSchema";

Parameter ServiceClass = "OPCUA.Service.TCPPollingRowSourceService";

Parameter ItemName = "TestDevice";

Method OnBeforeAllTests() As %Status
{
	set tSC = ..CreateTestSchema()
	Quit:$$$ISERR(tSC) tSC
	Quit ..CreateTestProduction()
}

Method OnAfterAllTests() As %Status
{
	do ..DropProduction()
	do ..DropSchema()
	kill ^||OPCUA.Tests("failUsage")
	Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
	kill ^||OPCUA.Tests("failUsage")
	Quit $$$OK
}

/// Schema delete refuses while a hand-built production uses it, and the error
/// names both the item and the production.
Method TestUsageInHandBuiltProduction()
{
	set tBody = {"name": (..#Schema)}
	set tSC = ##class(OPCUA.REST.SchemaService).Delete(tBody, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Delete refuses while schema is used")

	set tMsg = $System.Status.GetErrorText(tSC)
	do $$$AssertTrue(tMsg [ ..#ItemName, "error names the item: "_tMsg)
	do $$$AssertTrue(tMsg [ ..#ClientProduction, "error names the production: "_tMsg)

	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema still exists after refused delete")
}

/// A failure in MapSchemaUsage causes Delete to return an error and the schema
/// to survive.
Method TestUsageFailureRefusesDelete()
{
	set ^||OPCUA.Tests("failUsage") = 1

	set tBody = {"name": (..#Schema)}
	set tSC = ##class(OPCUA.REST.SchemaService).Delete(tBody, .tResult)
	do $$$AssertNotTrue($$$ISOK(tSC), "Delete refuses when MapSchemaUsage fails")
	do $$$AssertTrue(##class(%Dictionary.ClassDefinition).%ExistsId(..#Schema), "schema still exists after failed usage check")
}

/// DescribeSchema returns usedBy with production and managed flag. For the
/// hand-built production, managed = false.
Method TestUsedByShape()
{
	do ##class(OPCUA.REST.SchemaService).MapSchemaUsage(.tUsage)
	set tSC = ##class(OPCUA.REST.SchemaService).Get({"name":(..#Schema)}, .tResult)
	do $$$AssertStatusOK(tSC, "Get schema")
	Quit:$$$ISERR(tSC)

	set tUsedBy = tResult.usedBy
	do $$$AssertTrue($IsObject($Get(tUsedBy)), "usedBy is an array")
	do $$$AssertEquals(tUsedBy.%Size(), 1, "one usage")

	set tEntry = tUsedBy.%Get(0)
	do $$$AssertEquals(tEntry.name, ..#ItemName, "name matches item")
	do $$$AssertEquals(tEntry.production, ..#ClientProduction, "production matches")
	do $$$AssertEquals(tEntry.managed, 0, "managed = false for non-Pipeline.Production")
}

/// Create a minimal DeviceSchema subclass for testing.
ClassMethod CreateTestSchema() As %Status
{
	do ..DropSchema()

	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#Schema)
	set tDef.Super = "OPCUA.DataSource.DeviceSchema,%Persistent"
	set tDef.Description = "Throwaway schema for SchemaUsageTest"

	// OPCUADATASOURCE parameter is required
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE"
	set tParam.Default = "TestDevice"
	do tDef.Parameters.Insert(tParam)

	// OPCUDEFAULTANAMESPACE parameter is required
	set tParam2 = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam2.Name = "OPCUDEFAULTANAMESPACE"
	set tParam2.Default = "1"
	do tDef.Parameters.Insert(tParam2)

	// One simple column
	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "Temperature"
	set tProp.Type = "OPCUA.Types.DoubleDataValue"
	do tProp.Parameters.SetAt("Temperature", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC

	set tSC = $System.OBJ.Compile(..#Schema, "ck-d")
	Quit tSC
}

/// Create a production that uses the test schema.
ClassMethod CreateTestProduction() As %Status
{
	do ..DropProduction()

	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#ClientProduction)
	set tDef.Super = "Ens.Production"
	set tDef.Description = "Throwaway production for SchemaUsageTest. Never started."

	set tX = ##class(%Dictionary.XDataDefinition).%New()
	set tX.Name = "ProductionDefinition"
	do tX.Data.Write("<Production Name="""_..#ClientProduction_""">")
	do tX.Data.Write("<Item Name="""_..#ItemName_""" ClassName="""_..#ServiceClass_""" Enabled=""false"">")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DataSourceClass"">")
	do tX.Data.Write(..#Schema)
	do tX.Data.Write("</Setting>")
	do tX.Data.Write("<Setting Target=""Adapter"" Name=""DeviceNodePaths"">ns=1;i=123</Setting>")
	do tX.Data.Write("</Item>")
	do tX.Data.Write("</Production>")
	do tDef.XDatas.Insert(tX)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC

	set tSC = $System.OBJ.Compile(..#ClientProduction, "ck-d")
	Quit:$$$ISERR(tSC) tSC

	Quit ##class(Ens.Config.Production).LoadFromClass(..#ClientProduction)
}

ClassMethod DropProduction()
{
	set tProd = ..#ClientProduction
	&sql(DELETE FROM Ens_Config.Item WHERE Production = :tProd)
	do:##class(Ens.Config.Production).%ExistsId(tProd) ##class(Ens.Config.Production).%DeleteId(tProd)
	do:##class(%Dictionary.ClassDefinition).%ExistsId(tProd) $System.OBJ.Delete(tProd, "-d")
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

}
