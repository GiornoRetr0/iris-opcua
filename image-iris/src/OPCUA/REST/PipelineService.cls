Include (%occInclude, Ensemble)

/// Manage deployed OPC UA pipelines: list, toggle, delete.
/// Reads from the shared production (OPCUA.Pipeline.Production).
Class OPCUA.REST.PipelineService
{

/// The shared production class.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// List all pipeline service items with their runtime status.
ClassMethod List(pBody As %DynamicObject, Output pResult As %DynamicArray) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = []
	Try {
		if '##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) Quit

		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if '$IsObject(tProd) Quit

		do ##class(Ens.Director).GetProductionStatus(.tRunningProd, .tProdState)
		set tProdRunning = (tRunningProd = ..#ProductionClass) && (tProdState = 1)

		for i=1:1:tProd.Items.Count() {
			set tCfgItem = tProd.Items.GetAt(i)

			set tItem = {}
			set tItem.name = tCfgItem.Name
			set tItem.className = tCfgItem.ClassName
			set tItem.enabled = tCfgItem.Enabled

			// Determine mode and pipeline version from service class
			if tItem.className = "OPCUA.Service.TCPSubscriptionRowSourceService" {
				set tItem.mode = "subscription"
				set tItem.pipelineVersion = 2
			} elseif tItem.className = "OPCUA.Service.TCPSubscriptionService" {
				set tItem.mode = "subscription"
				set tItem.pipelineVersion = 1
			} elseif tItem.className = "OPCUA.Service.TCPPollingRowSourceService" {
				set tItem.mode = "polling"
				set tItem.pipelineVersion = 2
			} else {
				set tItem.mode = "polling"
				set tItem.pipelineVersion = 1
			}

			// Read settings from config item
			set tItem.dataSourceClass = ..GetSettingValue(tCfgItem, "DataSourceClass")
			set tItem.serverUrl = ..GetSettingValue(tCfgItem, "URL")
			set tItem.callInterval = ..GetSettingValue(tCfgItem, "CallInterval")
			set tItem.publishingInterval = ..GetSettingValue(tCfgItem, "RequestedPublishingInterval")
			// The device list is now a plain setting, so surface it directly —
			// editing a pipeline's devices is editing this string.
			set tDeviceNodePaths = ..GetSettingValue(tCfgItem, "DeviceNodePaths")
			set tItem.deviceNodePaths = tDeviceNodePaths
			set tItem.strictSchemaMatch = +..GetSettingValue(tCfgItem, "StrictSchemaMatch")

			// Derive table name from DataSource class
			if tItem.dataSourceClass '= "" {
				set tPkg = $Piece(tItem.dataSourceClass, ".", 1, *-1)
				set tShort = $Piece(tItem.dataSourceClass, ".", *)
				set tItem.tableName = $Select(tPkg="":tShort, 1:$Replace(tPkg, ".", "_")_"."_tShort)
			}

			if tProdRunning {
				set tItem.running = ##class(Ens.Director).IsItemEnabled(tItem.name, .tSCStatus)
				set tItem.rowCount = ..GetRowCount(tItem.dataSourceClass)
			} else {
				set tItem.running = 0
				set tItem.rowCount = 0
			}

			// Enabled is not the same as collecting: a service whose adapter fails
			// to connect or resolve stays enabled and keeps retrying while writing
			// nothing. Surface the adapter's own verdict so the UI can tell the two
			// apart — this is what "started but silently collecting nothing" looked
			// like before.
			do ..GetHealth(tItem.name, tProdRunning, tCfgItem.Enabled, .tHealth, .tLastActivity)
			set tItem.health = tHealth
			set tItem.lastActivity = tLastActivity

			set tItem.productionRunning = tProdRunning
			set tItem.nodes = ..GetNodeNames(tItem.dataSourceClass)

			if tItem.pipelineVersion = 2 {
				set tItem.rowSources = ..GetRowSourceInfo(tItem.dataSourceClass, tDeviceNodePaths)
			}

			do pResult.%Push(tItem)
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Get a setting value from a config item by name.
ClassMethod GetSettingValue(pItem As Ens.Config.Item, pName As %String) As %String [ Private ]
{
	set tValue = ""
	for i=1:1:pItem.Settings.Count() {
		set tSetting = pItem.Settings.GetAt(i)
		if tSetting.Name = pName {
			set tValue = tSetting.Value
			Quit
		}
	}
	Quit tValue
}

/// Classify a pipeline's real collection health, and report when it last did
/// any work.
///
/// The adapters already publish "OK" or "Error" per poll cycle via
/// $$$SetHostMonitor; this reads that verdict back rather than inferring health
/// from config, so a pipeline that is enabled but failing to connect, resolve,
/// or read is reported as such.
///
/// pHealth is one of:
/// <ul>
/// <li><tt>stopped</tt> — the production is not running</li>
/// <li><tt>disabled</tt> — the config item is switched off</li>
/// <li><tt>error</tt> — running and retrying, but not collecting</li>
/// <li><tt>ok</tt> — collecting normally</li>
/// <li><tt>starting</tt> — enabled, but has not reported a cycle yet</li>
/// </ul>
ClassMethod GetHealth(pItemName As %String, pProdRunning As %Boolean, pEnabled As %Boolean, Output pHealth As %String, Output pLastActivity As %String) [ Private ]
{
	set pHealth = "ok"
	set pLastActivity = ""

	if 'pProdRunning {
		set pHealth = "stopped"
		Quit
	}
	if 'pEnabled {
		set pHealth = "disabled"
		Quit
	}

	Try {
		set tStatus = $$$GetHostMonitor(pItemName, $$$eMonitorStatus)
		set pLastActivity = $$$GetHostMonitor(pItemName, $$$eMonitorLastActivity)

		// No entry yet means the job exists but hasn't completed a cycle. Calling
		// that "ok" would claim success that hasn't happened.
		if tStatus = "" {
			set pHealth = "starting"
		} elseif tStatus = "OK" {
			set pHealth = "ok"
		} else {
			set pHealth = "error"
		}
	} Catch (e) {
		// An unreadable monitor is not evidence of failure; leave it as-is.
	}
}

/// Get row count for a DataSource table.
ClassMethod GetRowCount(pClassName As %String) As %Integer [ Private ]
{
	set tCount = 0
	Try {
		if pClassName = "" Quit
		if '##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) Quit
		// SQL schema.table: package becomes schema, last part becomes table
		set tPkg = $Piece(pClassName, ".", 1, *-1)
		set tCls = $Piece(pClassName, ".", *)
		set tSchema = $Select(tPkg="":"SQLUser", 1:$Replace(tPkg, ".", "_"))
		set tTable = tSchema_"."_tCls
		set tRS = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM "_tTable)
		if $IsObject(tRS) && tRS.%Next() set tCount = tRS.%GetData(1)
	} Catch (e) {
		// Table might not exist or be empty
	}
	Quit tCount
}

/// Get the OPC UA node names from a DataSource class definition.
ClassMethod GetNodeNames(pClassName As %String) As %DynamicArray [ Private ]
{
	set tNodes = []
	Try {
		if pClassName = "" Quit
		// Use compiled class info (CompiledProperty) which has parameter access
		set tClassDef = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
		if '$IsObject(tClassDef) Quit
		for i=1:1:tClassDef.Properties.Count() {
			set tProp = tClassDef.Properties.GetAt(i)
			// Get OPCUANODENAME from property parameters
			set tNodeName = tProp.Parameters.GetAt("OPCUANODENAME")
			if tNodeName '= "" {
				set tNodeInfo = {}
				set tNodeInfo.property = tProp.Name
				set tNodeInfo.nodeId = tNodeName
				do tNodes.%Push(tNodeInfo)
			}
		}
	} Catch (e) {}
	Quit tNodes
}

