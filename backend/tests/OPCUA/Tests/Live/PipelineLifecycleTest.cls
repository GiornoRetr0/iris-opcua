Include (OPCUA.Constants, %occInclude, Ensemble)

/// Tests for pipeline lifecycle operations — deploy, delete, recreate with same name.
/// Verifies the config item row is properly deleted, not left orphaned.
Class OPCUA.Tests.Live.PipelineLifecycleTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpLifecycleSchema";

Parameter PipelineName = "TmpLifecycle";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Deploy a pipeline, enable it, delete it, deploy again with the same name, then toggle it.
/// The toggle should succeed, and the config item row count after delete should be 0.
Method TestDeleteThenRecreateSameName()
{
    #dim tSC As %Status = $$$OK
    Try {
        // Arrange: build schema offline like Live.PortalPipelineTest does
        set tSC = ..BuildSchema()
        Do $$$AssertStatusOK(tSC, "Schema creation should succeed")
        Quit:$$$ISERR(tSC)

        set tURL = $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
        set tDevices = "i=85|Objects"

        // Act 1: Deploy the pipeline
        set tDeployBody = {
            "dataSourceName": (..#PipelineName),
            "schemaClass": (..#SchemaClass),
            "mode": "polling",
            "url": (tURL),
            "deviceNodePaths": (tDevices),
            "callInterval": 2
        }
        set tSC = ##class(OPCUA.REST.DeployService).Deploy(tDeployBody, .tDeployResult)
        Do $$$AssertStatusOK(tSC, "First deploy should succeed")
        Quit:$$$ISERR(tSC)

        // Act 2: Enable the pipeline
        set tToggleBody = {"name": (..#PipelineName)}
        set tSC = ##class(OPCUA.REST.PipelineService).Toggle(tToggleBody, .tToggleResult)
        Do $$$AssertStatusOK(tSC, "First toggle should succeed")
        Quit:$$$ISERR(tSC)

        // Act 3: Delete the pipeline
        set tDeleteBody = {"name": (..#PipelineName)}
        set tSC = ##class(OPCUA.REST.PipelineService).Delete(tDeleteBody, .tDeleteResult)
        Do $$$AssertStatusOK(tSC, "Delete should succeed")
        Quit:$$$ISERR(tSC)

        // Assert: Config item row should be gone
        set tPipelineName = ..#PipelineName
        &sql(SELECT COUNT(*) INTO :tRowCount FROM Ens_Config.Item WHERE Name = :tPipelineName)
        Do $$$AssertEquals(tRowCount, 0, "Config item row count after delete should be 0")
        Do $$$AssertEquals(SQLCODE, 0, "Row count query should succeed")

        // Act 4: Deploy again with the same name
        set tSC = ##class(OPCUA.REST.DeployService).Deploy(tDeployBody, .tDeployResult2)
        Do $$$AssertStatusOK(tSC, "Second deploy with same name should succeed")
        Quit:$$$ISERR(tSC)

        // Act 5: Toggle the recreated pipeline
        set tSC = ##class(OPCUA.REST.PipelineService).Toggle(tToggleBody, .tToggleResult2)
        Do $$$AssertStatusOK(tSC, "Toggle after recreate should succeed")

    } Catch (e) {
        Do $$$AssertTrue(0, "Exception: "_e.DisplayString())
    }
}

/// Remove whatever an earlier, failed run left behind, so it can't break this one.
Method OnBeforeAllTests() As %Status
{
    do ..DoCleanup()
    Quit $$$OK
}

/// Clean up test artifacts. %UnitTest runs this whatever the tests did, and
/// DoCleanup never throws.
Method OnAfterAllTests() As %Status
{
    do ..DoCleanup()
    Quit $$$OK
}

/// Clean up test artifacts - can be called manually or from OnAfterAllTests
ClassMethod DoCleanup()
{
    // Delete the pipeline through the API first: it also updates a running
    // production, so the item's job stops and the schema class is not in use.
    Try {
        do ##class(OPCUA.REST.PipelineService).Delete({"name": (..#PipelineName)}, .tResult)
    } Catch (eDelete) {}

    Try {
        // Fallback: remove the item directly if the API delete could not
        if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
            set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
            if $IsObject(tProd) {
                set tFoundIdx = 0
                for i=1:1:tProd.Items.Count() {
                    if tProd.Items.GetAt(i).Name = ..#PipelineName {
                        set tFoundIdx = i
                        Quit
                    }
                }
                if tFoundIdx > 0 {
                    do tProd.Items.RemoveAt(tFoundIdx)
                    do tProd.%Save()
                    do tProd.SaveToClass()
                }
            }
        }

        // Delete any orphaned config item rows
        set tPipelineName = ..#PipelineName
        &sql(DELETE FROM Ens_Config.Item WHERE Name = :tPipelineName)
    } Catch (e) {}

    // Delete the schema, even when the steps above failed
    Try {
        Try {
            if ##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass) {
                do $classmethod(..#SchemaClass, "%KillExtent")
            }
        } Catch (eKill) {}
        if ##class(%Dictionary.ClassDefinition).%ExistsId(..#SchemaClass) {
            do $System.OBJ.Delete(..#SchemaClass, "-d")
        }
        kill ^OPCUA.DataSource(..#SchemaClass)

    } Catch (e) {}
}

/// Build a minimal schema for testing
ClassMethod BuildSchema() As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        set tDef = ##class(%Dictionary.ClassDefinition).%New(..#SchemaClass)
        set tDef.Description = "Throwaway schema for PipelineLifecycleTest"
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUADATASOURCE"
        set tParam.Default = "TmpLifecycle"
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

        for tName = "ServerTimeStamp", "SourceTimeStamp" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%TimeStamp"
            do tDef.Properties.Insert(tProp)
        }

        set tProp = ##class(%Dictionary.PropertyDefinition).%New()
        set tProp.Name = "SA1"
        set tProp.Type = "OPCUA.Types.IntegerDataValue"
        do tProp.Parameters.SetAt("SA1", "OPCUANODENAME")
        do tDef.Properties.Insert(tProp)

        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(..#SchemaClass, "ck-d")
        $$$ThrowOnError(tSC)

        Try { do $classmethod(..#SchemaClass, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

}
