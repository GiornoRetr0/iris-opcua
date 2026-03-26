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
		// Check if production class exists
		if '##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
			Quit  // No production yet — return empty array
		}

		// Get running production info
		do ##class(Ens.Director).GetProductionStatus(.tRunningProd, .tProdState)
		set tProdRunning = (tRunningProd = ..#ProductionClass) && (tProdState = 1)

		// Open class definition and parse XData
		set tClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(..#ProductionClass)
		if '$IsObject(tClassDef) Quit

		// Find XData
		set tXData = ""
		for i=1:1:tClassDef.XDatas.Count() {
			if tClassDef.XDatas.GetAt(i).Name = "ProductionDefinition" {
				set tXData = tClassDef.XDatas.GetAt(i)
				Quit
			}
		}
		if '$IsObject(tXData) Quit

		// Read XData content
		set tContent = ""
		while 'tXData.Data.AtEnd {
			set tContent = tContent _ tXData.Data.Read(32000)
		}

		// Parse XML to extract items
		set tSC = ..ParseItems(tContent, tProdRunning, pResult)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Parse production XData XML and extract Item elements using string parsing.
ClassMethod ParseItems(pContent As %String, pProdRunning As %Boolean, pResult As %DynamicArray) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		// Find each <Item ...>...</Item> block
		set tPos = 1
		for {
			set tItemStart = $Find(pContent, "<Item ", tPos)
			if tItemStart = 0 Quit

			set tItemEnd = $Find(pContent, "</Item>", tItemStart)
			if tItemEnd = 0 Quit

			// Extract the full item block (from <Item to </Item>)
			set tBlock = $Extract(pContent, tItemStart - 6, tItemEnd - 1)
			set tPos = tItemEnd

			set tItem = {}
			set tItem.name = ..ExtractAttr(tBlock, "Name")
			set tItem.className = ..ExtractAttr(tBlock, "ClassName")
			set tItem.enabled = (..ExtractAttr(tBlock, "Enabled") = "true")

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

			// Extract settings
			set tItem.dataSourceClass = ..ExtractSetting(tBlock, "DataSourceClass")
			set tItem.url = ..ExtractSetting(tBlock, "URL")
			set tItem.callInterval = ..ExtractSetting(tBlock, "CallInterval")
			set tItem.publishingInterval = ..ExtractSetting(tBlock, "RequestedPublishingInterval")

			// Derive table name from DataSource class
			if tItem.dataSourceClass '= "" {
				set tPkg = $Piece(tItem.dataSourceClass, ".", 1, *-1)
				set tShort = $Piece(tItem.dataSourceClass, ".", *)
				set tItem.tableName = $Select(tPkg="":tShort, 1:$Replace(tPkg, ".", "_")_"."_tShort)
			}

			// Get runtime status if production is running
			if pProdRunning {
				set tItem.running = ##class(Ens.Director).IsItemEnabled(tItem.name, .tSCStatus)
				set tItem.rowCount = ..GetRowCount(tItem.dataSourceClass)
			} else {
				set tItem.running = 0
				set tItem.rowCount = 0
			}

			set tItem.productionRunning = pProdRunning
			set tItem.nodes = ..GetNodeNames(tItem.dataSourceClass)

			// Add row source info for v2 pipelines
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

/// Extract an XML attribute value from a tag string.
ClassMethod ExtractAttr(pXML As %String, pAttr As %String) As %String [ Private ]
{
	set tSearch = pAttr_"="""
	set tPos = $Find(pXML, tSearch)
	if tPos = 0 Quit ""
	set tEnd = $Find(pXML, """", tPos)
	if tEnd = 0 Quit ""
	Quit $Extract(pXML, tPos, tEnd - 2)
}

/// Extract a Setting value by Name from an Item XML block.
ClassMethod ExtractSetting(pXML As %String, pName As %String) As %String [ Private ]
{
	set tSearch = "Name="""_pName_""">"
	set tPos = $Find(pXML, tSearch)
	if tPos = 0 Quit ""
	set tEnd = $Find(pXML, "</Setting>", tPos)
	if tEnd = 0 Quit ""
	Quit $Extract(pXML, tPos, tEnd - $Length("</Setting>") - 1)
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

/// Toggle a pipeline service item on/off.
/// Updates the XData Enabled attribute then calls UpdateProduction
/// to apply the change — this is the correct IRIS pattern.
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

		// Check production is running
		do ##class(Ens.Director).GetProductionStatus(.tRunning, .tRunState)
		if (tRunning '= ..#ProductionClass) || (tRunState '= 1) {
			set tSC = $$$ERROR($$$GeneralError, "Pipeline production is not running")
			Quit
		}

		set tEnabled = ##class(Ens.Director).IsItemEnabled(tName, .tSCCheck)
		set tNewState = 'tEnabled

		// Update XData Enabled attribute and recompile
		set tSC = ..SetItemEnabledInXData(tName, tNewState)
		$$$ThrowOnError(tSC)

		// UpdateProduction applies the XData change to the runtime
		set tSC = ##class(Ens.Director).UpdateProduction()
		$$$ThrowOnError(tSC)

		set pResult.name = tName
		set pResult.enabled = tNewState

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Update the Enabled attribute of an Item in the production XData.
ClassMethod SetItemEnabledInXData(pItemName As %String, pEnabled As %Boolean) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(..#ProductionClass)
		if '$IsObject(tClassDef) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production class")
			Quit
		}

		set tXData = ""
		for i=1:1:tClassDef.XDatas.Count() {
			if tClassDef.XDatas.GetAt(i).Name = "ProductionDefinition" {
				set tXData = tClassDef.XDatas.GetAt(i)
				Quit
			}
		}
		if '$IsObject(tXData) Quit

		set tContent = ""
		while 'tXData.Data.AtEnd {
			set tContent = tContent _ tXData.Data.Read(32000)
		}

		// Find the Item with this Name and replace its Enabled attribute
		set tEnabledStr = $Select(pEnabled: "true", 1: "false")

		// Find Name="pItemName" then find the Enabled=" before it in the same <Item tag
		set tNamePos = $Find(tContent, "Name="""_pItemName_"""")
		if tNamePos = 0 Quit

		// Walk back to find <Item
		set tItemPos = tNamePos
		for {
			set tItemPos = tItemPos - 1
			if tItemPos < 1 Quit
			if $Extract(tContent, tItemPos, tItemPos+4) = "<Item" Quit
		}

		// Find Enabled="..." within this Item tag (before the closing >)
		set tTagEnd = $Find(tContent, ">", tNamePos)
		set tItemTag = $Extract(tContent, tItemPos, tTagEnd - 1)

		// Replace Enabled="true" or Enabled="false" in the tag
		set tOld1 = "Enabled=""true"""
		set tOld2 = "Enabled=""false"""
		set tNew = "Enabled="""_tEnabledStr_""""

		set tNewTag = $Replace($Replace(tItemTag, tOld1, tNew), tOld2, tNew)

		set tNewContent = $Extract(tContent, 1, tItemPos - 1) _ tNewTag _ $Extract(tContent, tTagEnd, *)

		do tXData.Data.Clear()
		do tXData.Data.Write(tNewContent)

		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)

		set tSC = $System.OBJ.Compile(..#ProductionClass, "ck-d")
		$$$ThrowOnError(tSC)

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

		// If production is running, disable the item first
		do ##class(Ens.Director).GetProductionStatus(.tRunning, .tRunState2)
		if (tRunning = ..#ProductionClass) && (tRunState2 = 1) {
			if ##class(Ens.Director).IsItemEnabled(tName, .tSCCheck) {
				do ##class(Ens.Director).EnableConfigItem(tName, 0)
			}
		}

		// Find and remove the Item from the production XData (recompiles production)
		set tSC = ..RemoveItemFromXData(tName, .tDSClass)
		$$$ThrowOnError(tSC)

		// Update running production to remove the deleted item from runtime
		// This is safe because the item is already gone from XData,
		// so UpdateProduction won't re-enable anything
		if (tRunning = ..#ProductionClass) && (tRunState2 = 1) {
			do ##class(Ens.Director).UpdateProduction()
		}

		// Delete DataSource class if it exists
		if (tDSClass '= "") && ##class(%Dictionary.ClassDefinition).%ExistsId(tDSClass) {
			do $System.OBJ.Delete(tDSClass, "-d")
		}

		// Clean up v2 row source metadata (no-op for v1 pipelines)
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

/// Remove an Item element from the production XData by name.
/// Returns the DataSourceClass value so the caller can delete it.
ClassMethod RemoveItemFromXData(pItemName As %String, Output pDSClass As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	set pDSClass = ""
	Try {
		set tClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(..#ProductionClass)
		if '$IsObject(tClassDef) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production class")
			Quit
		}

		set tXData = ""
		for i=1:1:tClassDef.XDatas.Count() {
			if tClassDef.XDatas.GetAt(i).Name = "ProductionDefinition" {
				set tXData = tClassDef.XDatas.GetAt(i)
				Quit
			}
		}
		if '$IsObject(tXData) {
			set tSC = $$$ERROR($$$GeneralError, "Production XData not found")
			Quit
		}

		set tContent = ""
		while 'tXData.Data.AtEnd {
			set tContent = tContent _ tXData.Data.Read(32000)
		}

		// Find the Item with matching Name attribute and extract DataSourceClass
		// Use regex-like approach: find <Item Name="pItemName" ... </Item>
		set tItemStart = $Find(tContent, "Name="""_pItemName_"""")
		if tItemStart = 0 {
			set tSC = $$$ERROR($$$GeneralError, "Pipeline '"_pItemName_"' not found in production")
			Quit
		}

		// Find the <Item that precedes this Name attribute
		set tPos = tItemStart
		for {
			set tPos = tPos - 1
			if tPos < 1 Quit
			if $Extract(tContent, tPos, tPos+4) = "<Item" Quit
		}
		set tStartPos = tPos

		// Find closing </Item>
		set tEndPos = $Find(tContent, "</Item>", tItemStart)
		if tEndPos = 0 {
			set tSC = $$$ERROR($$$GeneralError, "Malformed production XData")
			Quit
		}

		// Extract the item XML to find DataSourceClass
		set tItemXML = $Extract(tContent, tStartPos, tEndPos - 1)
		set tDSPos = $Find(tItemXML, "Name=""DataSourceClass"">")
		if tDSPos > 0 {
			set tDSEnd = $Find(tItemXML, "</Setting>", tDSPos)
			if tDSEnd > 0 {
				set pDSClass = $Extract(tItemXML, tDSPos, tDSEnd - $Length("</Setting>") - 1)
			}
		}

		// Remove the item from content (including any preceding whitespace/newline)
		set tRemoveStart = tStartPos
		// Back up over whitespace before <Item
		while (tRemoveStart > 1) && ($Extract(tContent, tRemoveStart - 1) ? 1(1" ",1C)) {
			set tRemoveStart = tRemoveStart - 1
		}

		set tNewContent = $Extract(tContent, 1, tRemoveStart - 1) _ $Extract(tContent, tEndPos, *)

		// Write back
		do tXData.Data.Clear()
		do tXData.Data.Write(tNewContent)

		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)

		set tSC = $System.OBJ.Compile(..#ProductionClass, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Get row source information for a v2 pipeline from ^OPCUA.RowSource global.
ClassMethod GetRowSourceInfo(pClassName As %String) As %DynamicArray [ Private ]
{
	set tResult = []
	Try {
		set tRSData = $Get(^OPCUA.RowSource(pClassName))
		if tRSData = "" Quit

		set tRSCount = $LI(tRSData, 1)
		set tRSList = $LI(tRSData, 3)

		for i=1:1:tRSCount {
			set tRS = $LI(tRSList, i)
			set tInfo = {}
			set tInfo.path = $LI(tRS, 1)
			set tInfo.nodeNs = $LI(tRS, 2)
			set tInfo.nodeId = $LI(tRS, 3)
			set tInfo.nodeIdType = $LI(tRS, 4)
			do tResult.%Push(tInfo)
		}
	} Catch (e) {}
	Quit tResult
}

}
