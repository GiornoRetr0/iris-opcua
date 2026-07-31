Include %occInclude

/// Bind devices to an existing device schema: add a business service item to the
/// shared production (OPCUA.Pipeline.Production), where each pipeline is a
/// separate service item.
///
/// This class generates nothing. Schemas are created by
/// <class>OPCUA.REST.SchemaService</class>, and a deploy binds devices to one
/// that already exists — which is what lets a schema outlive any single pipeline
/// and back several at once.
///
/// A deploy is a pure configuration write: the new item is created
/// <b>disabled</b> and the production is not started. Collecting real data into a
/// real table is a decision of its own, so it is left to an explicit start
/// (<method>OPCUA.REST.PipelineService.Toggle</method>, or the Portal) once the
/// operator has looked the pipeline over.
Class OPCUA.REST.DeployService
{

/// The shared production class that holds all pipeline service items.
Parameter ProductionClass = "OPCUA.Pipeline.Production";

/// Deploy a pipeline: <tt>{schemaClass, devices, ...}</tt>.
/// See <method>BindExistingSchema</method>.
ClassMethod Deploy(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	if pBody.%Get("schemaClass") = "" {
		set pResult = {}
		set pResult.deployed = 0
		set pResult.compiled = 0
		set pResult.started = 0
		set pResult.productionClass = ..#ProductionClass
		Quit $$$ERROR($$$GeneralError, "Deploy request must include 'schemaClass'. Create the schema first with POST /schemas.")
	}
	Quit ..BindExistingSchema(pBody, .pResult)
}

/// Bind devices to an existing schema, generating nothing.
///
/// Adding a pipeline over a schema that already exists costs one config item and
/// no compilation.
///
/// Body: {
///   schemaClass       required, must be an OPCUA.DataSource.DeviceSchema subclass
///   devices           required, newline-separated nodepaths (DeviceNodePaths form)
///   dataSourceName    config item name; defaults to the schema's short name
///   mode              "polling" (default) or "subscription"
///   url               OPC UA endpoint
///   callInterval      polling mode, seconds (default 5)
///   publishingInterval / samplingInterval / queueSize   subscription mode, ms
///   securityMode + clientURI, certPath, keyPath, trustDir, crlDir   for mode 3
///   username, password   optional credentials
/// }
ClassMethod BindExistingSchema(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deployed = 0
	set pResult.compiled = 0
	set pResult.started = 0
	set pResult.productionClass = ..#ProductionClass
	Try {
		set tSchemaClass = pBody.%Get("schemaClass")

		if '##class(%Dictionary.CompiledClass).%ExistsId(tSchemaClass) {
			set tSC = $$$ERROR($$$GeneralError, "Schema '"_tSchemaClass_"' does not exist or is not compiled")
			Quit
		}
		if '##class(OPCUA.REST.SchemaService).IsSchema(tSchemaClass) {
			set tSC = $$$ERROR($$$GeneralError, "Class '"_tSchemaClass_"' is not an OPCUA.DataSource.DeviceSchema subclass")
			Quit
		}

		set tDevices = pBody.%Get("devices")
		if tDevices = "" set tDevices = pBody.%Get("deviceNodePaths")
		if tDevices = "" {
			set tSC = $$$ERROR($$$GeneralError, "No devices supplied — provide 'devices' as newline-separated nodepaths")
			Quit
		}

		// Fail early on an unusable device list rather than at connect time.
		// Report the per-line reasons, which are far more actionable than the summary.
		set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tDevices, .tParsed, .tParseErrors)
		if $$$ISERR(tSC) {
			set tMsg = "No usable device entries in 'devices'"
			for i=1:1:$LL(tParseErrors) { set tMsg = tMsg_" — "_$LI(tParseErrors, i) }
			set tSC = $$$ERROR($$$GeneralError, tMsg)
			Quit
		}

		// Every device must actually contribute a column. A device that browses to
		// zero matches writes nothing but NULLs for the life of the pipeline, so
		// catch it here rather than letting it quietly pad the table.
		set tSCUsable = ##class(OPCUA.REST.SchemaService).RequireUsableDevices(pBody, tSchemaClass)
		if $$$ISERR(tSCUsable) {
			set tSC = tSCUsable
			Quit
		}

		set tItemName = pBody.%Get("dataSourceName")
		if tItemName = "" set tItemName = $Piece(tSchemaClass, ".", *)

		set tMode = pBody.%Get("mode")
		if (tMode '= "polling") && (tMode '= "subscription") set tMode = "polling"

		set tSC = ..EnsureProductionExists()
		Quit:$$$ISERR(tSC)

		// Config item names must stay unique — see AddServiceItem's callers.
		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if $IsObject(tProd) {
			set tDup = tProd.FindItemByConfigName(tItemName, .tDupSC)
			if $IsObject(tDup) {
				set tSC = $$$ERROR($$$GeneralError, "A pipeline named '"_tItemName_"' already exists. Choose a different name.")
				Quit
			}
		}

		set tSC = ..AddServiceItem(pBody, tSchemaClass, tItemName, tMode, tDevices)
		Quit:$$$ISERR(tSC)

		set pResult.deployed = 1
		set pResult.compiled = 1
		set pResult.dataSourceClass = tSchemaClass
		set pResult.tableName = ##class(OPCUA.REST.SchemaService).TableName(tSchemaClass)
		set pResult.serviceItemName = tItemName
		set pResult.deviceCount = $LL(tParsed)

		// Deliberately not started. `started` stays 0 so a caller can see that
		// the pipeline exists but is not yet collecting.
		set pResult.enabled = 0

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
///
/// pDeviceNodePaths is used verbatim as the DeviceNodePaths setting; the caller
/// has already parsed and validated it.
ClassMethod AddServiceItem(pBody As %DynamicObject, pDSClassName As %String, pDSName As %String, pMode As %String, pDeviceNodePaths As %String) As %Status [ Private ]
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
		// Created switched off. Deploying is configuring; polling a live server and
		// writing rows is a separate, explicit act — so the operator gets a chance
		// to review the pipeline before it touches anything.
		set tItem.Enabled = 0
		set tItem.LogTraceEvents = 1

		// Add adapter settings
		do ..AddSetting(tItem, "Adapter", "DataSourceClass", pDSClassName)
		do ..AddSetting(tItem, "Adapter", "URL", pBody.%Get("url"))

		// The device list lives in the config item, so it is visible and editable
		// in the Management Portal — adding a device is a one-line edit here.
		do ..AddSetting(tItem, "Adapter", "DeviceNodePaths", pDeviceNodePaths)

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

}
