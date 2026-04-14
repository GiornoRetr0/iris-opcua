Include %occInclude

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

			set tItem.productionRunning = tProdRunning
			set tItem.nodes = ..GetNodeNames(tItem.dataSourceClass)

			if tItem.pipelineVersion = 2 {
				set tItem.rowSources = ..GetRowSourceInfo(tItem.dataSourceClass)
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

		// Clean up v2 row source metadata
		if tDSClass '= "" {
			Kill ^OPCUA.RowSource(tDSClass)
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

		// --- Step 3: Delete old class, serial subclasses, and metadata ---
		do ..DeleteSerialSubclasses(tClassName)
		do $System.OBJ.Delete(tClassName, "-d")
		Kill ^OPCUA.RowSource(tClassName)
		Kill ^OPCUA.DataSource(tClassName)

		// --- Step 4+5: Generate and compile new DataSource class (serial classes compiled internally) ---
		set tSC = ##class(OPCUA.REST.DeployService).GenerateDataSourceTextV2(pBody, tColumns, tRowSources, tClassName, tDataSourceName, .tText, .tSerialClasses)
		Quit:$$$ISERR(tSC)

		// --- Step 6: Update row source metadata ---
		set tSC = ##class(OPCUA.REST.DeployService).StoreRowSourceMetadata(tClassName, tRowSources, tColumns)
		Quit:$$$ISERR(tSC)

		// --- Step 7: Re-enable and restart ---
		if tProdRunning {
			do ##class(Ens.Director).EnableConfigItem(tDataSourceName, 1)
			do ##class(Ens.Director).UpdateProduction()
		}

		set pResult.updated = 1
		set pResult.dataSourceClass = tClassName
		set tPackage = $Piece(tClassName, ".", 1, *-1)
		set tShort = $Piece(tClassName, ".", *)
		set pResult.tableName = $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Get row source information for a v2 pipeline from ^OPCUA.RowSource global.
/// Returns path, nodeNs, nodeId, nodeIdType, and childNodes per row source.
/// childNodes are resolved by cross-referencing column masks with column names from the compiled class.
ClassMethod GetRowSourceInfo(pClassName As %String) As %DynamicArray [ Private ]
{
	set tResult = []
	Try {
		set tRSData = $Get(^OPCUA.RowSource(pClassName))
		if tRSData = "" Quit

		set tRSCount = $LI(tRSData, 1)
		set tColCount = $LI(tRSData, 2)
		set tRSList = $LI(tRSData, 3)

		// Get stored column paths if available (position 4)
		set tHasColumnPaths = ($LL(tRSData) >= 4) && ($LI(tRSData, 4) '= "")
		if tHasColumnPaths {
			set tColumnPaths = $LI(tRSData, 4)
		}

		// Get column names from compiled class (OPCUANODENAME params, in storage order)
		// These correspond to the column mask positions
		kill tColNames
		set tColIdx = 0
		set tClassDef = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
		if $IsObject(tClassDef) {
			set tStorage = tClassDef.Storages.GetAt(1)
			if $IsObject(tStorage) {
				set tDataDef = tStorage.Data.GetAt(1)
				if $IsObject(tDataDef) {
					for iS=1:1:tDataDef.Values.Count() {
						set tPropName = tDataDef.Values.GetAt(iS).Value
						if $Extract(tPropName,1)="%" continue
						if tPropName="NodePath" continue
						if tPropName="ServerTimeStamp" continue
						if tPropName="SourceTimeStamp" continue
						set tColIdx = tColIdx + 1
						for iP=1:1:tClassDef.Properties.Count() {
							set tProp = tClassDef.Properties.GetAt(iP)
							if tProp.Name = tPropName {
								set tColNames(tColIdx) = tProp.Parameters.GetAt("OPCUANODENAME")
								Quit
							}
						}
						if '$Data(tColNames(tColIdx)) set tColNames(tColIdx) = tPropName
					}
				}
			}
		}

		for i=1:1:tRSCount {
			set tRS = $LI(tRSList, i)
			set tInfo = {}
			set tInfo.path = $LI(tRS, 1)
			set tInfo.nodeNs = $LI(tRS, 2)
			set tInfo.nodeId = $LI(tRS, 3)
			set tInfo.nodeIdType = $LI(tRS, 4)

			set tChildren = []
			if $LL(tRS) >= 6 {
				set tMask = $LI(tRS, 5)
				set tAbsRefs = $LI(tRS, 6)
				set tRefIdx = 0
				for c=1:1:tColCount {
					if +$LI(tMask, c) {
						set tRefIdx = tRefIdx + 1
						set tRef = $LI(tAbsRefs, tRefIdx)
						set tChild = {}
						set tChild.displayName = $Get(tColNames(c), "Column"_c)
						set tChild.nodeNs = $LI(tRef, 1)
						set tChild.nodeId = $LI(tRef, 2)
						set tChild.nodeIdType = $LI(tRef, 3)
						// Include relativePath from stored column paths
						if tHasColumnPaths && ($LL(tColumnPaths) >= c) {
							set tPathStr = $LI(tColumnPaths, c)
							set tRelPath = ##class(%DynamicArray).%New()
							for seg=1:1:$Length(tPathStr, "/") {
								do tRelPath.%Push($Piece(tPathStr, "/", seg))
							}
							set tChild.relativePath = tRelPath
						}
						do tChildren.%Push(tChild)
					}
				}
			}
			set tInfo.childNodes = tChildren

			do tResult.%Push(tInfo)
		}
	} Catch (e) {}
	Quit tResult
}

/// Delete serial object subclasses for a DataSource class.
/// Scans the class's properties for types extending %SerialObject (excluding OPCUA.Types.*).
ClassMethod DeleteSerialSubclasses(pClassName As %String) [ Private ]
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
