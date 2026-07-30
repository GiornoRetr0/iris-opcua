Include %occInclude

/// Deploy an OPC UA data pipeline: create a device schema, bind devices to it,
/// add a business service item to the shared production, compile, and start.
/// Uses a single shared production (OPCUA.Pipeline.Production) where each
/// pipeline is a separate business service item.
///
/// Schema *generation* belongs to <class>OPCUA.REST.SchemaService</class>; this
/// class owns device *binding* and the production wiring. A deploy is therefore
/// "create a schema, then bind devices to it" — the two halves are separately
/// usable, which is what lets a schema exist without any pipeline.
Class OPCUA.REST.DeployService
{

/// The shared production class that holds all pipeline service items.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Deploy a complete pipeline from the wizard. All deploys use the v2
/// row-source model (columns + rowSources); see DeployV2().
ClassMethod Deploy(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set tRS = pBody.%Get("rowSources")
	if '$IsObject($Get(tRS)) || (tRS.%Size() = 0) {
		set pResult = {}
		set pResult.deployed = 0
		set pResult.compiled = 0
		set pResult.started = 0
		set pResult.productionClass = ..#ProductionClass
		Quit $$$ERROR($$$GeneralError, "Deploy request must include a 'rowSources' array (v2 row-source model)")
	}
	Quit ..DeployV2(pBody, .pResult)
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

		// All deploys use the v2 row-source runtime services.
		if pMode = "subscription" {
			set tServiceClass = "OPCUA.Service.TCPSubscriptionRowSourceService"
		} else {
			set tServiceClass = "OPCUA.Service.TCPPollingRowSourceService"
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

		// The device list lives in the config item, so it is visible and editable
		// in the Management Portal — adding a device is a one-line edit here.
		do ..AddSetting(tItem, "Adapter", "DeviceNodePaths", ..BuildDeviceNodePaths(pBody.%Get("rowSources")))

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

/// Render the wizard's row sources as a DeviceNodePaths setting value.
///
/// One line per device in OPC UA NodeId form, labelled with the row source's
/// path so the NodePath column reads as the user's tree selection did.
ClassMethod BuildDeviceNodePaths(pRowSources As %DynamicArray) As %String
{
	set tOut = ""
	Quit:'$IsObject($Get(pRowSources)) tOut

	for i=0:1:pRowSources.%Size()-1 {
		set tRS = pRowSources.%Get(i)
		set tNodeId = tRS.%Get("nodeId")
		continue:tNodeId=""

		// nodeIdType 0 = numeric, 3 = string (see OPCUA.Constants)
		set tIdType = +tRS.%Get("nodeIdType")
		set tKind = $Select(tIdType=0:"i=", 1:"s=")

		set tLine = "ns="_(+tRS.%Get("nodeNs"))_";"_tKind_tNodeId

		// Label keeps the NodePath column value stable across this change.
		set tPath = tRS.%Get("path")
		set:tPath'="" tLine = tLine_"|"_tPath

		set tOut = tOut_$Select(tOut="":"", 1:$Char(10))_tLine
	}
	Quit tOut
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

// ==================== v2 Row-Source Pipeline Deploy ====================

/// Deploy a v2 pipeline with multiple row sources sharing the same column schema.
/// Produces one DataSource class, one service item, one table — multiple rows per poll.
///
/// Internally this is two independent steps — <method>CreateSchema</method> then
/// <method>BindDevices</method> — which is what makes standalone schema creation
/// possible. The request payload and response envelope are unchanged.
ClassMethod DeployV2(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deployed = 0
	set pResult.compiled = 0
	set pResult.started = 0
	set pResult.productionClass = ..#ProductionClass
	Try {
		set tSC = ..ValidateDeployRequest(pBody, .tColumns, .tRowSources, .tClassName, .tDataSourceName, .tMode)
		Quit:$$$ISERR(tSC)

		// --- Step 1: the schema (no production side effects) ---
		set tSC = ..CreateSchema(pBody, tColumns, tRowSources, tClassName, tDataSourceName)
		Quit:$$$ISERR(tSC)

		set pResult.deployed = 1
		set pResult.dataSourceClass = tClassName
		set pResult.tableName = ##class(OPCUA.REST.SchemaService).TableName(tClassName)
		set pResult.serviceItemName = tDataSourceName

		// --- Step 2: bind devices and wire up the production ---
		set tSC = ..BindDevices(pBody, tClassName, tDataSourceName, tMode, tColumns, tRowSources)
		Quit:$$$ISERR(tSC)

		set pResult.compiled = 1

		set tSC = ..StartOrUpdateProduction()
		Quit:$$$ISERR(tSC)
		set pResult.started = 1

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Validate a wizard deploy request and normalise its key fields.
ClassMethod ValidateDeployRequest(pBody As %DynamicObject, Output pColumns, Output pRowSources, Output pClassName As %String, Output pDataSourceName As %String, Output pMode As %String) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set pRowSources = pBody.%Get("rowSources")
		set pColumns = pBody.%Get("columns")

		if '$IsObject($Get(pColumns)) || (pColumns.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No columns defined")
			Quit
		}

		if '$IsObject($Get(pRowSources)) || (pRowSources.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No row sources defined")
			Quit
		}

		set pClassName = pBody.%Get("className")
		if pClassName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing className")
			Quit
		}

		set pDataSourceName = pBody.%Get("dataSourceName")
		if pDataSourceName = "" set pDataSourceName = $Piece(pClassName, ".", *)

		set pMode = pBody.%Get("mode")
		if (pMode '= "polling") && (pMode '= "subscription") set pMode = "polling"

		// Check if class already exists
		if ##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
			set tSC = $$$ERROR($$$GeneralError, "Class '"_pClassName_"' already exists. Choose a different name.")
			Quit
		}

		// Check if a service item with the same name already exists in the production.
		// Config-item names must be unique: a duplicate would shadow the existing
		// pipeline at runtime (only one DataSourceClass is read) and make name-keyed
		// toggle/edit/delete ambiguous, orphaning the other DataSource class.
		if ##class(%Dictionary.ClassDefinition).%ExistsId(..#ProductionClass) {
			set tExistingProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
			if $IsObject(tExistingProd) {
				set tDupItem = tExistingProd.FindItemByConfigName(pDataSourceName, .tDupSC)
				if $IsObject(tDupItem) {
					set tSC = $$$ERROR($$$GeneralError, "A pipeline named '"_pDataSourceName_"' already exists. Choose a different name.")
					Quit
				}
			}
		}

		// Validate row sources have correct child count
		set tColCount = pColumns.%Size()
		for iRS=0:1:pRowSources.%Size()-1 {
			set tRS = pRowSources.%Get(iRS)
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
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Step 1 of a deploy: create and compile the device schema.
/// Touches no production and writes no device metadata — exactly what
/// <class>OPCUA.REST.SchemaService</class> does when called on its own.
ClassMethod CreateSchema(pBody As %DynamicObject, pColumns As %DynamicArray, pRowSources As %DynamicArray, pClassName As %String, pDataSourceName As %String) As %Status [ Private ]
{
	Quit ..GenerateDataSourceTextV2(pBody, pColumns, pRowSources, pClassName, pDataSourceName, .tDSText, .tSerialClasses)
}

/// Step 2 of a deploy: bind devices to an existing schema and add the service item.
///
/// The binding is entirely a config-item setting — AddServiceItem writes
/// DeviceNodePaths — so there is no metadata global to maintain.
ClassMethod BindDevices(pBody As %DynamicObject, pClassName As %String, pDataSourceName As %String, pMode As %String, pColumns As %DynamicArray, pRowSources As %DynamicArray) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..EnsureProductionExists()
		Quit:$$$ISERR(tSC)

		set tSC = ..AddServiceItem(pBody, pClassName, pDataSourceName, pMode)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Generate and compile a v2 DataSource class (schema) for a wizard deploy.
///
/// Schema generation itself lives in <class>OPCUA.REST.SchemaService</class> —
/// this wrapper exists to translate the wizard's row-source-shaped request into
/// the schema-shaped one, by deriving the default namespace and the per-column
/// namespace overrides from the first row source's browsed child nodes.
///
/// pText and pSerialClasses are kept as output params for compatibility with the
/// Edit flow.
ClassMethod GenerateDataSourceTextV2(pBody As %DynamicObject, pColumns As %DynamicArray, pRowSources As %DynamicArray, pClassName As %String, pDataSourceName As %String, Output pText As %String, Output pSerialClasses) As %Status
{
	#dim tSC As %Status = $$$OK
	set pText = ""
	kill pSerialClasses
	set pSerialClasses = 0
	Try {
		// Namespaces come from the first row source's browsed children: the most
		// common one becomes the class default, and any column whose node sits in
		// a different namespace gets an explicit OPCUANAMESPACE override.
		set tFirstRS = pRowSources.%Get(0)
		set tChildren = tFirstRS.%Get("childNodes")
		set tDefaultNS = ##class(OPCUA.REST.SchemaService).FindDefaultNamespace(tChildren)

		kill tColNS
		for i=0:1:pColumns.%Size()-1 {
			if i < tChildren.%Size() {
				set tColNS(i) = +tChildren.%Get(i).%Get("nodeNs")
			}
		}

		set tSC = ##class(OPCUA.REST.SchemaService).GenerateSchemaClass(pClassName, pDataSourceName, pColumns, tDefaultNS, .tColNS, .pSerialClasses)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

}
