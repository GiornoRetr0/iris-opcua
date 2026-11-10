Include (OPCUA.Constants, %occInclude, Ensemble)

/// Proves a working row-source pipeline can be built with NO webapp and NO
/// /deploy call — only a schema class and ordinary IRIS production configuration
/// (PRD §10 acceptance criteria 3-6).
///
/// The tests run in order (Test1..Test6) and build on each other, as the steps a
/// Portal user takes do. Waits poll for the condition they need
/// (<method>WaitFor</method>) instead of sleeping a fixed time.
///
/// What it exercises, in the order a Portal user would:
///   1. a hand-authored schema class appears in the DataSourceClass dropdown
///   2. adding a config item + typing device nodepaths yields a running pipeline
///   3. adding a device is a one-line setting edit with no recompile
///   4. a device missing a column stores NULL and logs a warning naming both
///   5. an unresolved column never stops the pipeline
///   6. POST /deploy creates the pipeline stopped and collects nothing until started
///   7. enabling never stops another production
Class OPCUA.Tests.Live.PortalPipelineTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpPortalSchema";

Parameter ItemName = "ZZPortalPipelineTest";

/// A second schema + item, used only by Test5DeployDoesNotAutostart. Separate from
/// the pair above because that pipeline is deliberately left collecting by tests
/// 2-4, and "no rows yet" can only be asserted on a table nothing else writes to.
Parameter DeploySchemaClass = "OPCUA.Tests.TmpDeploySchema";

Parameter DeployItemName = "ZZPortalDeployTest";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// A throwaway production standing in for someone else's, in test 6.
Parameter OtherProductionClass = "OPCUA.Tests.TmpOtherProduction";

/// Whether the pipeline production was running before the suite, so
/// <method>OnAfterAllTests</method> can put it back.
Property WasRunning As %Boolean [ InitialExpression = 0 ];

