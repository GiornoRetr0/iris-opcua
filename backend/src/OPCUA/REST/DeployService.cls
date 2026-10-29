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

/// The Portal category every pipeline we create belongs to, alongside the short
/// name of its schema. See <method>EnsureCategories</method>.
Parameter PipelineCategory = "OPCUA";

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
///   credentials       optional: the ID of an existing Ens.Config.Credentials entry
///   username, password   optional, instead of credentials: saved as a new entry
///                        <method>CredentialsId</method>(name), never in a setting
/// }
/// <p>Neither credentials nor username means an anonymous session, and no entry.
/// A password without a username is ignored, as an anonymous connect ignores it.</p>
ClassMethod BindExistingSchema(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deployed = 0
	set pResult.compiled = 0
	set pResult.started = 0
	set pResult.productionClass = ..#ProductionClass
	Try {
		set tSC = ..ValidateItemName(pBody.%Get("dataSourceName"))
		Quit:$$$ISERR(tSC)

		set tSchemaClass = pBody.%Get("schemaClass")

		if '##class(%Dictionary.CompiledClass).%ExistsId(tSchemaClass) {
			set tSC = ##class(OPCUA.REST.Error).NotFound("Schema '"_tSchemaClass_"' does not exist or is not compiled")
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

		// Which credentials the pipeline uses. Checked before the coverage check,
		// which has to connect the same way the pipeline will.
		set tSC = ..ResolveCredentials(pBody, .tCheckBody)
		Quit:$$$ISERR(tSC)

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
		set tSCUsable = ##class(OPCUA.REST.SchemaService).RequireUsableDevices(tCheckBody, tSchemaClass)
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

		// Config item names must stay unique. Checked here to fail fast, and again
		// under the edit lock in AddServiceItem.
		set tProd = ##class(Ens.Config.Production).%OpenId(..#ProductionClass)
		if $IsObject(tProd) && $IsObject(##class(OPCUA.REST.ProductionEdit).FindItem(tProd, tItemName)) {
			set tSC = ..DuplicateNameError(tItemName)
			Quit
		}
		kill tProd

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
ClassMethod AddServiceItem(pBody As %DynamicObject, pDSClassName As %String, pDSName As %String, pMode As %String, pDeviceNodePaths As %String) As %Status [ Internal ]
{
	#dim tSC As %Status = $$$OK
	Try {
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
		// Portal categories: every pipeline we create carries "OPCUA" plus the
		// short name of its schema, so the Production Configuration page groups
		// our pipelines away from the hand-authored Examples, and groups the
		// pipelines sharing a schema together. Purely organisational — nothing
		// reads these back.
		//
		// A caller that sends "categories" owns the list outright, including the
		// right to drop "OPCUA" or to send none at all — hence %IsDefined rather
		// than a truth test, which would silently re-add the defaults to an
		// intentionally empty list. Absent means "decide for me", which is what
		// the Portal-only path and older clients rely on.
		if pBody.%IsDefined("categories") {
			set tItem.Category = ..NormalizeCategories(pBody.%Get("categories"))
		} else {
			do ..EnsureCategories(tItem, pDSClassName)
		}
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

		// Credentials: an existing entry by ID, or a username (and password)
		// saved as a new entry below. Never a Username/Password setting, which
		// would put the password in the production class in plain text.
		set tCredId = pBody.%Get("credentials")
		set tUsername = pBody.%Get("username")
		set tNewCredId = ""
		if (tCredId = "") && (tUsername '= "") set (tCredId, tNewCredId) = ..CredentialsId(pDSName)
		do:tCredId'="" ..AddSetting(tItem, "Adapter", "Credentials", tCredId)
		// Refuse before taking the lock, so a missing privilege is the error the
		// caller sees.
		if (tNewCredId '= "") && '..CanWriteCredentials() {
			set tSC = ..NoCredentialsAccess("create credentials '"_tNewCredId_"'", "W")
			Quit
		}

		// Insert under the edit lock: reread the production, recheck the name,
		// create the entry, then one %Save and SaveToClass.
		set tSC = ##class(OPCUA.REST.ProductionEdit).Begin(.tProd, .tStamp)
		Quit:$$$ISERR(tSC)
		set tCreated = 0
		Try {
			if $IsObject(##class(OPCUA.REST.ProductionEdit).FindItem(tProd, pDSName)) {
				set tSC = ..DuplicateNameError(pDSName)
			} else {
				if tNewCredId '= "" {
					set tSC = ..CreateOwnedCredentials(tNewCredId, pDSName, tUsername, pBody.%Get("password"))
					set tCreated = $$$ISOK(tSC)
				}
				if $$$ISOK(tSC) {
					do tProd.Items.Insert(tItem)
					set tSC = ##class(OPCUA.REST.ProductionEdit).Commit(tProd, tStamp)
				}
			}
		} Catch (eEdit) {
			set tSC = eEdit.AsStatus()
		}
		// No pipeline, so no entry: take back the one just made for it, and say
		// so if that fails too.
		if $$$ISERR(tSC) && tCreated {
			set tSCUndo = ..DeleteOwnedCredentials(tNewCredId, pDSName)
			if $$$ISERR(tSCUndo) {
				set tSC = ##class(OPCUA.REST.Error).Make(500, "Pipeline not saved: "_##class(OPCUA.REST.Error).Text(tSC)_". The credentials '"_tNewCredId_"' made for it could not be removed: "_##class(OPCUA.REST.Error).Text(tSCUndo), tSC)
			}
		}
		do ##class(OPCUA.REST.ProductionEdit).End()

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// The <tt>Ens.Config.Credentials</tt> ID deploy uses for the entry it creates
/// for pipeline <var>pItemName</var>: <tt>OPCUA-</tt> plus the name.
///
/// Every character other than a letter, digit, dot, hyphen or underscore becomes
/// <tt>_</tt>, so the ID reads cleanly in the Portal's credentials list and can
/// never hold the <tt>||</tt> ID separator. The ID is at most 50 characters
/// (<tt>SystemName</tt>'s MAXLEN), and pipeline names run to 128, so a longer one
/// keeps its first 41 characters plus <tt>-</tt> and an 8-digit hex CRC of the
/// full name, which keeps names that differ only at the end apart.
///
/// Two pipeline names can still map to one ID ("A B" and "A_B"). Deploy then
/// refuses the second with 409, as it does for any taken ID.
ClassMethod CredentialsId(pItemName As %String) As %String
{
	set tKeep = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"
	set tId = "OPCUA-"
	for i=1:1:$Length(pItemName) {
		set tChar = $Extract(pItemName, i)
		set tId = tId_$Select(tKeep[tChar:tChar, 1:"_")
	}
	if $Length(tId) > ..#CredentialsIdMax {
		set tCrc = $ZConvert($ZHex($ZCRC($ZConvert(pItemName, "O", "UTF8"), 7)), "U")
		set tCrc = $Translate($Justify(tCrc, 8), " ", "0")
		set tId = $Extract(tId, 1, ..#CredentialsIdMax - 9)_"-"_tCrc
	}
	Quit tId
}

/// <tt>Ens.Config.Credentials.SystemName</tt>'s MAXLEN.
Parameter CredentialsIdMax = 50;

/// Check the body's credentials choice, and return in <var>pCheckBody</var> the
/// body the coverage check connects with: the caller's own, or, for an existing
/// entry, a copy carrying that entry's username and password.
///
/// 400 if <tt>credentials</tt> names no entry, or comes with a <tt>username</tt>
/// too. 403 if this IRIS account may not read the entry, or (with a
/// <tt>username</tt>) may not create one. Nothing is created here;
/// <method>AddServiceItem</method> does that.
ClassMethod ResolveCredentials(pBody As %DynamicObject, Output pCheckBody As %DynamicObject) As %Status
{
	set pCheckBody = pBody
	set tCredId = pBody.%Get("credentials")
	if tCredId = "" {
		if (pBody.%Get("username") '= "") && '..CanWriteCredentials() {
			Quit ..NoCredentialsAccess("create credentials for this pipeline", "W")
		}
		Quit $$$OK
	}
	if pBody.%Get("username") '= "" {
		Quit ##class(OPCUA.REST.Error).BadRequest("Send either 'credentials' (an existing credentials ID) or 'username' and 'password', not both.")
	}
	set tSC = ..ReadCredentials(tCredId, .tUser, .tPassword)
	Quit:$$$ISERR(tSC) tSC
	set pCheckBody = {}.%FromJSON(pBody.%ToJSON())
	do pCheckBody.%Set("username", tUser)
	do pCheckBody.%Set("password", tPassword)
	Quit $$$OK
}

/// The username and password in credentials entry <var>pId</var>, for a connect
/// made on the caller's behalf (deploy's and rebind's coverage checks).
///
/// The ID is matched as Ens matches it: case-insensitively, and "" or
/// <tt>none</tt> mean no credentials (an anonymous session). 400 if no entry
/// has the ID. 403 if this IRIS account cannot read stored passwords:
/// <tt>Ens.Config.Credentials</tt> then hands back an empty password with no
/// error, and the connect would fail with a misleading BadUserAccessDenied.
ClassMethod ReadCredentials(pId As %String, Output pUser As %String, Output pPassword As %String) As %Status
{
	set (pUser, pPassword) = ""
	Quit:(pId="")||($ZConvert(pId, "L")="none") $$$OK
	set tId = ..FindCredentialsId(pId)
	if tId = "" {
		Quit ##class(OPCUA.REST.Error).BadRequest("Credentials '"_pId_"' do not exist in namespace "_$Namespace_". Create them in the Management Portal (Interoperability > Configure > Credentials) first.")
	}
	if '..CanReadCredentials() {
		Quit ..NoCredentialsAccess("read the password in credentials '"_tId_"'", "R")
	}
	set tCred = ##class(Ens.Config.Credentials).%OpenId(tId, 0, .tSC)
	if '$IsObject(tCred) {
		Quit ##class(OPCUA.REST.Error).Make(500, "Cannot open credentials '"_tId_"'", tSC)
	}
	set pUser = tCred.Username, pPassword = tCred.Password
	Quit $$$OK
}

/// The stored ID of the credentials entry whose ID matches <var>pId</var> in any
/// case, as <tt>Ens.Config.Credentials.GetCredentialsObj</tt> matches it; ""
/// when there is none.
ClassMethod FindCredentialsId(pId As %String) As %String
{
	Quit:pId="" ""
	set tLower = $ZConvert(pId, "L"), tId = ""
	&sql(SELECT TOP 1 SystemName INTO :tId FROM Ens_Config.Credentials WHERE LOWER(SystemName) = :tLower)
	Quit $Select(SQLCODE=0:tId, 1:"")
}

/// Whether this process may read stored credentials passwords. Ens keeps them in
/// <tt>^Ens.SecondaryData.Password</tt>, in the namespace's secondary database,
/// and reads them with no privilege check of its own, so a reference that
/// raises &lt;PROTECT&gt; is the only reliable sign. The Portal also requires
/// %Ens_Credentials to view credentials, so that is checked too.
ClassMethod CanReadCredentials() As %Boolean
{
	Quit:'$System.Security.Check(..#CredentialsResource, "R") 0
	try {
		set tOK = ($Data(^Ens.SecondaryData.Password) >= 0)
	} catch {
		set tOK = 0
	}
	Quit tOK
}

/// Whether this process may create and delete credentials entries:
/// %Ens_Credentials:W, which <tt>%SYS.Ensemble</tt> checks before storing or
/// removing a password.
ClassMethod CanWriteCredentials() As %Boolean [ CodeMode = expression ]
{
$System.Security.Check(..#CredentialsResource, "W")
}

/// The resource that guards credentials entries.
Parameter CredentialsResource = "%Ens_Credentials";

/// 403 for a credentials operation this IRIS account may not do.
/// <var>pWhat</var> describes it ("read the password in credentials 'X'"),
/// <var>pPermission</var> is the permission it needs on %Ens_Credentials.
ClassMethod NoCredentialsAccess(pWhat As %String, pPermission As %String) As %Status
{
	Quit ##class(OPCUA.REST.Error).Forbidden("IRIS user '"_$Username_"' cannot "_pWhat_": that needs the "_..#CredentialsResource_" resource ("_pPermission_"), as SuperUser has. Sign the console in as a developer with SuperUser rights, or have an administrator create the credentials in the Management Portal and deploy with 'credentials'.")
}

/// Create credentials entry <var>pId</var> for pipeline <var>pItemName</var> and
/// record that deploy made it, in <tt>^OPCUA.OwnedCredentials(pId)</tt>, so that
/// deleting the pipeline deletes it and nothing else.
///
/// An existing entry is never overwritten, whoever made it: 409.
ClassMethod CreateOwnedCredentials(pId As %String, pItemName As %String, pUsername As %String, pPassword As %String) As %Status [ Private ]
{
	// Ens matches credentials IDs in any case, so a taken ID in another case is
	// taken.
	set tTaken = ..FindCredentialsId(pId)
	if tTaken '= "" {
		Quit ##class(OPCUA.REST.Error).Conflict("Credentials '"_tTaken_"' already exist, and are never overwritten. Choose a different pipeline name, or send 'credentials': '"_tTaken_"' to use them.")
	}
	Quit:'..CanWriteCredentials() ..NoCredentialsAccess("create credentials '"_pId_"'", "W")
	set tSC = ##class(Ens.Config.Credentials).SetCredential(pId, pUsername, pPassword, 0)
	Quit:$$$ISERR(tSC) ##class(OPCUA.REST.Error).Make(500, "Could not create credentials '"_pId_"'", tSC)
	set ^OPCUA.OwnedCredentials(pId) = pItemName
	Quit $$$OK
}

/// Delete credentials entry <var>pId</var> if, and only if, deploy created it for
/// pipeline <var>pItemName</var>. Any other entry is left alone. Returns OK when
/// there is nothing of ours to delete.
ClassMethod DeleteOwnedCredentials(pId As %String, pItemName As %String) As %Status
{
	Quit:'..OwnsCredentials(pId, pItemName) $$$OK
	Quit:'..CanWriteCredentials() ..NoCredentialsAccess("delete credentials '"_pId_"'", "W")
	if ##class(Ens.Config.Credentials).%ExistsId(pId) {
		set tSC = ##class(Ens.Config.Credentials).%DeleteId(pId)
		Quit:$$$ISERR(tSC) tSC
	}
	kill ^OPCUA.OwnedCredentials(pId)
	Quit $$$OK
}

/// Whether deploy created credentials entry <var>pId</var> for pipeline
/// <var>pItemName</var>.
ClassMethod OwnsCredentials(pId As %String, pItemName As %String) As %Boolean
{
	Quit:pId="" 0
	Quit $Get(^OPCUA.OwnedCredentials(pId))=pItemName
}

/// The refusal for a pipeline name that is already taken.
ClassMethod DuplicateNameError(pName As %String) As %Status [ Private ]
{
	Quit ##class(OPCUA.REST.Error).Conflict("A pipeline named '"_pName_"' already exists. Choose a different name.")
}

/// Turn a caller-supplied category list into the comma-delimited string
/// <tt>Ens.Config.Item.Category</tt> expects.
///
/// Accepts either a JSON array (what the console sends) or an already-joined
/// comma string, so a hand-rolled request works too. Entries are trimmed, blanks
/// dropped, and duplicates removed case-insensitively — the Portal treats
/// categories as display strings, so "opcua" and "OPCUA" would otherwise show as
/// two groups meaning one thing. The first spelling of a repeated name wins.
///
/// Commas inside a single entry are the one thing that cannot survive: the field
/// is comma-delimited, so an entry containing one would silently split into two
/// categories. They are stripped rather than escaped, because a category is a
/// short label and there is nothing to escape *to*.
ClassMethod NormalizeCategories(pValue) As %String
{
	set tOut = ""
	if '$IsObject(pValue) {
		// Comma string (or empty): reuse the same splitting path as an array by
		// walking the pieces.
		for i=1:1:$Length(pValue, ",") {
			set tCat = $ZStrip($Piece(pValue, ",", i), "<>WC")
			continue:tCat=""
			continue:$Data(tSeen($ZConvert(tCat, "U")))
			set tSeen($ZConvert(tCat, "U")) = ""
			set tOut = $Select(tOut="":tCat, 1:tOut_","_tCat)
		}
		Quit tOut
	}

	set tIter = pValue.%GetIterator()
	while tIter.%GetNext(.tKey, .tVal) {
		set tCat = $ZStrip($Translate($Get(tVal), ","), "<>WC")
		continue:tCat=""
		continue:$Data(tSeen($ZConvert(tCat, "U")))
		set tSeen($ZConvert(tCat, "U")) = ""
		set tOut = $Select(tOut="":tCat, 1:tOut_","_tCat)
	}
	Quit tOut
}

/// The categories a freshly deployed pipeline gets when the caller does not name
/// them: <tt>OPCUA</tt> plus the schema's short name. Exposed so the console can
/// prefill its editor with exactly what the backend would have chosen.
ClassMethod DefaultCategories(pSchemaClass As %String) As %String
{
	set tSchemaName = $Piece(pSchemaClass, ".", *)
	set tOut = ..#PipelineCategory
	if tSchemaName '= "" set tOut = tOut_","_tSchemaName
	Quit tOut
}

/// Stamp a config item's Portal categories: <tt>OPCUA</tt> plus the short name of
/// the schema it is bound to.
///
/// <tt>Ens.Config.Item.Category</tt> is a comma-delimited string, and
/// <tt>Ens.Config.Production:EnumerateCategories</tt> strips whitespace around each
/// piece — so the Portal's category filter sees these as two separate groups.
/// Categories are organisational only; nothing in the runtime reads them back, so a
/// missing category is cosmetic rather than a broken pipeline.
///
/// Existing categories are kept, and neither name is added twice, so this is safe
/// to call on an item that has already been stamped.
ClassMethod EnsureCategories(pItem As Ens.Config.Item, pSchemaClass As %String)
{
	set tSchemaName = $Piece(pSchemaClass, ".", *)
	set tWanted = $LB(..#PipelineCategory)
	// A schema class is always present on a deploy, but do not stamp an empty
	// piece if one ever is not — an empty category is dropped by the Portal anyway.
	if tSchemaName '= "" set tWanted = tWanted_$LB(tSchemaName)

	// Index what is already there, case-insensitively: the Portal treats
	// categories as display strings, so "opcua" and "OPCUA" would show as two
	// groups meaning one thing.
	set tExisting = pItem.Category
	for i=1:1:$Length(tExisting, ",") {
		set tCat = $ZStrip($Piece(tExisting, ",", i), "<>WC")
		continue:tCat=""
		set tHave($ZConvert(tCat, "U")) = ""
	}

	for i=1:1:$ListLength(tWanted) {
		set tCat = $ListGet(tWanted, i)
		continue:$Data(tHave($ZConvert(tCat, "U")))
		set tExisting = $Select(tExisting="":tCat, 1:tExisting_","_tCat)
		set tHave($ZConvert(tCat, "U")) = ""
	}

	set pItem.Category = tExisting
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
/// Refuses, without stopping anything, while another production holds the
/// namespace (see <method>CheckNoOtherProduction</method>).
ClassMethod StartOrUpdateProduction() As %Status
{
	set tSC = ##class(Ens.Director).GetProductionStatus(.tProdName, .tState)
	Quit:$$$ISERR(tSC) tSC

	// State: $$$eProductionStateRunning = 1, Stopped = 2, Suspended = 3, Troubled = 4
	if (tProdName = ..#ProductionClass) && (tState = 1) {
		// Our production is already running — update it to pick up the new item
		Quit ##class(Ens.Director).UpdateProduction()
	}

	// Never stop someone else's production to make room for ours
	set tSC = ..CheckNoOtherProduction()
	Quit:$$$ISERR(tSC) tSC

	// Start our production
	Quit ##class(Ens.Director).StartProduction(..#ProductionClass)
}

/// 400 unless <var>pName</var> ("" means the default, which is valid) can name a
/// config item: Ens.Config.Item allows at most 128 characters and refuses some
/// separators (<method>Ens.Config.Item.CheckForIllegalCharacters</method>). Checked
/// up front so the caller gets a readable 400, not a failed save.
ClassMethod ValidateItemName(pName As %String) As %Status
{
	Quit:pName="" $$$OK
	if $Length(pName) > 128 {
		Quit ##class(OPCUA.REST.Error).BadRequest("Pipeline name is too long: "_$Length(pName)_" characters, at most 128.")
	}
	set tSC = ##class(Ens.Config.Item).%New().CheckForIllegalCharacters(pName)
	if $$$ISERR(tSC) {
		do $System.Status.DecomposeStatus(tSC, .tErr)
		Quit ##class(OPCUA.REST.Error).BadRequest("Pipeline name '"_pName_"' is not valid: "_$Get(tErr(1, "param", 1), $System.Status.GetOneErrorText(tSC))_".")
	}
	Quit $$$OK
}

/// Error if a production other than ours holds this namespace.
///
/// A namespace runs one production at a time, so ours cannot start while another
/// is running, suspended or troubled. That one may belong to someone else, so it
/// is reported, not stopped.
ClassMethod CheckNoOtherProduction() As %Status
{
	set tSC = ##class(Ens.Director).GetProductionStatus(.tProdName, .tState)
	Quit:$$$ISERR(tSC) tSC
	if (tProdName = "") || (tProdName = ..#ProductionClass) Quit $$$OK

	// State: Running = 1, Suspended = 3, Troubled = 4
	set tStateText = $Case(tState, 1:"running", 3:"suspended", 4:"troubled", :"")
	if tStateText = "" Quit $$$OK

	Quit ##class(OPCUA.REST.Error).Conflict("Production '"_tProdName_"' is "_tStateText_" in namespace "_$Namespace_". A namespace runs one production at a time, and pipelines run in '"_..#ProductionClass_"'. Stop '"_tProdName_"' first; it was not changed.")
}

}
