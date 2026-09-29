Include (OPCUA.Constants, %occInclude, Ensemble)

/// Proves a working row-source pipeline can be built with NO webapp and NO
/// /deploy call — only a schema class and ordinary IRIS production configuration
/// (PRD §10 acceptance criteria 3-6).
///
/// Run against the docker-compose mock server:
///   zn "OPCUA"
///   write ##class(OPCUA.Tests.PortalPipelineTest).Run("opc.tcp://plc")
///
/// What it exercises, in the order a Portal user would:
///   1. a hand-authored schema class appears in the DataSourceClass dropdown
///   2. adding a config item + typing device nodepaths yields a running pipeline
///   3. adding a device is a one-line setting edit with no recompile
///   4. a device missing a column stores NULL and logs a warning naming both
///   5. an unresolved column never stops the pipeline
///   6. POST /deploy creates the pipeline stopped and collects nothing until started
Class OPCUA.Tests.PortalPipelineTest
{

Parameter SchemaClass = "OPCUA.Tests.TmpPortalSchema";

Parameter ItemName = "ZZPortalPipelineTest";

/// A second schema + item, used only by TestDeployDoesNotAutostart. Separate from
/// the pair above because that pipeline is deliberately left collecting by tests
/// 2-4, and "no rows yet" can only be asserted on a table nothing else writes to.
Parameter DeploySchemaClass = "OPCUA.Tests.TmpDeploySchema";

Parameter DeployItemName = "ZZPortalDeployTest";

Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Run the whole suite. Returns 1 if every check passed.
ClassMethod Run(pURL As %String = "opc.tcp://plc") As %Boolean
{
    set tPass = 0, tFail = 0

    Try {
        do ..Cleanup()

        write !, "=== 1. hand-authored schema is dropdown-discoverable ===", !
        do ..TestSchemaDiscoverable(.tPass, .tFail)

        write !, "=== 2. pipeline built from configuration alone ===", !
        do ..TestPortalBuild(pURL, .tPass, .tFail)

        write !, "=== 3. adding a device needs no recompile ===", !
        do ..TestAddDevice(.tPass, .tFail)

        write !, "=== 4. an unresolved column does not stop collection ===", !
        do ..TestPartialDeviceKeepsCollecting(.tPass, .tFail)

        write !, "=== 5. deploy creates the pipeline stopped ===", !
        do ..TestDeployDoesNotAutostart(pURL, .tPass, .tFail)

    } Catch (e) {
        set tFail = tFail + 1
        write "  FAIL exception: ", e.DisplayString(), !
    }

    do ..Cleanup()

    write !, "-----------------------------------------", !
    write "passed: ", tPass, "   failed: ", tFail, !
    quit (tFail = 0)
}

ClassMethod Check(pLabel As %String, pGot, pWant, ByRef pPass, ByRef pFail) [ Private ]
{
    if pGot = pWant {
        set pPass = pPass + 1
        write "  ok   ", pLabel, !
    } else {
        set pFail = pFail + 1
        write "  FAIL ", pLabel, " — got [", pGot, "] want [", pWant, "]", !
    }
}

/// A schema class written by hand (no wizard) must show up in the dropdown that
/// backs the DataSourceClass setting.
ClassMethod TestSchemaDiscoverable(ByRef pPass, ByRef pFail) [ Private ]
{
    set tSC = ..BuildSchema()
    do ..Check("hand-authored schema compiles", $$$ISOK(tSC), 1, .pPass, .pFail)
    if $$$ISERR(tSC) {
        write "       ", $System.Status.GetOneErrorText(tSC), !
        quit
    }

    // Exactly what the Portal's selector does for this setting.
    kill tParms, tResults
    set tParms("class") = "OPCUA.DataSource.DeviceSchema"
    set tSC = ##class(Ens.ContextSearch).SubclassOf(.tCaption, .tTop, .tResults, .tParms)
    do ..Check("SubclassOf succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)

    set tFound = 0, tSawAbstract = 0, i = ""
    for {
        set i = $Order(tResults(i))
        quit:i=""
        if tResults(i) = ..#SchemaClass set tFound = 1
        if tResults(i) = "OPCUA.DataSource.DeviceSchema" set tSawAbstract = 1
    }
    do ..Check("schema appears in the dropdown", tFound, 1, .pPass, .pFail)
    do ..Check("abstract base is excluded", tSawAbstract, 0, .pPass, .pFail)

    // The setting must actually carry the selector url through to the Portal.
    kill tSettings
    do ##class(OPCUA.Adapter.TCPPollingInboundAdapter).GetSettings(.tSettings)
    set tCat = $Get(tSettings(":", "DataSourceClass"))
    set tUrl = $Get(tSettings(tCat, "DataSourceClass"))
    do ..Check("DataSourceClass renders as a selector", (tUrl [ "selector?context="), 1, .pPass, .pFail)
    do ..Check("selector filters on DeviceSchema", (tUrl [ "OPCUA.DataSource.DeviceSchema"), 1, .pPass, .pFail)
    do ..Check("DeviceNodePaths is a registered setting", ''$Data(tSettings(":", "DeviceNodePaths")), 1, .pPass, .pFail)
}

/// Build the pipeline using only the Ens.Config API the Portal drives, then
/// confirm it actually collects rows.
ClassMethod TestPortalBuild(pURL As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    set tSC = ..EnsureProduction()
    do ..Check("shared production exists", $$$ISOK(tSC), 1, .pPass, .pFail)
    Quit:$$$ISERR(tSC)

    // "Add a business service item", fill in settings, start.
    set tSC = ..AddItem(pURL, "i=85|Objects")
    do ..Check("config item added and production started", $$$ISOK(tSC), 1, .pPass, .pFail)
    if $$$ISERR(tSC) {
        write "       ", $System.Status.GetOneErrorText(tSC), !
        quit
    }

    do ..Settle(12)

    do ..Check("pipeline collected rows", (..RowCount() > 0), 1, .pPass, .pFail)
    do ..Check("NodePath is tagged from the device label", ..HasNodePath("Objects"), 1, .pPass, .pFail)
    do ..Check("values are populated", ..HasNonNull("SA1"), 1, .pPass, .pFail)

    // The whole point: no device metadata global is involved.
    do ..Check("no ^OPCUA.RowSource entry was written", $Data(^OPCUA.RowSource(..#SchemaClass)), 0, .pPass, .pFail)
}

/// Adding a device must be a one-line setting edit: no regeneration, no recompile.
ClassMethod TestAddDevice(ByRef pPass, ByRef pFail) [ Private ]
{
    set tBefore = ..CompileStamp()

    // Second device deliberately has none of the schema's columns, which also
    // exercises the store-NULL-and-warn path.
    set tSC = ..SetSetting("DeviceNodePaths", "i=85|Objects" _ $Char(10) _ "# commented out" _ $Char(10) _ "i=2253|NoColumns")
    do ..Check("device list edited and applied", $$$ISOK(tSC), 1, .pPass, .pFail)
    Quit:$$$ISERR(tSC)

    do ..Settle(12)

    do ..Check("schema class was NOT recompiled", ..CompileStamp(), tBefore, .pPass, .pFail)
    do ..Check("original device still reporting", ..HasNodePath("Objects"), 1, .pPass, .pFail)
    do ..Check("added device is reporting", ..HasNodePath("NoColumns"), 1, .pPass, .pFail)
    do ..Check("commented-out device ignored", ..HasNodePath("commented out"), 0, .pPass, .pFail)

    // A device missing a column stores NULL for it and says so in the event log,
    // naming the device and the column.
    do ..Check("missing column stored as NULL", ..HasNullColumn("NoColumns", "SA1"), 1, .pPass, .pFail)
    do ..Check("warning names the device and column", ..LoggedWarningMatching("NoColumns", "SA1"), 1, .pPass, .pFail)
}

/// An unresolved column must never stop the pipeline.
///
/// Coverage is reported before deploy (POST /schemas/:name/validate), so binding
/// a partially matching device is a deliberate choice. Store NULL, warn, and keep
/// collecting everything that did resolve — a device with one missing node must
/// not cost the operator the other nine.
ClassMethod TestPartialDeviceKeepsCollecting(ByRef pPass, ByRef pFail) [ Private ]
{
    do ..ClearLog()
    set tBaseline = ..RowCount()

    // Resolution diagnostics are emitted on connect, not per poll cycle, so an
    // empty log alone would prove nothing. Rewriting the device list forces the
    // item to restart and re-resolve, which is what generates fresh entries.
    set tSC = ..SetSetting("DeviceNodePaths", "i=85|Objects" _ $Char(10) _ "i=2253|NoColumns")
    do ..Check("device list re-applied to force a re-resolve", $$$ISOK(tSC), 1, .pPass, .pFail)
    Quit:$$$ISERR(tSC)

    do ..Settle(12)

    // The NoColumns device resolves none of the schema's columns, and must not
    // prevent the other device from collecting.
    do ..Check("rows still accumulating despite an unresolved device", (..RowCount() > tBaseline), 1, .pPass, .pFail)
    do ..Check("resolved columns still populated", ..HasNonNull("SA1"), 1, .pPass, .pFail)
    do ..Check("unresolved column warns on re-resolve", ..LoggedWarningMatching("NoColumns", "SA1"), 1, .pPass, .pFail)

    // No refuse-to-collect path exists any more; an unresolved column is not an error.
    do ..Check("no error logged for an unresolved column", ..LoggedErrorMatching("did not resolve"), 0, .pPass, .pFail)
}

/// Deploying must not start collecting.
///
/// A deploy is a configuration write: the operator may want to look the pipeline
/// over, check the device list, or wait for a maintenance window before it touches
/// a live server. So POST /deploy adds the item switched off and starts nothing,
/// and going live is a separate explicit act (POST /pipelines/toggle).
///
/// Order-independent: it asserts only what deploy itself did, and reads row counts
/// from its own table, so it does not care whether a production is running.
ClassMethod TestDeployDoesNotAutostart(pURL As %String, ByRef pPass, ByRef pFail) [ Private ]
{
    set tSC = ..BuildSchema(..#DeploySchemaClass, "TmpDeploySchema")
    do ..Check("second schema compiles", $$$ISOK(tSC), 1, .pPass, .pFail)
    Quit:$$$ISERR(tSC)

    set tBody = {}
    do tBody.%Set("schemaClass", ..#DeploySchemaClass)
    do tBody.%Set("dataSourceName", ..#DeployItemName)
    do tBody.%Set("devices", "i=85|Objects")
    do tBody.%Set("mode", "polling")
    do tBody.%Set("callInterval", 2)
    do tBody.%Set("url", pURL)

    set tSC = ##class(OPCUA.REST.DeployService).Deploy(tBody, .tRes)
    do ..Check("deploy succeeds", $$$ISOK(tSC), 1, .pPass, .pFail)
    if $$$ISERR(tSC) {
        write "       ", $System.Status.GetOneErrorText(tSC), !
        quit
    }

    do ..Check("deploy reports it did not start", +tRes.%Get("started"), 0, .pPass, .pFail)
    do ..Check("config item was created disabled", ..ItemEnabled(..#DeployItemName), 0, .pPass, .pFail)

    // The substantive assertion: leave it alone for several poll intervals and
    // nothing should have been read or written. `started: 0` alone would not prove
    // that — it is a field in a response, not evidence about the server.
    //
    // This deliberately stops here. That an *enabled* item collects is what tests
    // 2-4 already establish; asserting the start half again would only re-test them,
    // and doing it in-process depends on production run state this test does not
    // own. Starting via POST /pipelines/toggle is verified against the running
    // instance instead.
    do ..Settle(8)
    do ..Check("no rows collected before it is started", ..RowCountFor(..#DeploySchemaClass), 0, .pPass, .pFail)
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

// ==================== assertions ====================

/// Let the pipeline run for a few poll cycles.
ClassMethod Settle(pSeconds As %Integer) [ Private ]
{
    hang pSeconds
}

ClassMethod RowCount() As %Integer [ Private ]
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

ClassMethod HasNodePath(pPath As %String) As %Boolean [ Private ]
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE NodePath = ?", pPath)
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

ClassMethod HasNonNull(pColumn As %String) As %Boolean [ Private ]
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE "_pColumn_" IS NOT NULL")
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

ClassMethod HasNullColumn(pPath As %String, pColumn As %String) As %Boolean [ Private ]
{
    set tFound = 0
    Try {
        set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_..TableName()_" WHERE NodePath = ? AND "_pColumn_" IS NULL", pPath)
        if $IsObject(tRS) && tRS.%Next() set tFound = (tRS.%GetData(1) > 0)
    } Catch (e) {}
    Quit tFound
}

/// Is there a warning naming both this device and this column?
ClassMethod LoggedWarningMatching(pDevice As %String, pColumn As %String) As %Boolean [ Private ]
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
                set tRemoved = 0
                for i=tProd.Items.Count():-1:1 {
                    set tNm = tProd.Items.GetAt(i).Name
                    continue:(tNm'=..#ItemName)&&(tNm'=..#DeployItemName)
                    do tProd.Items.RemoveAt(i)
                    set tRemoved = 1
                }
                if tRemoved {
                    do tProd.%Save()
                    do tProd.SaveToClass()
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