/// Starting the pipeline production would be refused while another production
/// runs, and this suite never stops a production it does not own.
Method OnBeforeAllTests() As %Status
{
    set tSC = ##class(OPCUA.REST.DeployService).CheckNoOtherProduction()
    Quit:$$$ISERR(tSC) tSC
    do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
    set ..WasRunning = (tRunning = ..#ProductionClass) && (tState = 1)
    do ..Cleanup()
    Quit $$$OK
}

/// Remove what the suite added and put the pipeline production back.
Method OnAfterAllTests() As %Status
{
    do ..Cleanup()
    do ..RestoreProduction(..WasRunning)
    Quit $$$OK
}

/// The live server, as set by <method>OPCUA.Tests.Runner.Live</method>.
ClassMethod URL() As %String [ CodeMode = expression ]
{
$Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

/// Poll <var>pCondition</var> every 0.5 s until it is true or
/// <var>pTimeoutSec</var> runs out, and assert that it came true. The condition
/// is an ObjectScript expression in which <var>t</var> is this test case, e.g.
/// <code>t.RowCount() > 0</code>. Returns whether it came true.
Method WaitFor(pCondition As %String, pTimeoutSec As %Integer = 30) As %Boolean
{
    set tStart = $ZHorolog, tOK = 0
    for {
        set tOK = ''$Xecute("(t) quit "_pCondition, $this)
        quit:tOK
        quit:(($ZHorolog-tStart)>=pTimeoutSec)
        hang 0.5
    }
    set tTook = $FNumber($ZHorolog - tStart, "", 1)
    do $$$AssertTrue(tOK, $Select(tOK:"came true after "_tTook_" s: ", 1:"timed out after "_pTimeoutSec_" s waiting for: ")_pCondition)
    Quit tOK
}

/// A schema class written by hand (no wizard) must show up in the dropdown that
/// backs the DataSourceClass setting.
Method Test1SchemaDiscoverable()
{
    set tSC = ..BuildSchema()
    do $$$AssertEquals($$$ISOK(tSC), 1, "hand-authored schema compiles")
    if $$$ISERR(tSC) {
        do $$$LogMessage($System.Status.GetOneErrorText(tSC))
        quit
    }

    // Exactly what the Portal's selector does for this setting.
    kill tParms, tResults
    set tParms("class") = "OPCUA.DataSource.DeviceSchema"
    set tSC = ##class(Ens.ContextSearch).SubclassOf(.tCaption, .tTop, .tResults, .tParms)
    do $$$AssertEquals($$$ISOK(tSC), 1, "SubclassOf succeeds")

    set tFound = 0, tSawAbstract = 0, i = ""
    for {
        set i = $Order(tResults(i))
        quit:i=""
        if tResults(i) = ..#SchemaClass set tFound = 1
        if tResults(i) = "OPCUA.DataSource.DeviceSchema" set tSawAbstract = 1
    }
    do $$$AssertEquals(tFound, 1, "schema appears in the dropdown")
    do $$$AssertEquals(tSawAbstract, 0, "abstract base is excluded")

    // The setting must actually carry the selector url through to the Portal.
    kill tSettings
    do ##class(OPCUA.Adapter.TCPPollingInboundAdapter).GetSettings(.tSettings)
    set tCat = $Get(tSettings(":", "DataSourceClass"))
    set tUrl = $Get(tSettings(tCat, "DataSourceClass"))
    do $$$AssertEquals((tUrl [ "selector?context="), 1, "DataSourceClass renders as a selector")
    do $$$AssertEquals((tUrl [ "OPCUA.DataSource.DeviceSchema"), 1, "selector filters on DeviceSchema")
    do $$$AssertEquals(''$Data(tSettings(":", "DeviceNodePaths")), 1, "DeviceNodePaths is a registered setting")
}

/// Build the pipeline using only the Ens.Config API the Portal drives, then
/// confirm it actually collects rows.
Method Test2PortalBuild()
{
    set pURL = ..URL()
    set tSC = ..EnsureProduction()
    do $$$AssertEquals($$$ISOK(tSC), 1, "shared production exists")
    Quit:$$$ISERR(tSC)

    // "Add a business service item", fill in settings, start.
    set tSC = ..AddItem(pURL, "i=85|Objects")
    do $$$AssertEquals($$$ISOK(tSC), 1, "config item added and production started")
    if $$$ISERR(tSC) {
        do $$$LogMessage($System.Status.GetOneErrorText(tSC))
        quit
    }

    do ..WaitFor("t.RowCount() > 0 && t.HasNodePath(""Objects"") && t.HasNonNull(""SA1"")")

    do $$$AssertEquals((..RowCount() > 0), 1, "pipeline collected rows")
    do $$$AssertEquals(..HasNodePath("Objects"), 1, "NodePath is tagged from the device label")
    do $$$AssertEquals(..HasNonNull("SA1"), 1, "values are populated")

    // The whole point: no device metadata global is involved.
    do $$$AssertEquals($Data(^OPCUA.RowSource(..#SchemaClass)), 0, "no ^OPCUA.RowSource entry was written")
}

/// Adding a device must be a one-line setting edit: no regeneration, no recompile.
Method Test3AddDevice()
{
    set tBefore = ..CompileStamp()

    // Second device deliberately has none of the schema's columns, which also
    // exercises the store-NULL-and-warn path.
    set tSC = ..SetSetting("DeviceNodePaths", "i=85|Objects" _ $Char(10) _ "# commented out" _ $Char(10) _ "i=2253|NoColumns")
    do $$$AssertEquals($$$ISOK(tSC), 1, "device list edited and applied")
    Quit:$$$ISERR(tSC)

    do ..WaitFor("t.HasNullColumn(""NoColumns"", ""SA1"") && t.LoggedWarningMatching(""NoColumns"", ""SA1"")")

    do $$$AssertEquals(..CompileStamp(), tBefore, "schema class was NOT recompiled")
    do $$$AssertEquals(..HasNodePath("Objects"), 1, "original device still reporting")
    do $$$AssertEquals(..HasNodePath("NoColumns"), 1, "added device is reporting")
    do $$$AssertEquals(..HasNodePath("commented out"), 0, "commented-out device ignored")

    // A device missing a column stores NULL for it and says so in the event log,
    // naming the device and the column.
    do $$$AssertEquals(..HasNullColumn("NoColumns", "SA1"), 1, "missing column stored as NULL")
    do $$$AssertEquals(..LoggedWarningMatching("NoColumns", "SA1"), 1, "warning names the device and column")
}

/// An unresolved column must never stop the pipeline.
///
/// Coverage is reported before deploy (POST /schemas/:name/validate), so binding
/// a partially matching device is a deliberate choice. Store NULL, warn, and keep
/// collecting everything that did resolve — a device with one missing node must
/// not cost the operator the other nine.
Method Test4PartialDeviceKeepsCollecting()
{
    do ..ClearLog()
    set tBaseline = ..RowCount()

    // Resolution diagnostics are emitted on connect, not per poll cycle, so an
    // empty log alone would prove nothing. Rewriting the device list forces the
    // item to restart and re-resolve, which is what generates fresh entries.
    set tSC = ..SetSetting("DeviceNodePaths", "i=85|Objects" _ $Char(10) _ "i=2253|NoColumns")
    do $$$AssertEquals($$$ISOK(tSC), 1, "device list re-applied to force a re-resolve")
    Quit:$$$ISERR(tSC)

    do ..WaitFor("t.RowCount() > "_tBaseline_" && t.LoggedWarningMatching(""NoColumns"", ""SA1"")")

    // The NoColumns device resolves none of the schema's columns, and must not
    // prevent the other device from collecting.
    do $$$AssertEquals((..RowCount() > tBaseline), 1, "rows still accumulating despite an unresolved device")
    do $$$AssertEquals(..HasNonNull("SA1"), 1, "resolved columns still populated")
    do $$$AssertEquals(..LoggedWarningMatching("NoColumns", "SA1"), 1, "unresolved column warns on re-resolve")

    // No refuse-to-collect path exists any more; an unresolved column is not an error.
    do $$$AssertEquals(..LoggedErrorMatching("did not resolve"), 0, "no error logged for an unresolved column")
}

/// Deploying must not start collecting.
///
/// A deploy is a configuration write: the operator may want to look the pipeline
/// over, check the device list, or wait for a maintenance window before it touches
/// a live server. So POST /deploy adds the item switched off and starts nothing,
/// and going live is a separate explicit act (POST /pipelines/toggle).
///
/// It asserts only what deploy itself did, and reads row counts from its own
/// table. It uses the Test2 pipeline, still collecting, as its clock.
Method Test5DeployDoesNotAutostart()
{
    set pURL = ..URL()
    set tSC = ..BuildSchema(..#DeploySchemaClass, "TmpDeploySchema")
    do $$$AssertEquals($$$ISOK(tSC), 1, "second schema compiles")
    Quit:$$$ISERR(tSC)

    set tBody = {}
    do tBody.%Set("schemaClass", ..#DeploySchemaClass)
    do tBody.%Set("dataSourceName", ..#DeployItemName)
    do tBody.%Set("devices", "i=85|Objects")
    do tBody.%Set("mode", "polling")
    do tBody.%Set("callInterval", 2)
    do tBody.%Set("url", pURL)

    set tCycleBase = ..RowCount()
    set tSC = ##class(OPCUA.REST.DeployService).Deploy(tBody, .tRes)
    do $$$AssertEquals($$$ISOK(tSC), 1, "deploy succeeds")
    if $$$ISERR(tSC) {
        do $$$LogMessage($System.Status.GetOneErrorText(tSC))
        quit
    }

    do $$$AssertEquals(+tRes.%Get("started"), 0, "deploy reports it did not start")
    do $$$AssertEquals(..ItemEnabled(..#DeployItemName), 0, "config item was created disabled")

    // The substantive assertion: leave it alone for several poll intervals and
    // nothing should have been read or written. `started: 0` alone would not prove
    // that — it is a field in a response, not evidence about the server.
    //
    // This deliberately stops here. That an *enabled* item collects is what tests
    // 2-4 already establish; asserting the start half again would only re-test them,
    // and doing it in-process depends on production run state this test does not
    // own. Starting via POST /pipelines/toggle is verified against the running
    // instance instead.
    //
    // "Nothing happened" cannot be polled for, so the window is measured in poll
    // cycles instead of seconds: the Test2 pipeline, polling every 2 s in the same
    // production, must write three more cycles (two rows each) first.
    do ..WaitFor("t.RowCount() >= "_(tCycleBase + 6))
    do $$$AssertEquals(..RowCountFor(..#DeploySchemaClass), 0, "no rows collected before it is started")
}

/// Enabling a pipeline while another production holds the namespace is refused,
/// and that production keeps running. It used to be force-stopped.
///
/// Uses the disabled item test 5 deployed, and a throwaway empty production as
/// the "other" one, so nothing outside this suite is touched.
Method Test6OtherProductionNotStopped()
{
    set tOther = ..#OtherProductionClass
    // Starting a production records it as the namespace's last production, which
    // then names the default for config item lookups (FindItemByConfigName). Put
    // the previous one back, or that default outlives the deleted class.
    set tLastProduction = $Get(^Ens.Configuration("csp", "LastProduction"))
    Try {
        set tSC = ##class(Ens.Director).StopProduction(10, 1)
        do $$$AssertEquals($$$ISOK(tSC), 1, "pipeline production stops")
        Quit:$$$ISERR(tSC)

        set tSC = ..BuildOtherProduction()
        do $$$AssertEquals($$$ISOK(tSC), 1, "other production compiles")
        Quit:$$$ISERR(tSC)
        set tSC = ##class(Ens.Director).StartProduction(tOther)
        do $$$AssertEquals($$$ISOK(tSC), 1, "other production starts")
        Quit:$$$ISERR(tSC)

        set tSC = ##class(OPCUA.REST.PipelineService).Toggle({"name": (..#DeployItemName)}, .tRes)
        do $$$AssertEquals($$$ISERR(tSC), 1, "enable is refused")
        do $$$AssertEquals($System.Status.GetOneErrorText(tSC) [ tOther, 1, "refusal names the other production")
        do $$$AssertEquals(..ItemEnabled(..#DeployItemName), 0, "refused pipeline stays disabled")

        set tSC = ##class(OPCUA.REST.DeployService).StartOrUpdateProduction()
        do $$$AssertEquals($$$ISERR(tSC), 1, "StartOrUpdateProduction is refused")

        do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
        do $$$AssertEquals((tRunning = tOther) && (tState = 1), 1, "other production is still running")
    } Catch (e) {
        do $$$AssertFailure("exception: "_e.DisplayString())
    }

    do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
    if tRunning = tOther do ##class(Ens.Director).StopProduction(10, 1)
    if ##class(%Dictionary.ClassDefinition).%ExistsId(tOther) do $System.OBJ.Delete(tOther, "-d")
    if tLastProduction '= "" set ^Ens.Configuration("csp", "LastProduction") = tLastProduction
}

/// Start the pipeline production again if it was running before the suite, or
/// stop it if the suite started it.
ClassMethod RestoreProduction(pWasRunning As %Boolean) [ Private ]
{
    do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
    set tIsRunning = (tRunning = ..#ProductionClass) && (tState = 1)
    if pWasRunning && 'tIsRunning {
        do ##class(Ens.Director).StartProduction(..#ProductionClass)
    } elseif 'pWasRunning && tIsRunning {
        do ##class(Ens.Director).StopProduction(10, 1)
    }
}

// ==================== fixtures ====================
/// A schema whose columns match nodes the plc mock server exposes, written the
/// way a developer would by hand rather than via the wizard.
ClassMethod BuildSchema(pClassName As %String = {..#SchemaClass}, pDSName As %String = "TmpPortalSchema") As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        set tDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
        set tDef.Description = "Throwaway hand-authored schema for OPCUA.Tests.PortalPipelineTest."
        set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

        set tParam = ##class(%Dictionary.ParameterDefinition).%New()
        set tParam.Name = "OPCUADATASOURCE"
        set tParam.Default = pDSName
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
        for tName = "SA1", "SA2", "VT5" {
            set tProp = ##class(%Dictionary.PropertyDefinition).%New()
            set tProp.Name = tName
            set tProp.Type = "%Integer"
            do tProp.Parameters.SetAt(tName, "OPCUANODENAME")
            do tDef.Properties.Insert(tProp)
        }

        set tSC = tDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(pClassName, "ck-d")
        $$$ThrowOnError(tSC)

        // Start from an empty table. Cleanup kills the extent, but a global orphaned
        // by an interrupted run would otherwise make row-count assertions read the
        // previous run's data.
        Try { do $classmethod(pClassName, "%KillExtent") } Catch (eKill) {}
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Create the shared production if this is a virgin instance. A Portal user
/// would already have one, or create it from the Production wizard.
ClassMethod EnsureProduction() As %Status [ Private ]
{
    if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) Quit $$$OK

    #dim tSC As %Status = $$$OK
    Try {
        set tClassDef = ##class(%Dictionary.ClassDefinition).%New(..#ProductionClass)
        set tClassDef.Description = "Shared OPC UA pipeline production."
        set tClassDef.Super = "Ens.Production"

        set tXData = ##class(%Dictionary.XDataDefinition).%New()
        set tXData.Name = "ProductionDefinition"
        do tXData.Data.Write("<Production Name="""_..#ProductionClass_""" LogGeneralTraceEvents=""false"">")
        do tXData.Data.Write("<Description>OPC UA Data Pipelines</Description>")
        do tXData.Data.Write("<ActorPoolSize>2</ActorPoolSize>")
        do tXData.Data.Write("</Production>")
        do tClassDef.XDatas.Insert(tXData)

        set tSC = tClassDef.%Save()
        $$$ThrowOnError(tSC)
        set tSC = $System.OBJ.Compile(..#ProductionClass, "ck-d")
        $$$ThrowOnError(tSC)
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// An empty production for <method>Test6OtherProductionNotStopped</method>.
ClassMethod BuildOtherProduction() As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        // A leftover from an interrupted run would make %Save fail
        if ##class(%Dictionary.ClassDefinition).%ExistsId(..#OtherProductionClass) {
            $$$ThrowOnError($System.OBJ.Delete(..#OtherProductionClass, "-d"))
        }
        set tClassDef = ##class(%Dictionary.ClassDefinition).%New(..#OtherProductionClass)
        set tClassDef.Super = "Ens.Production"
        set tXData = ##class(%Dictionary.XDataDefinition).%New()
        set tXData.Name = "ProductionDefinition"
        do tXData.Data.Write("<Production Name="""_..#OtherProductionClass_"""></Production>")
        do tClassDef.XDatas.Insert(tXData)
        $$$ThrowOnError(tClassDef.%Save())
        $$$ThrowOnError($System.OBJ.Compile(..#OtherProductionClass, "ck-d"))
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Add the service item exactly as the Production Configuration page would.
ClassMethod AddItem(pURL As %String, pDevices As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
        if '$IsObject(tProd) {
            set tSC = $$$ERROR($$$GeneralError, "Cannot open "_..#ProductionClass)
            Quit
        }

        set tItem = ##class(Ens.Config.Item).%New()
        set tItem.Name = ..#ItemName
        set tItem.ClassName = "OPCUA.Service.TCPPollingRowSourceService"
        set tItem.PoolSize = 1
        set tItem.Enabled = 1
        set tItem.LogTraceEvents = 0

        do ..InsertSetting(tItem, "DataSourceClass", ..#SchemaClass)
        do ..InsertSetting(tItem, "DeviceNodePaths", pDevices)
        do ..InsertSetting(tItem, "URL", pURL)
        do ..InsertSetting(tItem, "CallInterval", 2)

        do tProd.Items.Insert(tItem)
        set tSC = tProd.%Save()
        $$$ThrowOnError(tSC)
        set tSC = tProd.SaveToClass()
        $$$ThrowOnError(tSC)

        set tSC = ##class(OPCUA.REST.DeployService).StartOrUpdateProduction()
        $$$ThrowOnError(tSC)
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

ClassMethod InsertSetting(pItem As Ens.Config.Item, pName As %String, pValue As %String) [ Private ]
{
    set tS = ##class(Ens.Config.Setting).%New()
    set tS.Target = "Adapter"
    set tS.Name = pName
    set tS.Value = pValue
    do pItem.Settings.Insert(tS)
}

/// Change one setting on the item and apply it, as a Portal edit would.
ClassMethod SetSetting(pName As %String, pValue As %String) As %Status [ Private ]
{
    #dim tSC As %Status = $$$OK
    Try {
        set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
        if '$IsObject(tProd) {
            set tSC = $$$ERROR($$$GeneralError, "Cannot open production")
            Quit
        }

        set tFound = 0
        for i=1:1:tProd.Items.Count() {
            set tItem = tProd.Items.GetAt(i)
            continue:tItem.Name'=..#ItemName
            for j=1:1:tItem.Settings.Count() {
                set tS = tItem.Settings.GetAt(j)
                continue:tS.Name'=pName
                set tS.Value = pValue
                set tFound = 1
            }
            if 'tFound {
                do ..InsertSetting(tItem, pName, pValue)
                set tFound = 1
            }
        }
        if 'tFound {
            set tSC = $$$ERROR($$$GeneralError, "Config item "_..#ItemName_" not found")
            Quit
        }

        set tSC = tProd.%Save()
        $$$ThrowOnError(tSC)
        set tSC = tProd.SaveToClass()
        $$$ThrowOnError(tSC)

        do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
        if (tRunning = ..#ProductionClass) && (tState = 1) {
            set tSC = ##class(Ens.Director).UpdateProduction()
            $$$ThrowOnError(tSC)
        }
    } Catch (e) {
        set tSC = e.AsStatus()
    }
    Quit tSC
}

ClassMethod RowCount() As %Integer
{
    Quit ..RowCountFor(..#SchemaClass)
}

ClassMethod RowCountFor(pSchemaClass As %String) As %Integer [ Private ]
{
    set tCount = 0
    Try {
        set tTable = ##class(OPCUA.REST.SchemaService).TableName(pSchemaClass)
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_tTable)
        if $IsObject(tRS) && tRS.%Next() set tCount = tRS.%GetData(1)
    } Catch (e) {}
    Quit tCount
}

/// The Enabled flag on a config item, or "" if there is no such item.
ClassMethod ItemEnabled(pItemName As %String) As %String [ Private ]
{
    set tEnabled = ""
    Try {
        set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
        Quit:'$IsObject(tProd)
        for i=1:1:tProd.Items.Count() {
            set tItem = tProd.Items.GetAt(i)
            if tItem.Name = pItemName set tEnabled = +tItem.Enabled  quit
        }
    } Catch (e) {}
    Quit tEnabled
}

ClassMethod HasNodePath(pPath As %String) As %Boolean
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE NodePath = ?", pPath)
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

ClassMethod HasNonNull(pColumn As %String) As %Boolean
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE "_pColumn_" IS NOT NULL")
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

ClassMethod HasNullColumn(pPath As %String, pColumn As %String) As %Boolean
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE NodePath = ? AND "_pColumn_" IS NULL", pPath)
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

/// Is there a warning naming both this device and this column?
ClassMethod LoggedWarningMatching(pDevice As %String, pColumn As %String) As %Boolean
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 3 ORDER BY ID DESC", ..#ItemName)
        while $IsObject(tRS) && tRS.%Next() {
            set tText = tRS.%GetData(1)
            if (tText [ pDevice) && (tText [ pColumn) set tFound = 1 quit
        }
    } Catch (e) {}
    Quit tFound
}

ClassMethod LoggedErrorMatching(pNeedle As %String) As %Boolean [ Private ]
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ConfigName = ? AND Type = 2 ORDER BY ID DESC", ..#ItemName)
        while $IsObject(tRS) && tRS.%Next() {
            if tRS.%GetData(1) [ pNeedle set tFound = 1 quit
        }
    } Catch (e) {}
    Quit tFound
}

/// Compile timestamp, used to prove no recompile happened.
ClassMethod CompileStamp() As %String [ Private ]
{
    set tStamp = ""
    Try {
        set tCD = ##class(%Dictionary.CompiledClass).%OpenId(..#SchemaClass)
        if $IsObject(tCD) set tStamp = tCD.TimeChanged
    } Catch (e) {}
    Quit tStamp
}

ClassMethod TableName() As %String [ CodeMode = expression, Private ]
{
##class(OPCUA.REST.SchemaService).TableName(..#SchemaClass)
}

/// Drop this item's log entries so the assertions see only fresh ones.
ClassMethod ClearLog() [ Private ]
{
    do ..ClearLogFor(..#ItemName)
}

ClassMethod ClearLogFor(pItemName As %String) [ Private ]
{
    Try {
        do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Ens_Util.Log WHERE ConfigName = ?", pItemName)
    } Catch (e) {}
}

// ==================== teardown ====================
/// Remove both config items and both schemas, leaving the instance as found.
ClassMethod Cleanup() [ Private ]
{
    Try {
        if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
            set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
            if $IsObject(tProd) {
                // Descending, so removing one index does not shift the next.
                // Collect IDs before removing, so we can delete the config item rows.
                kill tItemIds
                set tRemoved = 0
                for i=tProd.Items.Count():-1:1 {
                    set tItem = tProd.Items.GetAt(i)
                    set tNm = tItem.Name
                    continue:(tNm'=..#ItemName)&&(tNm'=..#DeployItemName)
                    set tItemIds(i) = tItem.%Id()
                    do tProd.Items.RemoveAt(i)
                    set tRemoved = 1
                }
                if tRemoved {
                    do tProd.%Save()
                    do tProd.SaveToClass()
                    // Delete the config item rows
                    set i = ""
                    for {
                        set i = $Order(tItemIds(i))
                        Quit:i=""
                        Try { do ##class(Ens.Config.Item).%DeleteId(tItemIds(i)) } Catch (eDel) {}
                    }
                    do ##class(Ens.Director).GetProductionStatus(.tRunning, .tState)
                    if (tRunning = ..#ProductionClass) && (tState = 1) {
                        do ##class(Ens.Director).UpdateProduction()
                    }
                }
            }
        }
    } Catch (e) {}

    Try {
        do ..ClearLog()
        do ..ClearLogFor(..#DeployItemName)
        for tCls = ..#SchemaClass, ..#DeploySchemaClass {
            // Drop the rows before the class. Deleting a %Persistent class leaves
            // its data global behind, and a stale table would let "no rows
            // collected" pass or fail on the previous run's leftovers rather than
            // on this one.
            Try {
                if ##class(%Dictionary.CompiledClass).%ExistsId(tCls) {
                    do $classmethod(tCls, "%KillExtent")
                }
            } Catch (eKill) {}
            if ##class(%Dictionary.ClassDefinition).%ExistsId(tCls) {
                do $System.OBJ.Delete(tCls, "-d")
            }
            kill ^OPCUA.DataSource(tCls)
        }
    } Catch (e) {}
}

}
