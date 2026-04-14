Include %occInclude

/// Deploy an OPC UA data pipeline: generate a DataSource class,
/// add a business service item to the shared production, compile, and start.
/// Uses a single shared production (OPCUA.Pipeline.Production) where each
/// pipeline is a separate business service item.
Class OPCUA.REST.DeployService
{

/// The shared production class that holds all pipeline service items.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Source directory for generated class files.
Parameter SourceDir = "/opt/irisapp/src/";

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

		set pResult.deployed = 1
		set pResult.dataSourceClass = tClassName

		// Derive SQL table name
		set tPackage = $Piece(tClassName, ".", 1, *-1)
		set tShort = $Piece(tClassName, ".", *)
		set pResult.tableName = $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
		set pResult.serviceItemName = tDataSourceName

		// --- Add service item to shared production ---
		set tSC = ..EnsureProductionExists()
		Quit:$$$ISERR(tSC)

		set tSC = ..AddServiceItem(pBody, tClassName, tDataSourceName, tMode)
		Quit:$$$ISERR(tSC)

		set pResult.compiled = 1

		// --- Start or update the production ---
		set tSC = ..StartOrUpdateProduction()
		Quit:$$$ISERR(tSC)
		set pResult.started = 1

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

	#dim tSC As %Status = $$$OK
	Try {
		set tClassDef = ##class(%Dictionary.ClassDefinition).%New(..#ProductionClass)
		set tClassDef.Description = "Shared OPC UA pipeline production. Service items are added automatically."
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

/// Add a new business service item to the shared production using the Ens.Config API.
ClassMethod AddServiceItem(pBody As %DynamicObject, pDSClassName As %String, pDSName As %String, pMode As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if '$IsObject(tProd) {
			set tSC = $$$ERROR($$$GeneralError, "Cannot open production: "_..#ProductionClass)
			Quit
		}

		// Determine service class
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

		// Create config item
		set tItem = ##class(Ens.Config.Item).%New()
		set tItem.Name = pDSName
		set tItem.ClassName = tServiceClass
		set tItem.PoolSize = 1
		set tItem.Enabled = 1
		set tItem.LogTraceEvents = 1

		// Add adapter settings
		do ..AddSetting(tItem, "Adapter", "DataSourceClass", pDSClassName)
		do ..AddSetting(tItem, "Adapter", "URL", pBody.%Get("url"))

		if pMode = "polling" {
			set tInterval = +pBody.%Get("callInterval")
			if tInterval < 1 set tInterval = 5
			do ..AddSetting(tItem, "Adapter", "CallInterval", tInterval)
		} else {
			set tPubInterval = +pBody.%Get("publishingInterval")
			if tPubInterval < 1 set tPubInterval = 1000
			do ..AddSetting(tItem, "Adapter", "RequestedPublishingInterval", tPubInterval)
			set tSampInterval = pBody.%Get("samplingInterval")
			if tSampInterval = "" set tSampInterval = 0
			do ..AddSetting(tItem, "Adapter", "RequestedSamplingInterval", +tSampInterval)
			set tQueueSize = +pBody.%Get("queueSize")
			if tQueueSize < 1 set tQueueSize = 5
			do ..AddSetting(tItem, "Adapter", "RequestedQueueSize", tQueueSize)
		}

		// Security settings
		set tSecMode = +pBody.%Get("securityMode")
		if tSecMode '= 3 set tSecMode = 1
		if tSecMode = 3 {
			do ..AddSetting(tItem, "Adapter", "SecurityMode", 3)
			do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "clientURI", "ClientURI")
			do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "certPath", "PublicCertificate")
			do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "keyPath", "PrivateKey")
			do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "trustDir", "TrustListDir")
			do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "crlDir", "RevocationListDir")
		}

		// Credentials
		do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "username", "Username")
		do ..AddSettingIfNotEmpty(tItem, "Adapter", pBody, "password", "Password")

		// Insert into production, save, and persist to class
		do tProd.Items.Insert(tItem)
		set tSC = tProd.%Save()
		$$$ThrowOnError(tSC)
		set tSC = tProd.SaveToClass()
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Add a setting to a config item.
ClassMethod AddSetting(pItem As Ens.Config.Item, pTarget As %String, pName As %String, pValue As %String) [ Private ]
{
	set tSetting = ##class(Ens.Config.Setting).%New()
	set tSetting.Target = pTarget
	set tSetting.Name = pName
	set tSetting.Value = pValue
	do pItem.Settings.Insert(tSetting)
}

