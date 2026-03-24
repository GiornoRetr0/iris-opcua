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
ClassMethod Deploy(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
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

	if pMode = "subscription" {
		set tServiceClass = "OPCUA.Service.TCPSubscriptionService"
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
ClassMethod WriteAndCompile(pClassName As %String, pText As %String) As %Status [ Private ]
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

}
