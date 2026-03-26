Include %occInclude

/// Deploy an OPC UA data pipeline: generate a DataSource class,
/// add a business service item to the shared production, compile, and start.
/// Uses a single shared production (OPCUA.Pipeline.Production) where each
/// pipeline is a separate business service item.
Class OPCUA.REST.DeployService
{

/// The shared production class that holds all pipeline service items.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Deploy a complete pipeline from selected nodes.
/// Supports both v1 (flat nodes array) and v2 (columns + rowSources) payloads.
ClassMethod Deploy(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	// Detect v2 deploy request (has rowSources array)
	set tRS = pBody.%Get("rowSources")
	if $IsObject($Get(tRS)) && (tRS.%Size() > 0) {
		Quit ..DeployV2(pBody, .pResult)
	}

	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deployed = 0
	set pResult.compiled = 0
	set pResult.started = 0
	set pResult.productionClass = ..#ProductionClass
	Try {
		// --- Validate inputs ---
		set tNodes = pBody.%Get("nodes")
		if '$IsObject($Get(tNodes)) || (tNodes.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No nodes selected")
			Quit
		}

		set tClassName = pBody.%Get("className")
		if tClassName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing className")
			Quit
		}

		set tDataSourceName = pBody.%Get("dataSourceName")
		if tDataSourceName = "" set tDataSourceName = $Piece(tClassName, ".", *)

		set tMode = pBody.%Get("mode")
		if (tMode '= "polling") && (tMode '= "subscription") set tMode = "polling"

		// Check if DataSource class already exists
		if ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
			set tSC = $$$ERROR($$$GeneralError, "Class '"_tClassName_"' already exists. Choose a different name.")
			Quit
		}

		// --- Generate and compile DataSource class ---
		set tSC = ..GenerateDataSourceText(pBody, tNodes, tClassName, tDataSourceName, .tDSText)
		Quit:$$$ISERR(tSC)

		set tSC = ..WriteAndCompile(tClassName, tDSText)
		if $$$ISERR(tSC) {
			set pResult.error = "DataSource compilation failed: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set pResult.deployed = 1
		set pResult.dataSourceClass = tClassName

		// Derive SQL table name
		set tPackage = $Piece(tClassName, ".", 1, *-1)
		set tShort = $Piece(tClassName, ".", *)
		set pResult.tableName = $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
		set pResult.serviceItemName = tDataSourceName

		// --- Add service item to shared production ---
		set tSC = ..EnsureProductionExists()
		if $$$ISERR(tSC) {
			set pResult.error = "Failed to create production: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set tSC = ..AddServiceItem(pBody, tClassName, tDataSourceName, tMode)
		if $$$ISERR(tSC) {
			set pResult.error = "Failed to add service item: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set pResult.compiled = 1

		// --- Start or update the production ---
		set tEnableOnDeploy = pBody.%Get("enableOnDeploy")
		if tEnableOnDeploy '= 0 {
			set tSC = ..StartOrUpdateProduction()
			if $$$ISERR(tSC) {
				set pResult.error = "Failed to start production: "_$System.Status.GetErrorText(tSC)
				set tSC = $$$OK
				Quit
			}
			set pResult.started = 1
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Ensure the shared production class exists. Creates it on first deploy.
ClassMethod EnsureProductionExists() As %Status [ Private ]
{
	if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
		Quit $$$OK
	}

	// Create a minimal production with no items
	set tNL = $Char(10)
	set tText = "/// Shared OPC UA pipeline production. Service items are added automatically."_tNL
	set tText = tText_"Class "_..#ProductionClass_" Extends Ens.Production"_tNL
	set tText = tText_"{"_tNL_tNL
	set tText = tText_"XData ProductionDefinition"_tNL
	set tText = tText_"{"_tNL
	set tText = tText_"<Production Name="""_..#ProductionClass_""" LogGeneralTraceEvents=""false"">"_tNL
	set tText = tText_"  <Description>OPC UA Data Pipelines</Description>"_tNL
	set tText = tText_"  <ActorPoolSize>2</ActorPoolSize>"_tNL
	set tText = tText_"</Production>"_tNL
	set tText = tText_"}"_tNL_tNL
	set tText = tText_"}"_tNL

	Quit ..WriteAndCompile(..#ProductionClass, tText)
}

/// Add a new business service item to the shared production's XData.
ClassMethod AddServiceItem(pBody As %DynamicObject, pDSClassName As %String, pDSName As %String, pMode As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		// Open the production class definition
		set tClassDef = ##class(%Dictionary.ClassDefinition).%OpenId(..#ProductionClass)
		if '$IsObject(tClassDef) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production class definition")
			Quit
		}

		// Find the XData block
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

		// Read current XData content
		set tContent = ""
		while 'tXData.Data.AtEnd {
			set tContent = tContent _ tXData.Data.Read(32000)
		}

		// Build the new <Item> XML
		set tItemXML = ..BuildItemXML(pBody, pDSClassName, pDSName, pMode)

		// Insert before </Production>
		set tInsertPos = $Find(tContent, "</Production>")
		if tInsertPos = 0 {
			set tSC = $$$ERROR($$$GeneralError, "Cannot find </Production> tag in XData")
			Quit
		}
		// $Find returns position AFTER the match, so back up
		set tInsertPos = tInsertPos - $Length("</Production>")
		set tNewContent = $Extract(tContent, 1, tInsertPos - 1) _ tItemXML _ $Extract(tContent, tInsertPos, *)

		// Write back
		do tXData.Data.Clear()
		do tXData.Data.Write(tNewContent)

		// Save the class definition
		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)

		// Recompile the production
		set tSC = $System.OBJ.Compile(..#ProductionClass, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Build the XML fragment for a single <Item> element.
ClassMethod BuildItemXML(pBody As %DynamicObject, pDSClassName As %String, pDSName As %String, pMode As %String) As %String [ Private ]
{
	set tNL = $Char(10)
	set tURL = pBody.%Get("url")
	set tSecMode = +pBody.%Get("securityMode")
	if tSecMode '= 3 set tSecMode = 1

	set tVersion = +pBody.%Get("pipelineVersion")
	if (pMode = "subscription") && (tVersion = 2) {
		set tServiceClass = "OPCUA.Service.TCPSubscriptionRowSourceService"
	} elseif pMode = "subscription" {
		set tServiceClass = "OPCUA.Service.TCPSubscriptionService"
	} elseif tVersion = 2 {
		set tServiceClass = "OPCUA.Service.TCPPollingRowSourceService"
	} else {
		set tServiceClass = "OPCUA.Service.TCPPollingService"
	}

	set tXML = "  <Item Name="""_$ZConvert(pDSName, "O", "HTML")_""" Category="""" ClassName="""_tServiceClass_""""
	set tXML = tXML_" PoolSize=""1"" Enabled=""true"" Foreground=""false"""
	set tXML = tXML_" LogTraceEvents=""true"" Schedule="""">"_tNL

	// DataSourceClass
	set tXML = tXML_"    <Setting Target=""Adapter"" Name=""DataSourceClass"">"_pDSClassName_"</Setting>"_tNL

	// URL
	set tXML = tXML_"    <Setting Target=""Adapter"" Name=""URL"">"_$ZConvert(tURL, "O", "HTML")_"</Setting>"_tNL

	// Mode-specific settings
	if pMode = "polling" {
		set tInterval = +pBody.%Get("callInterval")
		if tInterval < 1 set tInterval = 5
		set tXML = tXML_"    <Setting Target=""Adapter"" Name=""CallInterval"">"_tInterval_"</Setting>"_tNL
	} else {
		set tPubInterval = +pBody.%Get("publishingInterval")
		if tPubInterval < 1 set tPubInterval = 1000
		set tXML = tXML_"    <Setting Target=""Adapter"" Name=""RequestedPublishingInterval"">"_tPubInterval_"</Setting>"_tNL

		set tSampInterval = pBody.%Get("samplingInterval")
		if tSampInterval = "" set tSampInterval = 0
		set tXML = tXML_"    <Setting Target=""Adapter"" Name=""RequestedSamplingInterval"">"_+tSampInterval_"</Setting>"_tNL

		set tQueueSize = +pBody.%Get("queueSize")
		if tQueueSize < 1 set tQueueSize = 5
		set tXML = tXML_"    <Setting Target=""Adapter"" Name=""RequestedQueueSize"">"_tQueueSize_"</Setting>"_tNL
	}

	// Security settings
	if tSecMode = 3 {
		set tXML = tXML_"    <Setting Target=""Adapter"" Name=""SecurityMode"">3</Setting>"_tNL
		do ..AppendSettingIfNotEmpty(.tXML, pBody, "clientURI", "ClientURI", tNL)
		do ..AppendSettingIfNotEmpty(.tXML, pBody, "certPath", "PublicCertificate", tNL)
		do ..AppendSettingIfNotEmpty(.tXML, pBody, "keyPath", "PrivateKey", tNL)
		do ..AppendSettingIfNotEmpty(.tXML, pBody, "trustDir", "TrustListDir", tNL)
		do ..AppendSettingIfNotEmpty(.tXML, pBody, "crlDir", "RevocationListDir", tNL)
	}

	// Username/password
	do ..AppendSettingIfNotEmpty(.tXML, pBody, "username", "Username", tNL)
	do ..AppendSettingIfNotEmpty(.tXML, pBody, "password", "Password", tNL)

	set tXML = tXML_"  </Item>"_tNL

	Quit tXML
}

/// Helper: append a setting XML line if value is non-empty.
ClassMethod AppendSettingIfNotEmpty(ByRef pXML As %String, pBody As %DynamicObject, pJsonKey As %String, pSettingName As %String, pNL As %String) [ Private ]
{
	set tVal = pBody.%Get(pJsonKey)
	if tVal '= "" {
		set pXML = pXML_"    <Setting Target=""Adapter"" Name="""_pSettingName_""">"_$ZConvert(tVal, "O", "HTML")_"</Setting>"_pNL
	}
}

/// Start the production, or update it if already running.
ClassMethod StartOrUpdateProduction() As %Status [ Private ]
{
	set tSC = ##class(Ens.Director).GetProductionStatus(.tProdName, .tState)

	// State: $$$eProductionStateRunning = 1, Stopped = 2, Suspended = 3, Troubled = 4
	if (tProdName = ..#ProductionClass) && (tState = 1) {
		// Our production is already running — update it to pick up the new item
		Quit ##class(Ens.Director).UpdateProduction()
	}

	if (tProdName '= "") && (tState = 1) {
		// A different production is running — stop it first
		set tSC = ##class(Ens.Director).StopProduction(, 1)
		if $$$ISERR(tSC) Quit tSC
		hang 1
	}

	// Start our production
	Quit ##class(Ens.Director).StartProduction(..#ProductionClass)
}

/// Generate the DataSource class definition text.
ClassMethod GenerateDataSourceText(pBody As %DynamicObject, pNodes As %DynamicArray, pClassName As %String, pDataSourceName As %String, Output pText As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tNodeCount = pNodes.%Size()

		// Determine default namespace (most common among selected nodes)
		for i=0:1:tNodeCount-1 {
			set tNode = pNodes.%Get(i)
			set tNS = +tNode.%Get("nodeNs")
			set tNSCount(tNS) = $Get(tNSCount(tNS), 0) + 1
		}
		set tDefaultNS = 0
		set tMaxCount = 0
		set tNS = ""
		for {
			set tNS = $Order(tNSCount(tNS))
			if tNS = "" Quit
			if tNSCount(tNS) > tMaxCount {
				set tMaxCount = tNSCount(tNS)
				set tDefaultNS = tNS
			}
		}

		// Build class text
		set tNL = $Char(10)
		set pText = "/// Auto-generated OPC UA DataSource class."_tNL
		set pText = pText_"Class "_pClassName_" Extends (%Persistent, OPCUA.DataSource.Definition)"_tNL
		set pText = pText_"{"_tNL
		set pText = pText_tNL
		set pText = pText_"Parameter OPCUADATASOURCE = """_pDataSourceName_""";"_tNL
		set pText = pText_tNL
		set pText = pText_"Parameter OPCUDEFAULTANAMESPACE = "_tDefaultNS_";"_tNL

		// Generate properties
		for i=0:1:tNodeCount-1 {
			set tNode = pNodes.%Get(i)
			set tDisplayName = tNode.%Get("displayName")
			set tNodeId = tNode.%Get("nodeId")
			set tNodeNS = +tNode.%Get("nodeNs")
			set tType = tNode.%Get("inferredType")
			if tType = "" set tType = "OPCUA.Types.StringDataValue"

			// Sanitize property name
			set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tDisplayName, .tUsedNames)

			set pText = pText_tNL
			set pText = pText_"Property "_tPropName_" As "_tType_"(OPCUANODENAME = """_tNodeId_""""
			if tNodeNS '= tDefaultNS {
				set pText = pText_", OPCUANAMESPACE = """_tNodeNS_""""
			}
			set pText = pText_");"_tNL
		}

		set pText = pText_tNL_"}"_tNL

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Write class text to a temp file and compile it.
ClassMethod WriteAndCompile(pClassName As %String, pText As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tRelPath = $Replace(pClassName, ".", "/")_".cls"
		set tDir = "/opt/irisapp/src/"
		set tFilePath = tDir_tRelPath

		set tFileDir = ##class(%File).GetDirectory(tFilePath)
		do ##class(%File).CreateDirectoryChain(tFileDir)

		set tStream = ##class(%Stream.FileCharacter).%New()
		set tSC = tStream.LinkToFile(tFilePath)
		$$$ThrowOnError(tSC)
		set tSC = tStream.Write(pText)
		$$$ThrowOnError(tSC)
		set tSC = tStream.%Save()
		$$$ThrowOnError(tSC)

		set tSC = $System.OBJ.Load(tFilePath, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

// ==================== v2 Row-Source Pipeline Deploy ====================

/// Deploy a v2 pipeline with multiple row sources sharing the same column schema.
/// Produces one DataSource class, one service item, one table — multiple rows per poll.
ClassMethod DeployV2(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deployed = 0
	set pResult.compiled = 0
	set pResult.started = 0
	set pResult.productionClass = ..#ProductionClass
	Try {
		// --- Validate inputs ---
		set tRowSources = pBody.%Get("rowSources")
		set tColumns = pBody.%Get("columns")

		if '$IsObject($Get(tColumns)) || (tColumns.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No columns defined")
			Quit
		}

		if '$IsObject($Get(tRowSources)) || (tRowSources.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No row sources defined")
			Quit
		}

		set tClassName = pBody.%Get("className")
		if tClassName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing className")
			Quit
		}

		set tDataSourceName = pBody.%Get("dataSourceName")
		if tDataSourceName = "" set tDataSourceName = $Piece(tClassName, ".", *)

		set tMode = pBody.%Get("mode")
		if (tMode '= "polling") && (tMode '= "subscription") set tMode = "polling"

		// Check if class already exists
		if ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
			set tSC = $$$ERROR($$$GeneralError, "Class '"_tClassName_"' already exists. Choose a different name.")
			Quit
		}

		// Validate row sources have correct child count
		set tColCount = tColumns.%Size()
		for iRS=0:1:tRowSources.%Size()-1 {
			set tRS = tRowSources.%Get(iRS)
			set tChildren = tRS.%Get("childNodes")
			if '$IsObject($Get(tChildren)) || (tChildren.%Size() = 0) {
				set tSC = $$$ERROR($$$GeneralError, "Row source '"_tRS.%Get("displayName")_"' has no child nodes")
				Quit
			}
			// Row sources may have fewer children than union columns (missing columns → NULL)
			if tChildren.%Size() > tColCount {
				set tSC = $$$ERROR($$$GeneralError, "Row source '"_tRS.%Get("displayName")_"' has more child nodes ("_tChildren.%Size()_") than columns ("_tColCount_")")
				Quit
			}
		}
		Quit:$$$ISERR(tSC)

		// --- Generate and compile v2 DataSource class ---
		set tSC = ..GenerateDataSourceTextV2(pBody, tColumns, tRowSources, tClassName, tDataSourceName, .tDSText)
		Quit:$$$ISERR(tSC)

		set tSC = ..WriteAndCompile(tClassName, tDSText)
		if $$$ISERR(tSC) {
			set pResult.error = "DataSource compilation failed: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set pResult.deployed = 1
		set pResult.dataSourceClass = tClassName

		// Derive SQL table name
		set tPackage = $Piece(tClassName, ".", 1, *-1)
		set tShort = $Piece(tClassName, ".", *)
		set pResult.tableName = $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
		set pResult.serviceItemName = tDataSourceName

		// --- Store row source metadata ---
		set tSC = ..StoreRowSourceMetadata(tClassName, tRowSources, tColumns)
		if $$$ISERR(tSC) {
			set pResult.error = "Failed to store row source metadata: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		// --- Add service item to shared production ---
		set tSC = ..EnsureProductionExists()
		if $$$ISERR(tSC) {
			set pResult.error = "Failed to create production: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set tSC = ..AddServiceItem(pBody, tClassName, tDataSourceName, tMode)
		if $$$ISERR(tSC) {
			set pResult.error = "Failed to add service item: "_$System.Status.GetErrorText(tSC)
			set tSC = $$$OK
			Quit
		}

		set pResult.compiled = 1

		// --- Start or update the production ---
		set tEnableOnDeploy = pBody.%Get("enableOnDeploy")
		if tEnableOnDeploy '= 0 {
			set tSC = ..StartOrUpdateProduction()
			if $$$ISERR(tSC) {
				set pResult.error = "Failed to start production: "_$System.Status.GetErrorText(tSC)
				set tSC = $$$OK
				Quit
			}
			set pResult.started = 1
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Generate v2 DataSource class text with NodePath + relative column names.
ClassMethod GenerateDataSourceTextV2(pBody As %DynamicObject, pColumns As %DynamicArray, pRowSources As %DynamicArray, pClassName As %String, pDataSourceName As %String, Output pText As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		// Determine default namespace from the first row source's child nodes
		set tFirstRS = pRowSources.%Get(0)
		set tChildren = tFirstRS.%Get("childNodes")
		for i=0:1:tChildren.%Size()-1 {
			set tChild = tChildren.%Get(i)
			set tNS = +tChild.%Get("nodeNs")
			set tNSCount(tNS) = $Get(tNSCount(tNS), 0) + 1
		}
		set tDefaultNS = 0
		set tMaxCount = 0
		set tNS = ""
		for {
			set tNS = $Order(tNSCount(tNS))
			if tNS = "" Quit
			if tNSCount(tNS) > tMaxCount {
				set tMaxCount = tNSCount(tNS)
				set tDefaultNS = tNS
			}
		}

		// Build class text
		set tNL = $Char(10)
		set pText = "/// Auto-generated OPC UA DataSource class (v2 row-source model)."_tNL
		set pText = pText_"Class "_pClassName_" Extends (%Persistent, OPCUA.DataSource.Definition)"_tNL
		set pText = pText_"{"_tNL
		set pText = pText_tNL
		set pText = pText_"Parameter OPCUADATASOURCE = """_pDataSourceName_""";"_tNL
		set pText = pText_tNL
		set pText = pText_"Parameter OPCUDEFAULTANAMESPACE = "_tDefaultNS_";"_tNL
		set pText = pText_tNL
		set pText = pText_"Parameter OPCUAPIPELINEVERSION = 2;"_tNL

		// Row metadata: NodePath, shared timestamps
		set pText = pText_tNL
		set pText = pText_"Property NodePath As %String(MAXLEN = 500);"_tNL
		set pText = pText_tNL
		set pText = pText_"Property ServerTimeStamp As %TimeStamp;"_tNL
		set pText = pText_tNL
		set pText = pText_"Property SourceTimeStamp As %TimeStamp;"_tNL

		// Generate column properties with plain types and relative OPCUANODENAME
		for i=0:1:pColumns.%Size()-1 {
			set tCol = pColumns.%Get(i)
			set tDisplayName = tCol.%Get("displayName")
			set tInferredType = tCol.%Get("inferredType")

			// Map OPCUA.Types.*DataValue to plain IRIS types
			set tType = ..MapToPlainType(tInferredType)

			// Use the first row source's corresponding child node namespace
			set tChildNS = tDefaultNS
			if i < tChildren.%Size() {
				set tChildNS = +tChildren.%Get(i).%Get("nodeNs")
			}

			// Sanitize property name
			set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tDisplayName, .tUsedNames)

			// Use the display name as the relative OPCUANODENAME (browse name)
			set pText = pText_tNL
			set pText = pText_"Property "_tPropName_" As "_tType_"(OPCUANODENAME = """_tDisplayName_""""
			if tChildNS '= tDefaultNS {
				set pText = pText_", OPCUANAMESPACE = """_tChildNS_""""
			}
			set pText = pText_");"_tNL
		}

		set pText = pText_tNL_"}"_tNL

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Store row source metadata in ^OPCUA.RowSource global for runtime use by row-source services.
/// Computes a column mask per row source: which union columns each RS has (by matching childNode displayNames).
/// Missing columns will be NULL at runtime.
ClassMethod StoreRowSourceMetadata(pClassName As %String, pRowSources As %DynamicArray, pColumns As %DynamicArray) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tRSCount = pRowSources.%Size()
		set tColCount = pColumns.%Size()

		// Build ordered column name list for matching
		for c=0:1:tColCount-1 {
			set tColNames(c) = pColumns.%Get(c).%Get("displayName")
		}

		// Build row source list with column masks
		// Each RS entry: $LB(path, ns, id, idType, columnMask, absNodeRefs)
		//   columnMask = $LB(1,0,1,...) — M entries, 1=has column, 0=NULL
		//   absNodeRefs = $LB($LB(ns,id,type),...) — only for mask=1 columns, in mask order
		set tRSList = ""
		for i=0:1:tRSCount-1 {
			set tRS = pRowSources.%Get(i)
			set tPath = tRS.%Get("path")
			set tNodeNs = +tRS.%Get("nodeNs")
			set tNodeId = tRS.%Get("nodeId")
			set tNodeIdType = +tRS.%Get("nodeIdType")

			// Build a lookup: childNode displayName → child object
			set tChildren = tRS.%Get("childNodes")
			kill tChildMap
			for j=0:1:tChildren.%Size()-1 {
				set tChild = tChildren.%Get(j)
				set tChildMap(tChild.%Get("displayName")) = tChild
			}

			// Build column mask and abs node refs by iterating union columns in order
			set tMask = ""
			set tAbsNodeRefs = ""
			for c=0:1:tColCount-1 {
				if $Data(tChildMap(tColNames(c))) {
					// This row source has this column
					set tChild = tChildMap(tColNames(c))
					set tMask = tMask _ $LB(1)
					set tAbsNodeRefs = tAbsNodeRefs _ $LB($LB(+tChild.%Get("nodeNs"), tChild.%Get("nodeId"), +tChild.%Get("nodeIdType")))
				} else {
					// Missing column → NULL at runtime
					set tMask = tMask _ $LB(0)
				}
			}

			set tRSList = tRSList _ $LB($LB(tPath, tNodeNs, tNodeId, tNodeIdType, tMask, tAbsNodeRefs))
		}

		// Store: $LB(rowSourceCount, columnCount, rowSourceList)
		set ^OPCUA.RowSource(pClassName) = $LB(tRSCount, tColCount, tRSList)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Map OPCUA.Types.*DataValue to plain IRIS types for v2 flat columns.
ClassMethod MapToPlainType(pInferredType As %String) As %String
{
	if pInferredType = "" Quit "%String"
	if pInferredType = "OPCUA.Types.DoubleDataValue" Quit "%Double"
	if pInferredType = "OPCUA.Types.IntegerDataValue" Quit "%Integer"
	if pInferredType = "OPCUA.Types.BooleanDataValue" Quit "%Boolean"
	if pInferredType = "OPCUA.Types.TimeStampDataValue" Quit "%TimeStamp"
	if pInferredType = "OPCUA.Types.StringDataValue" Quit "%String"
	// Array types → store as string (JSON)
	if pInferredType [ "ArrayDataValue" Quit "%String(MAXLEN=32000)"
	// Already a plain type (e.g., %Double passed directly)
	if $Extract(pInferredType, 1) = "%" Quit pInferredType
	// Default fallback
	Quit "%String"
}

}