/// Add a setting only if the JSON body has a non-empty value for the given key.
ClassMethod AddSettingIfNotEmpty(pItem As Ens.Config.Item, pTarget As %String, pBody As %DynamicObject, pJsonKey As %String, pSettingName As %String) [ Private ]
{
	set tVal = pBody.%Get(pJsonKey)
	if tVal '= "" {
		do ..AddSetting(pItem, pTarget, pSettingName, tVal)
	}
}

/// Start the production, or update it if already running.
ClassMethod StartOrUpdateProduction() As %Status
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

/// Generate and compile a v1 DataSource class using %Dictionary API.
ClassMethod GenerateDataSourceText(pBody As %DynamicObject, pNodes As %DynamicArray, pClassName As %String, pDataSourceName As %String, Output pText As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tNodeCount = pNodes.%Size()

		// Determine default namespace (most common among selected nodes)
		set tDefaultNS = ..FindDefaultNamespace(pNodes)

		// Create class definition
		set tClassDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
		set tClassDef.Description = "Auto-generated OPC UA DataSource class."
		set tClassDef.Super = "%Persistent,OPCUA.DataSource.Definition"

		do ..AddParameter(tClassDef, "OPCUADATASOURCE", pDataSourceName)
		do ..AddParameter(tClassDef, "OPCUDEFAULTANAMESPACE", tDefaultNS)

		// Generate properties
		for i=0:1:tNodeCount-1 {
			set tNode = pNodes.%Get(i)
			set tDisplayName = tNode.%Get("displayName")
			set tNodeId = tNode.%Get("nodeId")
			set tNodeNS = +tNode.%Get("nodeNs")
			set tType = tNode.%Get("inferredType")
			if tType = "" set tType = "OPCUA.Types.StringDataValue"

			set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tDisplayName, .tUsedNames)

			set tProp = ##class(%Dictionary.PropertyDefinition).%New()
			set tProp.Name = tPropName
			set tProp.Type = tType
			do tProp.Parameters.SetAt(tNodeId, "OPCUANODENAME")
			if tNodeNS '= tDefaultNS {
				do tProp.Parameters.SetAt(tNodeNS, "OPCUANAMESPACE")
			}
			do tClassDef.Properties.Insert(tProp)
		}

		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)
		set tSC = $System.OBJ.Compile(pClassName, "ck-d")
		$$$ThrowOnError(tSC)

		// pText not used by caller for v1, but set for consistency
		set pText = ""

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Find the most common namespace among a set of nodes.
ClassMethod FindDefaultNamespace(pNodes As %DynamicArray) As %Integer [ Private ]
{
	for i=0:1:pNodes.%Size()-1 {
		set tNS = +pNodes.%Get(i).%Get("nodeNs")
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
	Quit tDefaultNS
}

/// Add a parameter to a class definition.
ClassMethod AddParameter(pClassDef As %Dictionary.ClassDefinition, pName As %String, pValue As %String) [ Private ]
{
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = pName
	set tParam.Default = pValue
	do pClassDef.Parameters.Insert(tParam)
}

/// Write class text to a temp file and compile it.
ClassMethod WriteAndCompile(pClassName As %String, pText As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tRelPath = $Replace(pClassName, ".", "/")_".cls"
		set tFilePath = ..#SourceDir_tRelPath

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

		// --- Generate and compile v2 DataSource class (serial classes compiled first internally) ---
		set tSC = ..GenerateDataSourceTextV2(pBody, tColumns, tRowSources, tClassName, tDataSourceName, .tDSText, .tSerialClasses)
		Quit:$$$ISERR(tSC)

		set pResult.deployed = 1
		set pResult.dataSourceClass = tClassName

		// Derive SQL table name
		set tPackage = $Piece(tClassName, ".", 1, *-1)
		set tShort = $Piece(tClassName, ".", *)
		set pResult.tableName = $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
		set pResult.serviceItemName = tDataSourceName

		// --- Store row source metadata ---
		set tSC = ..StoreRowSourceMetadata(tClassName, tRowSources, tColumns)
		Quit:$$$ISERR(tSC)

		// --- Add service item to shared production ---
		set tSC = ..EnsureProductionExists()
		Quit:$$$ISERR(tSC)

		set tSC = ..AddServiceItem(pBody, tClassName, tDataSourceName, tMode)
		Quit:$$$ISERR(tSC)

		set pResult.compiled = 1

		// --- Start or update the production ---
		set tSC = ..StartOrUpdateProduction()
		Quit:$$$ISERR(tSC)
		set pResult.started = 1

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Generate and compile a v2 DataSource class using %Dictionary API.
/// Supports nested columns via %SerialObject classes for sub-folders.
/// pText and pSerialClasses are kept as output params for compatibility with Edit flow.
ClassMethod GenerateDataSourceTextV2(pBody As %DynamicObject, pColumns As %DynamicArray, pRowSources As %DynamicArray, pClassName As %String, pDataSourceName As %String, Output pText As %String, Output pSerialClasses) As %Status
{
	#dim tSC As %Status = $$$OK
	set pText = ""
	kill pSerialClasses
	set pSerialClasses = 0
	Try {
		// Determine default namespace from the first row source's child nodes
		set tFirstRS = pRowSources.%Get(0)
		set tChildren = tFirstRS.%Get("childNodes")
		set tDefaultNS = ..FindDefaultNamespace(tChildren)

		// Separate flat columns from nested columns and build folder tree
		kill tFolderColumns
		set tHasNesting = 0
		for i=0:1:pColumns.%Size()-1 {
			set tCol = pColumns.%Get(i)
			set tRelPath = tCol.%Get("relativePath")
			if '$IsObject($Get(tRelPath)) || (tRelPath.%Size() <= 1) continue
			set tFolderName = tRelPath.%Get(0)
			set tHasNesting = 1
			if '$Data(tFolderColumns(tFolderName)) {
				set tFolderColumns(tFolderName) = ##class(%DynamicArray).%New()
			}
			set tSubCol = ##class(%DynamicObject).%New()
			set tSubCol.displayName = tCol.%Get("displayName")
			set tSubCol.inferredType = tCol.%Get("inferredType")
			set tSubCol.leafName = tRelPath.%Get(tRelPath.%Size()-1)
			do tFolderColumns(tFolderName).%Push(tSubCol)
		}

		// Generate and compile serial object classes first
		if tHasNesting {
			set tSC = ..GenerateSerialClasses(pClassName, tDefaultNS, .tFolderColumns, .pSerialClasses)
			Quit:$$$ISERR(tSC)
		}

		// Create main class definition
		set tClassDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
		set tClassDef.Description = "Auto-generated OPC UA DataSource class (v2 row-source model)."
		set tClassDef.Super = "%Persistent,OPCUA.DataSource.Definition"

		do ..AddParameter(tClassDef, "OPCUADATASOURCE", pDataSourceName)
		do ..AddParameter(tClassDef, "OPCUDEFAULTANAMESPACE", tDefaultNS)
		do ..AddParameter(tClassDef, "OPCUAPIPELINEVERSION", 2)

		// Row metadata properties
		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "NodePath"
		set tProp.Type = "%String"
		do tProp.Parameters.SetAt(500, "MAXLEN")
		do tClassDef.Properties.Insert(tProp)

		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "ServerTimeStamp"
		set tProp.Type = "%TimeStamp"
		do tClassDef.Properties.Insert(tProp)

		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "SourceTimeStamp"
		set tProp.Type = "%TimeStamp"
		do tClassDef.Properties.Insert(tProp)

		// Generate column properties
		kill tEmittedFolders
		for i=0:1:pColumns.%Size()-1 {
			set tCol = pColumns.%Get(i)
			set tDisplayName = tCol.%Get("displayName")
			set tInferredType = tCol.%Get("inferredType")
			set tRelPath = tCol.%Get("relativePath")

			set tIsNested = $IsObject($Get(tRelPath)) && (tRelPath.%Size() > 1)
			if tIsNested {
				set tFolderName = tRelPath.%Get(0)
				if $Data(tEmittedFolders(tFolderName)) continue
				set tEmittedFolders(tFolderName) = 1

				set tSerialClassName = pClassName_"."_tFolderName_"Type"
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tFolderName, .tUsedNames)
				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
			set tProp.Name = tPropName
				set tProp.Type = tSerialClassName
				do tProp.Parameters.SetAt(tFolderName, "OPCUANODENAME")
				do tClassDef.Properties.Insert(tProp)
			} else {
				set tType = ..MapToPlainType(tInferredType)
				set tChildNS = tDefaultNS
				if i < tChildren.%Size() {
					set tChildNS = +tChildren.%Get(i).%Get("nodeNs")
				}
				set tLeafName = tDisplayName
				if $IsObject($Get(tRelPath)) && (tRelPath.%Size() = 1) {
					set tLeafName = tRelPath.%Get(0)
				}
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tLeafName, .tUsedNames)
				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
			set tProp.Name = tPropName
				set tProp.Type = tType
				do tProp.Parameters.SetAt(tLeafName, "OPCUANODENAME")
				if tChildNS '= tDefaultNS {
					do tProp.Parameters.SetAt(tChildNS, "OPCUANAMESPACE")
				}
				do tClassDef.Properties.Insert(tProp)
			}
		}

		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)
		set tSC = $System.OBJ.Compile(pClassName, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Generate and compile %SerialObject classes for nested folder columns using %Dictionary API.
ClassMethod GenerateSerialClasses(pMainClassName As %String, pDefaultNS As %Integer, ByRef pFolderColumns, Output pSerialClasses) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set pSerialClasses = 0

		set tFolderName = ""
		for {
			set tFolderName = $Order(pFolderColumns(tFolderName))
			if tFolderName = "" Quit

			set tSerialClassName = pMainClassName_"."_tFolderName_"Type"
			set tColumns = pFolderColumns(tFolderName)

			set tClassDef = ##class(%Dictionary.ClassDefinition).%New(tSerialClassName)
			set tClassDef.Description = "Auto-generated serial object for nested OPC UA folder: "_tFolderName
			set tClassDef.Super = "%SerialObject"
			set tClassDef.PropertyClass = "OPCUA.DataSource.PropertyClass"

			kill tUsedNames
			for i=0:1:tColumns.%Size()-1 {
				set tSubCol = tColumns.%Get(i)
				set tLeafName = tSubCol.%Get("leafName")
				set tType = ..MapToPlainType(tSubCol.%Get("inferredType"))
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tLeafName, .tUsedNames)

				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
				set tProp.Name = tPropName
				set tProp.Type = tType
				do tProp.Parameters.SetAt(tLeafName, "OPCUANODENAME")
				do tClassDef.Properties.Insert(tProp)
			}

			set tSC = tClassDef.%Save()
			$$$ThrowOnError(tSC)
			set tSC = $System.OBJ.Compile(tSerialClassName, "ck-d")
			$$$ThrowOnError(tSC)

			// Track for caller (pSerialClasses kept for Edit flow compatibility)
			set pSerialClasses = pSerialClasses + 1
			set pSerialClasses(pSerialClasses) = $LB(tSerialClassName, "")
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Store row source metadata in ^OPCUA.RowSource global for runtime use by row-source services.
/// Computes a column mask per row source: which union columns each RS has (by matching childNode relativePath keys).
/// Missing columns will be NULL at runtime.
/// Stores: $LB(rsCount, colCount, rsList, columnPaths, nestingSpec)
///   columnPaths = $LB("Temperature", "Humidity", "SubFolder/TargetNode") — leaf column path keys
///   nestingSpec = $LB($LB("leaf",1), $LB("leaf",2), $LB("serial",3,$LB($LB("leaf",1)))) — storage layout
ClassMethod StoreRowSourceMetadata(pClassName As %String, pRowSources As %DynamicArray, pColumns As %DynamicArray) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tRSCount = pRowSources.%Size()
		set tColCount = pColumns.%Size()

		// Build ordered column path key list for matching (uses relativePath if available)
		set tColumnPaths = ""
		for c=0:1:tColCount-1 {
			set tCol = pColumns.%Get(c)
			set tRelPath = tCol.%Get("relativePath")
			if $IsObject($Get(tRelPath)) && (tRelPath.%Size() > 0) {
				// Build path key from relativePath array: "SubFolder/TargetNode"
				set tPathKey = ""
				for rp=0:1:tRelPath.%Size()-1 {
					set:tPathKey'="" tPathKey = tPathKey_"/"
					set tPathKey = tPathKey_tRelPath.%Get(rp)
				}
			} else {
				set tPathKey = tCol.%Get("displayName")
			}
			set tColNames(c) = tPathKey
			set tColumnPaths = tColumnPaths _ $LB(tPathKey)
		}

		// Build row source list with column masks
		set tRSList = ""
		for i=0:1:tRSCount-1 {
			set tRS = pRowSources.%Get(i)
			set tPath = tRS.%Get("path")
			set tNodeNs = +tRS.%Get("nodeNs")
			set tNodeId = tRS.%Get("nodeId")
			set tNodeIdType = +tRS.%Get("nodeIdType")

			// Build a lookup: childNode relativePath key → child object
			set tChildren = tRS.%Get("childNodes")
			kill tChildMap
			for j=0:1:tChildren.%Size()-1 {
				set tChild = tChildren.%Get(j)
				set tChildRelPath = tChild.%Get("relativePath")
				if $IsObject($Get(tChildRelPath)) && (tChildRelPath.%Size() > 0) {
					set tChildKey = ""
					for rp=0:1:tChildRelPath.%Size()-1 {
						set:tChildKey'="" tChildKey = tChildKey_"/"
						set tChildKey = tChildKey_tChildRelPath.%Get(rp)
					}
				} else {
					set tChildKey = tChild.%Get("displayName")
				}
				set tChildMap(tChildKey) = tChild
			}

			// Build column mask and abs node refs by iterating union columns in order
			set tMask = ""
			set tAbsNodeRefs = ""
			for c=0:1:tColCount-1 {
				if $Data(tChildMap(tColNames(c))) {
					set tChild = tChildMap(tColNames(c))
					set tMask = tMask _ $LB(1)
					set tAbsNodeRefs = tAbsNodeRefs _ $LB($LB(+tChild.%Get("nodeNs"), tChild.%Get("nodeId"), +tChild.%Get("nodeIdType")))
				} else {
					set tMask = tMask _ $LB(0)
				}
			}

			set tRSList = tRSList _ $LB($LB(tPath, tNodeNs, tNodeId, tNodeIdType, tMask, tAbsNodeRefs))
		}

		// Build nesting spec: describes how flat leaf values map to the nested $LB storage layout
		// Each entry is either $LB("leaf", leafIndex) for flat columns,
		// or $LB("serial", storageSlot, innerSpec) for serial object groups
		set tNestingSpec = ""
		set tLeafIdx = 0
		kill tProcessedFolders
		set tHasNesting = 0
		for c=0:1:tColCount-1 {
			set tPath = tColNames(c)
			if tPath [ "/" {
				// Nested column
				set tFolderName = $Piece(tPath, "/", 1)
				set tHasNesting = 1
				if '$Data(tProcessedFolders(tFolderName)) {
					// Gather all leaf columns under this folder
					set tProcessedFolders(tFolderName) = 1
					set tInnerSpec = ""
					set tInnerIdx = 0
					for c2=0:1:tColCount-1 {
						set tPath2 = tColNames(c2)
						if $Piece(tPath2, "/", 1) = tFolderName {
							set tLeafIdx = tLeafIdx + 1
							set tInnerIdx = tInnerIdx + 1
							set tInnerSpec = tInnerSpec _ $LB($LB("leaf", tLeafIdx))
						}
					}
					set tNestingSpec = tNestingSpec _ $LB($LB("serial", tFolderName, tInnerSpec))
				}
			} else {
				// Flat column
				set tLeafIdx = tLeafIdx + 1
				set tNestingSpec = tNestingSpec _ $LB($LB("leaf", tLeafIdx))
			}
		}

		// Store: $LB(rowSourceCount, columnCount, rowSourceList, columnPaths, nestingSpec)
		if tHasNesting {
			set ^OPCUA.RowSource(pClassName) = $LB(tRSCount, tColCount, tRSList, tColumnPaths, tNestingSpec)
		} else {
			// Backward compatible: no extra elements for flat pipelines
			set ^OPCUA.RowSource(pClassName) = $LB(tRSCount, tColCount, tRSList)
		}

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