/// Toggle a pipeline service item on/off using Ens.Config API.
ClassMethod Toggle(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	Try {
		set tName = pBody.%Get("name")
		if tName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing pipeline name")
			Quit
		}

		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if '$IsObject(tProd) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production")
			Quit
		}

		set tItem = tProd.FindItemByConfigName(tName, .tSC2)
		if '$IsObject(tItem) {
			set tSC = $$$ERROR($$$GeneralError, "Pipeline '"_tName_"' not found")
			Quit
		}

		set tNewState = 'tItem.Enabled
		set tItem.Enabled = tNewState

		set tSC = tProd.%Save()
		$$$ThrowOnError(tSC)
		set tSC = tProd.SaveToClass()
		$$$ThrowOnError(tSC)

		// Start production if not running, otherwise just update
		do ##class(Ens.Director).GetProductionStatus(.tRunning, .tRunState)
		if (tRunning = ..#ProductionClass) && (tRunState = 1) {
			set tSC = ##class(Ens.Director).UpdateProduction()
			$$$ThrowOnError(tSC)
		} elseif tNewState {
			// Production not running and we're enabling — start it
			set tSC = ##class(OPCUA.REST.DeployService).StartOrUpdateProduction()
			$$$ThrowOnError(tSC)
		}

		set pResult.name = tName
		set pResult.enabled = tNewState

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Delete a pipeline: remove service item from production, delete DataSource class.
ClassMethod Delete(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	Try {
		set tName = pBody.%Get("name")
		if tName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing pipeline name")
			Quit
		}

		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if '$IsObject(tProd) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production")
			Quit
		}

		// Find the item and get its DataSourceClass before removing
		set tDSClass = ""
		set tFoundIdx = 0
		for i=1:1:tProd.Items.Count() {
			set tCfgItem = tProd.Items.GetAt(i)
			if tCfgItem.Name = tName {
				set tDSClass = ..GetSettingValue(tCfgItem, "DataSourceClass")
				set tFoundIdx = i
				Quit
			}
		}
		if tFoundIdx = 0 {
			set tSC = $$$ERROR($$$GeneralError, "Pipeline '"_tName_"' not found in production")
			Quit
		}

		// If production is running, disable the item first
		do ##class(Ens.Director).GetProductionStatus(.tRunning, .tRunState2)
		set tProdRunning = (tRunning = ..#ProductionClass) && (tRunState2 = 1)
		if tProdRunning {
			if ##class(Ens.Director).IsItemEnabled(tName, .tSCCheck) {
				do ##class(Ens.Director).EnableConfigItem(tName, 0)
			}
		}

		// Remove from production and persist
		do tProd.Items.RemoveAt(tFoundIdx)
		set tSC = tProd.%Save()
		$$$ThrowOnError(tSC)
		set tSC = tProd.SaveToClass()
		$$$ThrowOnError(tSC)

		if tProdRunning {
			do ##class(Ens.Director).UpdateProduction()
		}

		// Delete DataSource class and serial subclasses
		if (tDSClass '= "") && ##class(%Dictionary.ClassDefinition).%ExistsId(tDSClass) {
			do ..DeleteSerialSubclasses(tDSClass)
			do $System.OBJ.Delete(tDSClass, "-d")
		}

		set pResult.deleted = 1
		set pResult.name = tName

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Edit (update) an existing v2 pipeline: stop service, regenerate DataSource class
/// with type preservation, update row source metadata, restart service.
ClassMethod Edit(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.updated = 0
	Try {
		// --- Validate inputs ---
		set tClassName = pBody.%Get("existingClassName")
		if tClassName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing existingClassName")
			Quit
		}

		if '##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
			set tSC = $$$ERROR($$$GeneralError, "Class '"_tClassName_"' does not exist")
			Quit
		}

		set tColumns = pBody.%Get("columns")
		set tRowSources = pBody.%Get("rowSources")
		if '$IsObject($Get(tColumns)) || (tColumns.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No columns defined")
			Quit
		}
		if '$IsObject($Get(tRowSources)) || (tRowSources.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No row sources defined")
			Quit
		}

		set tDataSourceName = pBody.%Get("dataSourceName")
		if tDataSourceName = "" set tDataSourceName = $Piece(tClassName, ".", *)

		set tMode = pBody.%Get("mode")
		if (tMode '= "polling") && (tMode '= "subscription") set tMode = "polling"

		// --- Step 1: Read existing column types before deleting ---
		kill tExistingTypes
		set tClassDef = ##class(%Dictionary.CompiledClass).%OpenId(tClassName)
		if $IsObject(tClassDef) {
			for i=1:1:tClassDef.Properties.Count() {
				set tProp = tClassDef.Properties.GetAt(i)
				if tProp.Name = "NodePath" continue
				if tProp.Name = "ServerTimeStamp" continue
				if tProp.Name = "SourceTimeStamp" continue
				if $Extract(tProp.Name, 1) = "%" continue
				set tExistingTypes(tProp.Name) = tProp.Type
			}
		}

		// --- Step 2: Stop the service item if running ---
		do ##class(Ens.Director).GetProductionStatus(.tRunningProd, .tProdState)
		set tProdRunning = (tRunningProd = ..#ProductionClass) && (tProdState = 1)
		if tProdRunning {
			if ##class(Ens.Director).IsItemEnabled(tDataSourceName, .tSCCheck) {
				do ##class(Ens.Director).EnableConfigItem(tDataSourceName, 0)
				do ##class(Ens.Director).UpdateProduction()
			}
		}

		// --- Step 3: Delete old class, serial subclasses, and spec ---
		do ..DeleteSerialSubclasses(tClassName)
		do $System.OBJ.Delete(tClassName, "-d")
		Kill ^OPCUA.DataSource(tClassName)

		// --- Step 4+5: Regenerate the schema class (serial classes compiled internally) ---
		set tSC = ##class(OPCUA.REST.DeployService).GenerateDataSourceTextV2(pBody, tColumns, tRowSources, tClassName, tDataSourceName, .tText, .tSerialClasses)
		Quit:$$$ISERR(tSC)

		// --- Step 6: Update the device list, which is now just a setting ---
		set tSC = ..UpdateDeviceNodePaths(tDataSourceName, ##class(OPCUA.REST.DeployService).BuildDeviceNodePaths(tRowSources))
		Quit:$$$ISERR(tSC)

		// --- Step 7: Re-enable and restart ---
		if tProdRunning {
			do ##class(Ens.Director).EnableConfigItem(tDataSourceName, 1)
			do ##class(Ens.Director).UpdateProduction()
		}

		set pResult.updated = 1
		set pResult.dataSourceClass = tClassName
		set pResult.tableName = ##class(OPCUA.REST.SchemaService).TableName(tClassName)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Write a config item's DeviceNodePaths setting, adding it if absent.
///
/// Rebinding a pipeline's devices is now a settings update rather than a class
/// regeneration — which is why editing a device list no longer needs a recompile.
ClassMethod UpdateDeviceNodePaths(pItemName As %String, pValue As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if '$IsObject(tProd) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production: "_..#ProductionClass)
			Quit
		}

		set tFound = 0
		for i=1:1:tProd.Items.Count() {
			set tItem = tProd.Items.GetAt(i)
			continue:tItem.Name'=pItemName

			set tSet = 0
			for j=1:1:tItem.Settings.Count() {
				set tSetting = tItem.Settings.GetAt(j)
				continue:tSetting.Name'="DeviceNodePaths"
				set tSetting.Value = pValue
				set tSet = 1
			}
			if 'tSet {
				set tSetting = ##class(Ens.Config.Setting).%New()
				set tSetting.Target = "Adapter"
				set tSetting.Name = "DeviceNodePaths"
				set tSetting.Value = pValue
				do tItem.Settings.Insert(tSetting)
			}
			set tFound = 1
		}

		if 'tFound {
			set tSC = $$$ERROR($$$GeneralError, "Pipeline '"_pItemName_"' not found in production")
			Quit
		}

		set tSC = tProd.%Save()
		$$$ThrowOnError(tSC)
		set tSC = tProd.SaveToClass()
		$$$ThrowOnError(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Describe a v2 pipeline's devices, from the DeviceNodePaths setting plus the
/// schema class — the two places that now hold the truth.
///
/// Every device is reported with the schema's full column list, because a
/// device's actual coverage is only known once it has been browsed at connect
/// time; use POST /schemas/:name/validate for real per-device coverage.
ClassMethod GetRowSourceInfo(pClassName As %String, pDeviceNodePaths As %String = "") As %DynamicArray [ Private ]
{
	set tResult = []
	Try {
		Quit:pDeviceNodePaths=""

		do ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(pDeviceNodePaths, .tDevices, .tErrors)
		Quit:$LL($Get(tDevices))=0

		// Schema columns, in the same storage order the runtime uses.
		set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(pClassName, .tColumns, .tFolders)
		if $$$ISERR(tSC) set tColumns = 0

		for i=1:1:$LL(tDevices) {
			set tDev = $LI(tDevices, i)
			set tInfo = {}
			set tInfo.path = $LI(tDev, 4)
			set tInfo.nodeNs = $LI(tDev, 1)
			set tInfo.nodeId = $LI(tDev, 2)
			set tInfo.nodeIdType = $LI(tDev, 3)

			set tChildren = []
			for c=1:1:tColumns {
				set tCol = tColumns(c)
				set tFolderName = $LI(tCol, 5)
				set tNodeName = $LI(tCol, 3)

				set tChild = {}
				set tChild.displayName = tNodeName
				set tChild.nodeNs = $LI(tCol, 2)
				// Nodes are resolved by name at connect time, so there is no
				// stored absolute node id to report here.
				set tChild.nodeId = ""
				set tChild.nodeIdType = ""

				set tRelPath = ##class(%DynamicArray).%New()
				if tFolderName '= "" do tRelPath.%Push(tFolderName)
				do tRelPath.%Push(tNodeName)
				set tChild.relativePath = tRelPath

				do tChildren.%Push(tChild)
			}
			set tInfo.childNodes = tChildren

			do tResult.%Push(tInfo)
		}
	} Catch (e) {}
	Quit tResult
}

/// Delete serial object subclasses for a DataSource class.
/// Scans the class's properties for types extending %SerialObject (excluding OPCUA.Types.*).
/// Also called by <class>OPCUA.REST.SchemaService</class> when deleting a schema.
ClassMethod DeleteSerialSubclasses(pClassName As %String)
{
	Try {
		set tClassDef = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
		if '$IsObject(tClassDef) Quit

		for i=1:1:tClassDef.Properties.Count() {
			set tProp = tClassDef.Properties.GetAt(i)
			set tType = tProp.Type
			// Skip OPCUA.Types.* (these are framework serial objects, not ours)
			if $Extract(tType, 1, 12) = "OPCUA.Types." continue
			// Skip standard types
			if $Extract(tType, 1) = "%" continue
			// Check if it extends %SerialObject
			Try {
				if $classmethod(tType, "%Extends", "%SerialObject") {
					// This is a pipeline-generated serial class — delete it
					if ##class(%Dictionary.ClassDefinition).%ExistsId(tType) {
						do $System.OBJ.Delete(tType, "-d")
					}
				}
			} Catch (eInner) {
				// Type class may not exist — skip
			}
		}
	} Catch (e) {}
}

}
