Include %occInclude

/// Create and manage device schemas independently of any pipeline
/// (PRD "Baustein 1", §4.9).
///
/// A schema is a compiled subclass of <class>OPCUA.DataSource.DeviceSchema</class>
/// describing ONE device type: its columns and the OPC UA node names they resolve
/// against. Creating one has no production, service-item or device-binding side
/// effects — binding devices to a schema is a separate act, performed either by
/// <class>OPCUA.REST.DeployService</class> or by hand in the Management Portal.
///
/// This class owns all schema *generation*; DeployService owns device *binding*.
Class OPCUA.REST.SchemaService
{

/// Default package for generated schemas, matching the wizard's convention.
Parameter DefaultPackage = "OPCUA.DS";

// ==================== REST entry points ====================

/// POST /schemas — create a schema from a column list.
///
/// Body: {
///   className | name    target class ("OPCUA.DS.AirConditioner", or "AirConditioner"
///                       combined with packagePath)
///   packagePath          optional package when only `name` is given
///   dataSourceName       optional OPCUADATASOURCE value (defaults to the short name)
///   defaultNamespace     optional OPC UA namespace index for columns that omit one
///   columns[]            { displayName, inferredType, relativePath[], nodeNs }
///   includeServerTimestamp  optional, default true. false types every column as an
///                       OPCUA.Types.NoServerTS measurement, so the table has no
///                       *_ServerTS columns
/// }
///
/// Deliberately touches no production and writes no device metadata.
ClassMethod Create(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.created = 0
	Try {
		set tColumns = pBody.%Get("columns")
		if '$IsObject($Get(tColumns)) || (tColumns.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "No columns defined")
			Quit
		}

		set tSC = ..ResolveClassName(pBody, .tClassName)
		Quit:$$$ISERR(tSC)

		set tDataSourceName = pBody.%Get("dataSourceName")
		if tDataSourceName = "" set tDataSourceName = $Piece(tClassName, ".", *)

		if ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
			set tSC = ##class(OPCUA.REST.Error).Conflict("Class '"_tClassName_"' already exists. Choose a different name.")
			Quit
		}

		// Namespaces come from the columns themselves when creating a schema
		// standalone (the wizard deploy path supplies them from browsed nodes).
		set tDefaultNS = pBody.%Get("defaultNamespace")
		if tDefaultNS = "" {
			set tDefaultNS = ..FindDefaultNamespace(tColumns)
		} else {
			set tDefaultNS = +tDefaultNS
		}
		kill tColNS
		for i=0:1:tColumns.%Size()-1 {
			set tNS = tColumns.%Get(i).%Get("nodeNs")
			set:tNS'="" tColNS(i) = +tNS
		}

		// JSON false arrives as 0; absent means the default, true.
		set tIncludeServerTS = pBody.%Get("includeServerTimestamp")
		set tIncludeServerTS = $Case($ZConvert(tIncludeServerTS, "L"), "":1, "false":0, "0":0, :1)

		set tSC = ..GenerateSchemaClass(tClassName, tDataSourceName, tColumns, tDefaultNS, .tColNS, .tSerialClasses, tIncludeServerTS)
		Quit:$$$ISERR(tSC)

		set pResult.created = 1
		set pResult.schemaClass = tClassName
		set pResult.dataSourceName = tDataSourceName
		set pResult.tableName = ..TableName(tClassName)
		set pResult.columnCount = tColumns.%Size()
		set pResult.serialClasses = $Get(tSerialClasses, 0)
		do pResult.%Set("includeServerTimestamp", tIncludeServerTS, "boolean")

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// GET /schemas — list every compiled schema with its column count, table name,
/// and the pipelines currently bound to it.
ClassMethod List(pBody As %DynamicObject, Output pResult As %DynamicArray) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = []
	Try {
		set tSC = ..MapSchemaUsage(.tUsage)
		Quit:$$$ISERR(tSC)

		set tRS = ##class(%ResultSet).%New("%Dictionary.ClassDefinition:SubclassOf")
		set tSC = tRS.Execute("OPCUA.DataSource.DeviceSchema")
		Quit:$$$ISERR(tSC)

		while tRS.Next() {
			set tClass = tRS.Data("Name")
			continue:tClass="OPCUA.DataSource.DeviceSchema"
			// Skip abstract classes — they cannot back a pipeline.
			continue:$$$comClassKeyGet(tClass,$$$cCLASSabstract)

			// One unreadable schema must not hide the rest: it is listed with
			// its columnsError.
			set tItem = ..DescribeSchema(tClass, 0)
			set tItem.usedBy = ..UsageArray(.tUsage, tClass)
			do pResult.%Push(tItem)
		}
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// GET /schemas/:name — column detail for one schema, used to drive
/// device-binding validation in the UI.
ClassMethod Get(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	Try {
		set tSC = ..RequireSchema(pBody, .tClassName)
		Quit:$$$ISERR(tSC)

		set tSC = ..MapSchemaUsage(.tUsage)
		Quit:$$$ISERR(tSC)

		set pResult = ..DescribeSchema(tClassName, 1, .tSC)
		if $$$ISERR(tSC) {
			set tSC = ##class(OPCUA.REST.Error).Make(500, "Cannot read the columns of schema '"_tClassName_"'", tSC)
			Quit
		}
		set pResult.usedBy = ..UsageArray(.tUsage, tClassName)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// DELETE /schemas/:name — delete a schema and its generated serial subclasses.
/// Refuses while any production config item still references it.
ClassMethod Delete(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.deleted = 0
	Try {
		set tSC = ..RequireSchema(pBody, .tClassName)
		Quit:$$$ISERR(tSC)

		set tSC = ..MapSchemaUsage(.tUsage)
		Quit:$$$ISERR(tSC)

		// Check if schema is in use in any production
		set tUsageList = ""
		set tProdClass = ""
		for {
			set tProdClass = $Order(tUsage(tClassName, tProdClass))
			quit:tProdClass=""

			set tItemName = ""
			for {
				set tItemName = $Order(tUsage(tClassName, tProdClass, tItemName))
				quit:tItemName=""

				set tEntry = tItemName_" ("_tProdClass_")"
				set tUsageList = tUsageList_$Select(tUsageList="":"", 1:", ")_tEntry
			}
		}

		if tUsageList '= "" {
			set tSC = ##class(OPCUA.REST.Error).Conflict("Schema '"_tClassName_"' is still used by: "_tUsageList)
			Quit
		}

		// Remove the rows first: deleting the class leaves its data global, whose
		// name comes from the class name, so a new schema with the same name would
		// inherit them under a different column layout. %KillExtent, not the "e"
		// delete flag: that deletes row by row, and refuses if any row won't open.
		set tSC = $classmethod(tClassName, "%KillExtent")
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.PipelineService).DeleteSerialSubclasses(tClassName)
		Quit:$$$ISERR(tSC)
		set tSC = $System.OBJ.Delete(tClassName, "-d")
		Quit:$$$ISERR(tSC)
		kill ^OPCUA.DataSource(tClassName)

		set pResult.deleted = 1
		set pResult.schemaClass = tClassName
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// POST /schemas/:name/validate — dry run a device binding.
///
/// Browses the given device(s) and reports, per device, which of the schema's
/// columns resolve and which do not. This is the mitigation for the deferred-failure
/// risk that name-based resolution introduces: it moves the "does this device
/// actually have these nodes?" question back to before deploy.
///
/// Body: schema name plus `devices` (newline-separated nodepaths, or an array)
/// and the usual connection parameters (url, securityMode, certificates, ...).
ClassMethod Validate(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim tClient As OPCUA.Client
	set pResult = {}
	Try {
		set tSC = ..RequireSchema(pBody, .tClassName)
		Quit:$$$ISERR(tSC)

		set tSC = ..ExtractDeviceSetting(pBody, .tSetting)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.DataSource.Resolver).ParseDeviceNodePaths(tSetting, .tDevices, .tParseErrors)
		if $$$ISERR(tSC) {
			// Surface the per-line reasons, which are far more useful than the summary.
			set tMsg = ##class(OPCUA.REST.Error).Text(tSC)
			for i=1:1:$LL(tParseErrors) { set tMsg = tMsg_"; "_$LI(tParseErrors, i) }
			set tSC = $$$ERROR($$$GeneralError, tMsg)
			Quit
		}

		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass, .tCert, .tKey, .tTrust, .tCrl, .tClientURI)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClassName, tDevices, .tSpec, .tMasks, .tDiag, .tBrowseOK)
		Quit:$$$ISERR(tSC)

		// Column names in the same order the masks use.
		set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(tClassName, .tColumns, .tFolders)
		Quit:$$$ISERR(tSC)

		set pResult.schemaClass = tClassName
		set pResult.columnCount = tColumns
		set tDevArray = []
		set tAllResolved = 1

		for iDev=1:1:$LL(tDevices) {
			set tDev = $LI(tDevices, iDev)
			set tMask = $LI(tMasks, iDev)

			set tEntry = {}
			set tEntry.label = $LI(tDev, 4)
			set tEntry.nodeNs = $LI(tDev, 1)
			set tEntry.nodeId = $LI(tDev, 2)

			set tMatched = [], tMissing = []
			for iCol=1:1:tColumns {
				set tCol = tColumns(iCol)
				set tFolderName = $LI(tCol, 5)
				set tName = $Select(tFolderName="":$LI(tCol, 3), 1:tFolderName_"/"_$LI(tCol, 3))
				if +$LI(tMask, iCol) {
					do tMatched.%Push(tName)
				} else {
					do tMissing.%Push(tName)
					set tAllResolved = 0
				}
			}
			set tEntry.matched = tMatched
			set tEntry.missing = tMissing
			set tEntry.matchedCount = tMatched.%Size()
			set tEntry.missingCount = tMissing.%Size()
			set tEntry.complete = (tMissing.%Size() = 0)

			// Zero matches means different things depending on whether the server
			// answered, and only one of them is a binding worth making.
			set tBrowsed = +$LI(tBrowseOK, iDev)
			set tUsable = (tBrowsed && (tMatched.%Size() > 0))
			set tEntry.browsed = tBrowsed
			set tEntry.usable = tUsable
			if 'tUsable {
				set tEntry.unusableReason = $Select('tBrowsed:"could not be browsed — the device is unreachable, or this NodeId does not exist on the server", 1:"browsed successfully but matched none of the schema's columns — every row would be entirely NULL")
			}
			do tDevArray.%Push(tEntry)
		}

		set pResult.devices = tDevArray
		set pResult.allResolved = tAllResolved

		// Raw diagnostics, so a caller can show the resolver's own wording.
		set tDiagArray = []
		for i=1:1:$LL(tDiag) {
			set tD = $LI(tDiag, i)
			set tObj = {}
			set tObj.device = $LI(tD, 1)
			set tObj.column = $LI(tD, 2)
			set tObj.reason = $LI(tD, 3)
			do tDiagArray.%Push(tObj)
		}
		set pResult.diagnostics = tDiagArray

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

/// Refuse a device list containing any device that would contribute nothing.
///
/// A device only earns a place in a pipeline if the server answered its browse
/// <em>and</em> at least one schema column matched. Both failures are rejected,
/// for different reasons:
/// <ul>
/// <li><b>browsed, zero matches</b> — the wrong node, or a leaf. Every row it
///     produced would be entirely NULL, forever.</li>
/// <li><b>could not be browsed</b> — unreachable, or the NodeId does not exist.
///     Nothing can be verified, so the binding cannot be shown to be good.</li>
/// </ul>
///
/// This is a <em>deploy-time</em> gate only, and deliberately not enforced at
/// runtime: a device that drops offline mid-session must keep storing NULL and
/// warning, not take the pipeline down. Enforcing it on every connect would
/// recreate StrictSchemaMatch, which was removed for exactly that reason.
///
/// The cost is that a device cannot be bound before it exists. Adding it later is
/// a rebind — one settings edit, no recompile.
///
/// pSchemaClass is passed explicitly rather than read from pBody: on a deploy body
/// `name` is the <em>pipeline</em> name, so resolving the schema from it would
/// check the wrong class (or fail outright).
///
/// Devices and connection parameters come from pBody. This reuses
/// <method>Validate</method> so there is one definition of coverage.
ClassMethod RequireUsableDevices(pBody As %DynamicObject, pSchemaClass As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		// Copy the caller's body, overriding only how the schema is identified, so
		// url/securityMode/certificates still reach the browse.
		set tReq = {}.%FromJSON(pBody.%ToJSON())
		do tReq.%Set("className", pSchemaClass)
		do tReq.%Set("name", "")

		set tSC = ..Validate(tReq, .tVal)
		Quit:$$$ISERR(tSC)

		set tDevices = tVal.%Get("devices")
		if '$IsObject($Get(tDevices)) Quit

		set tMsg = ""
		set tBad = 0
		for i=0:1:tDevices.%Size()-1 {
			set tD = tDevices.%Get(i)
			continue:+tD.%Get("usable")
			set tBad = tBad + 1
			set tMsg = tMsg_$Select(tMsg="":"", 1:"; ")_"'"_tD.%Get("label")_"' "_tD.%Get("unusableReason")
		}

		if tBad > 0 {
			set tSC = $$$ERROR($$$GeneralError, "Cannot bind "_tBad_" device(s) — "_tMsg_". Remove the device, or point it at the node that actually holds the schema's values.")
		}
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

// ==================== schema generation ====================

/// Generate and compile a device schema class, plus any %SerialObject classes its
/// nested columns need. No production or device-binding side effects.
///
/// pColNamespaces(i) optionally overrides the OPC UA namespace for the column at
/// 0-based index i; columns without an entry use pDefaultNS. This is how the
/// wizard deploy path preserves the per-node namespaces it browsed.
///
/// pIncludeServerTS 0 types every measurement, flat or nested, as its
/// OPCUA.Types.NoServerTS counterpart, which has no ServerTimeStamp property.
ClassMethod GenerateSchemaClass(pClassName As %String, pDataSourceName As %String, pColumns As %DynamicArray, pDefaultNS As %Integer, ByRef pColNamespaces, Output pSerialClasses, pIncludeServerTS As %Boolean = 1) As %Status
{
	#dim tSC As %Status = $$$OK
	kill pSerialClasses
	set pSerialClasses = 0
	kill tCreatedClasses
	Try {
		// Separate flat columns from nested ones and build the folder tree.
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

		// Serial classes must exist before the main class references them.
		if tHasNesting {
			set tSC = ..GenerateSerialClasses(pClassName, pDefaultNS, .tFolderColumns, .pSerialClasses, pIncludeServerTS, .tCreatedClasses)
			Quit:$$$ISERR(tSC)
		}

		set tClassDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
		set tClassDef.Description = "Auto-generated OPC UA device schema with per-measurement value, quality and "_$Select(pIncludeServerTS:"timestamps.", 1:"source timestamp (no server timestamp).")
		// Extend DeviceSchema (not Definition) so the class is discoverable by the
		// DataSourceClass dropdown, which filters on this superclass.
		set tClassDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

		do ..AddParameter(tClassDef, "OPCUADATASOURCE", pDataSourceName)
		do ..AddParameter(tClassDef, "OPCUDEFAULTANAMESPACE", pDefaultNS)
		do ..AddParameter(tClassDef, "OPCUAPIPELINEVERSION", 2)

		// Device identity is row-level; timestamps and status belong to each measurement.
		set tProp = ##class(%Dictionary.PropertyDefinition).%New()
		set tProp.Name = "NodePath"
		set tProp.Type = "%String"
		do tProp.Parameters.SetAt(500, "MAXLEN")
		do tClassDef.Properties.Insert(tProp)

		// Test hook: inject a bad property type to force compile failure
		if $Get(^||OPCUA.Tests("badProp")) {
			set tProp = ##class(%Dictionary.PropertyDefinition).%New()
			set tProp.Name = "BadProperty"
			set tProp.Type = "ThisClassDoesNotExist"
			do tClassDef.Properties.Insert(tProp)
		}

		// Column properties
		kill tEmittedFolders, tUsedNames
		for i=0:1:pColumns.%Size()-1 {
			set tCol = pColumns.%Get(i)
			set tDisplayName = tCol.%Get("displayName")
			set tInferredType = tCol.%Get("inferredType")
			set tRelPath = tCol.%Get("relativePath")

			set tIsNested = $IsObject($Get(tRelPath)) && (tRelPath.%Size() > 1)
			if tIsNested {
				// One property per folder, emitted once, typed as the serial class.
				set tFolderName = tRelPath.%Get(0)
				if $Data(tEmittedFolders(tFolderName)) continue
				set tEmittedFolders(tFolderName) = 1

				set tSerialClassName = ..SerialClassName(pClassName, tFolderName)
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tFolderName, .tUsedNames)
				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
				set tProp.Name = tPropName
				set tProp.Type = tSerialClassName
				do tProp.Parameters.SetAt(tFolderName, "OPCUANODENAME")
				do tClassDef.Properties.Insert(tProp)
			} else {
				set tType = ..MapToDataValueType(tInferredType, pIncludeServerTS)
				set tChildNS = $Get(pColNamespaces(i), pDefaultNS)
				set tLeafName = tDisplayName
				if $IsObject($Get(tRelPath)) && (tRelPath.%Size() = 1) {
					set tLeafName = tRelPath.%Get(0)
				}
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tLeafName, .tUsedNames)
				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
				set tProp.Name = tPropName
				set tProp.Type = tType
				do tProp.Parameters.SetAt(tLeafName, "OPCUANODENAME")
				if tChildNS '= pDefaultNS {
					do tProp.Parameters.SetAt(tChildNS, "OPCUANAMESPACE")
				}
				do tClassDef.Properties.Insert(tProp)
			}
		}

		set tSC = tClassDef.%Save()
		$$$ThrowOnError(tSC)
		set tCreatedClasses($Increment(tCreatedClasses)) = pClassName
		set tSC = $System.OBJ.Compile(pClassName, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
		// Clean up any classes created by this call
		set i = ""
		for {
			set i = $Order(tCreatedClasses(i))
			quit:i=""
			set tClassName = tCreatedClasses(i)
			if ##class(%Dictionary.ClassDefinition).%ExistsId(tClassName) {
				// Test seam: force a delete failure for a specific class
				if $Get(^||OPCUA.Tests("deleteFailClass")) = tClassName {
					set tDelSC = $$$ERROR($$$GeneralError, "Test-forced delete failure")
				} else {
					set tDelSC = $System.OBJ.Delete(tClassName, "-d")
				}
				if $$$ISERR(tDelSC) {
					set tSC = $$$ADDSC(tSC, $$$ERROR($$$GeneralError, "Failed to delete class '"_tClassName_"' during rollback"))
				}
			}
		}
	}
	Quit tSC
}

/// Generate and compile %SerialObject classes for nested folder columns.
///
/// On any error, deletes exactly the classes this call created and returns the
/// original error. The pCreatedClasses array tracks all classes created across
/// both this method and the caller (GenerateSchemaClass), so cleanup can be
/// thorough.
ClassMethod GenerateSerialClasses(pMainClassName As %String, pDefaultNS As %Integer, ByRef pFolderColumns, Output pSerialClasses, pIncludeServerTS As %Boolean = 1, ByRef pCreatedClasses) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set pSerialClasses = 0

		// Check all target serial class names upfront
		set tFolderName = ""
		for {
			set tFolderName = $Order(pFolderColumns(tFolderName))
			if tFolderName = "" Quit

			set tSerialClassName = ..SerialClassName(pMainClassName, tFolderName)

			// Sanitising is lossy, so two folder names can collapse onto one class
			// name ("A_B" and "AB"). Silently generating the second over the first
			// would drop its columns, so refuse instead.
			if $Data(tTakenNames(tSerialClassName)) {
				set tSC = $$$ERROR($$$GeneralError, "Folders '"_tTakenNames(tSerialClassName)_"' and '"_tFolderName_"' both map to class '"_tSerialClassName_"'. Rename one, or select their columns from a single folder.")
				Quit
			}
			set tTakenNames(tSerialClassName) = tFolderName

			// Check if class already exists
			if ##class(%Dictionary.ClassDefinition).%ExistsId(tSerialClassName) {
				set tSC = ##class(OPCUA.REST.Error).Conflict("Class '"_tSerialClassName_"' already exists. Choose different folder names or a different schema name.")
				Quit
			}
		}
		Quit:$$$ISERR(tSC)

		// Now create and compile the serial classes
		set tFolderName = ""
		for {
			set tFolderName = $Order(pFolderColumns(tFolderName))
			if tFolderName = "" Quit

			set tSerialClassName = ..SerialClassName(pMainClassName, tFolderName)
			set tColumns = pFolderColumns(tFolderName)

			set tClassDef = ##class(%Dictionary.ClassDefinition).%New(tSerialClassName)
			set tClassDef.Description = "Auto-generated serial object for nested OPC UA folder: "_tFolderName
			set tClassDef.Super = "%SerialObject"
			set tClassDef.PropertyClass = "OPCUA.DataSource.PropertyClass"

			kill tUsedNames
			for i=0:1:tColumns.%Size()-1 {
				set tSubCol = tColumns.%Get(i)
				set tLeafName = tSubCol.%Get("leafName")
				set tType = ..MapToDataValueType(tSubCol.%Get("inferredType"), pIncludeServerTS)
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tLeafName, .tUsedNames)

				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
				set tProp.Name = tPropName
				set tProp.Type = tType
				do tProp.Parameters.SetAt(tLeafName, "OPCUANODENAME")
				do tClassDef.Properties.Insert(tProp)
			}

			set tSC = tClassDef.%Save()
			$$$ThrowOnError(tSC)
			set pCreatedClasses($Increment(pCreatedClasses)) = tSerialClassName
			set tSC = $System.OBJ.Compile(tSerialClassName, "ck-d")
			$$$ThrowOnError(tSC)

			set pSerialClasses = pSerialClasses + 1
			set pSerialClasses(pSerialClasses) = $LB(tSerialClassName, "")
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Name of the %SerialObject class backing a nested folder.
///
/// An OPC UA browse name is free text, but a class name is not: underscores and
/// most punctuation are rejected by %Dictionary.Classname validation, so the
/// folder name is sanitised before it becomes an identifier. Without this, a
/// folder called "State_Condition" fails the schema save with #5794 rather than
/// producing a usable class.
///
/// The folder's real OPC UA name is preserved as the property's OPCUANODENAME,
/// which is what resolution actually matches on — so sanitising here changes the
/// class name only, never the name looked up on the device.
ClassMethod SerialClassName(pMainClassName As %String, pFolderName As %String) As %String
{
	kill tUsed
	set tIdent = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(pFolderName, .tUsed)
	set tIdent = $Replace(tIdent, "_", "")
	if tIdent = "" set tIdent = "Folder"
	// A leading digit survives sanitisation as "N<digits>", so only the empty
	// case needs guarding above.
	Quit pMainClassName_"."_tIdent_"Type"
}

/// Preserve the OPC UA DataValue wrapper, including its status and timestamps.
/// Plain type aliases remain accepted in API requests, but produce wrappers too.
/// Unknown/unprobed types keep the existing string fallback.
///
/// pIncludeServerTS 0 returns the OPCUA.Types.NoServerTS counterpart instead.
/// Either family is accepted as input and mapped to the requested one.
ClassMethod MapToDataValueType(pInferredType As %String, pIncludeServerTS As %Boolean = 1) As %String
{
	set tType = ..MapToFullDataValueType($Replace(pInferredType, "OPCUA.Types.NoServerTS.", "OPCUA.Types.", 1, 1))
	Quit:pIncludeServerTS tType
	set tShort = "OPCUA.Types.NoServerTS."_$Extract(tType, 13, *)
	Quit $Select(##class(%Dictionary.CompiledClass).%ExistsId(tShort):tShort, 1:"OPCUA.Types.NoServerTS.StringDataValue")
}

/// Map an inferred type onto an OPCUA.Types measurement that keeps its server timestamp.
ClassMethod MapToFullDataValueType(pInferredType As %String) As %String [ Private ]
{
	if $Extract(pInferredType, 1, 12) = "OPCUA.Types." {
		if ##class(%Dictionary.CompiledClass).%ExistsId(pInferredType) {
			if (pInferredType '= "OPCUA.Types.AbstractDataValue") && $classmethod(pInferredType, "%Extends", "OPCUA.Types.AbstractDataValue") {
				Quit pInferredType
			}
		}
	}
	if pInferredType = "%Double" Quit "OPCUA.Types.DoubleDataValue"
	if pInferredType = "%Numeric" Quit "OPCUA.Types.DoubleDataValue"
	if pInferredType = "%Float" Quit "OPCUA.Types.FloatDataValue"
	if pInferredType = "%Integer" Quit "OPCUA.Types.IntegerDataValue"
	if pInferredType = "%Boolean" Quit "OPCUA.Types.BooleanDataValue"
	if pInferredType = "%TimeStamp" Quit "OPCUA.Types.TimeStampDataValue"
	Quit "OPCUA.Types.StringDataValue"
}

/// Find the most common namespace among a set of nodes (or columns).
ClassMethod FindDefaultNamespace(pNodes As %DynamicArray) As %Integer
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
ClassMethod AddParameter(pClassDef As %Dictionary.ClassDefinition, pName As %String, pValue As %String)
{
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = pName
	set tParam.Default = pValue
	do pClassDef.Parameters.Insert(tParam)
}

// ==================== helpers ====================

/// Resolve the target class name from `className`, or from `name` plus an
/// optional `packagePath` (defaulting to OPCUA.DS).
///
/// The result must be a valid class name, so a bad name is a 400 saying so here,
/// rather than a %Dictionary datatype error later.
ClassMethod ResolveClassName(pBody As %DynamicObject, Output pClassName As %String) As %Status [ Private ]
{
	set pClassName = pBody.%Get("className")
	if pClassName = "" {
		set tName = pBody.%Get("name")
		if tName = "" {
			Quit $$$ERROR($$$GeneralError, "Missing schema name (supply 'className', or 'name' with optional 'packagePath')")
		}
		if tName [ "." {
			// A dotted name is already fully qualified.
			set pClassName = tName
		} else {
			set tPackage = pBody.%Get("packagePath")
			if tPackage = "" set tPackage = ..#DefaultPackage
			set pClassName = tPackage_"."_tName
		}
	}
	if '##class(%Dictionary.Classname).IsValid(pClassName) {
		Quit ##class(OPCUA.REST.Error).BadRequest("'"_pClassName_"' is not a valid schema name. Use letters and digits only, starting with a letter (no spaces, hyphens or underscores), with dots only between package parts.")
	}
	Quit $$$OK
}

/// Resolve and validate that the requested schema exists and really is a schema.
ClassMethod RequireSchema(pBody As %DynamicObject, Output pClassName As %String) As %Status [ Private ]
{
	set tSC = ..ResolveClassName(pBody, .pClassName)
	Quit:$$$ISERR(tSC) tSC

	if '##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		Quit ##class(OPCUA.REST.Error).NotFound("Schema '"_pClassName_"' does not exist")
	}
	if '..IsSchema(pClassName) {
		Quit $$$ERROR($$$GeneralError, "Class '"_pClassName_"' is not an OPCUA.DataSource.DeviceSchema subclass")
	}
	Quit $$$OK
}

/// Is this class a usable device schema?
ClassMethod IsSchema(pClassName As %String) As %Boolean
{
	set tIs = 0
	Try {
		if pClassName '= "OPCUA.DataSource.DeviceSchema" {
			set tIs = $classmethod(pClassName, "%Extends", "OPCUA.DataSource.DeviceSchema")
		}
	} Catch (e) {
		set tIs = 0
	}
	Quit tIs
}

/// Describe one schema: identity, table, and (optionally) its columns.
/// Columns are reported in storage order, which is the order the runtime
/// services and the resolver's coverage masks use.
///
/// <var>pSC</var> is the error when the columns cannot be read (e.g. the class's
/// compiled spec in <tt>^OPCUA.DataSource</tt> is missing); the item then has
/// <tt>columnCount</tt> 0 and a <tt>columnsError</tt> saying why.
ClassMethod DescribeSchema(pClassName As %String, pWithColumns As %Boolean = 0, Output pSC As %Status) As %DynamicObject
{
	set pSC = $$$OK
	set tItem = {}
	set tItem.schemaClass = pClassName
	set tItem.name = $Piece(pClassName, ".", *)
	set tItem.packagePath = $Piece(pClassName, ".", 1, *-1)
	set tItem.tableName = ..TableName(pClassName)

	Try {
		set tCD = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
		if $IsObject(tCD) {
			for i=1:1:tCD.Parameters.Count() {
				set tP = tCD.Parameters.GetAt(i)
				if tP.Name = "OPCUADATASOURCE" set tItem.dataSourceName = tP.Default
				if tP.Name = "OPCUDEFAULTANAMESPACE" set tItem.defaultNamespace = tP.Default
			}
		}

		set tSC = ##class(OPCUA.DataSource.Resolver).GetSchemaColumns(pClassName, .tColumns, .tFolders)
		if $$$ISOK(tSC) {
			set tItem.columnCount = tColumns
			if pWithColumns {
				set tArr = []
				for i=1:1:tColumns {
					set tCol = tColumns(i)
					set tObj = {}
					set tObj.nodeName = $LI(tCol, 3)
					set tObj.namespace = $LI(tCol, 2)
					set tObj.attributeId = $LI(tCol, 4)
					set tObj.folder = $LI(tCol, 5)
					set tObj.propertyPath = $LI(tCol, 1)
					do tArr.%Push(tObj)
				}
				set tItem.columns = tArr
			}
		} else {
			set pSC = tSC
		}
	} Catch (e) {
		set pSC = e.AsStatus()
	}
	if $$$ISERR(pSC) {
		set tItem.columnCount = 0
		set tItem.columnsError = ##class(OPCUA.REST.Error).Text(pSC)
	}

	Quit tItem
}

/// Map usage across ALL productions in the namespace.
///
/// Output: pUsage(schemaClass, production, itemName) = "". Any failure (e.g. cannot
/// open a production) is returned as a %Status error, so callers can refuse actions
/// that depend on complete usage information.
///
/// Not private: PipelineService reports remaining usage after deleting a
/// pipeline, and this is the single definition of "which pipelines use what".
ClassMethod MapSchemaUsage(Output pUsage) As %Status
{
	#dim tSC As %Status = $$$OK
	kill pUsage
	Try {
		// Test seam: force a failure to test error handling
		if $Get(^||OPCUA.Tests("failUsage")) {
			set tSC = ##class(OPCUA.REST.Error).Make(500, "Forced usage check failure")
			Quit
		}

		// Iterate every production in the namespace via SQL
		// A failed query (e.g. no SELECT privilege for this user) must stop the
		// caller: read as "no productions", schema delete would skip its in-use check.
		Try {
			set tRS = ##class(OPCUA.Utils).ExecQuery("SELECT ID FROM Ens_Config.Production")
		} Catch (eQuery) {
			set tSC = ##class(OPCUA.REST.Error).Make(500, "Failed to query Ens_Config.Production", eQuery.AsStatus())
		}
		Quit:$$$ISERR(tSC)

		while tRS.%Next() {
			set tProdClass = tRS.ID
			set tProd = ##class(Ens.Config.Production).%OpenId(tProdClass)
			if '$IsObject(tProd) {
				set tSC = ##class(OPCUA.REST.Error).Make(500, "Failed to open production '"_tProdClass_"'")
				Quit
			}

			for i=1:1:tProd.Items.Count() {
				set tItem = tProd.Items.GetAt(i)
				for j=1:1:tItem.Settings.Count() {
					set tS = tItem.Settings.GetAt(j)
					continue:tS.Name'="DataSourceClass"
					continue:tS.Value=""
					set pUsage(tS.Value, tProdClass, tItem.Name) = ""
				}
			}
		}
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Turn the three-subscript usage map into a JSON array of objects.
///
/// Input: pUsage(schemaClass, production, itemName) = ""
/// Output: [{name: itemName, production: prodClass, managed: true|false}, ...]
/// where managed = true if production is OPCUA.Pipeline.Production.
ClassMethod UsageArray(ByRef pUsage, pSchemaClass As %String) As %DynamicArray
{
	set tArr = []
	set tProdClass = ""
	for {
		set tProdClass = $Order(pUsage(pSchemaClass, tProdClass))
		quit:tProdClass=""

		set tItemName = ""
		for {
			set tItemName = $Order(pUsage(pSchemaClass, tProdClass, tItemName))
			quit:tItemName=""

			set tObj = {}
			set tObj.name = tItemName
			set tObj.production = tProdClass
			set tManaged = (tProdClass = ##class(OPCUA.REST.DeployService).#ProductionClass)
			do tObj.%Set("managed", tManaged, "boolean")
			do tArr.%Push(tObj)
		}
	}
	Quit tArr
}

/// Accept the device list either as a newline-separated string (`devices` /
/// `deviceNodePaths`) or as a JSON array of nodepath strings/objects.
ClassMethod ExtractDeviceSetting(pBody As %DynamicObject, Output pSetting As %String) As %Status [ Private ]
{
	set pSetting = ""
	set tDevices = pBody.%Get("devices")
	if tDevices = "" set tDevices = pBody.%Get("deviceNodePaths")

	if $IsObject($Get(tDevices)) {
		// JSON array: strings, or objects with nodePath/path (+ optional label)
		for i=0:1:tDevices.%Size()-1 {
			set tD = tDevices.%Get(i)
			if $IsObject($Get(tD)) {
				set tPath = tD.%Get("nodePath")
				if tPath = "" set tPath = tD.%Get("path")
				set tLabel = tD.%Get("label")
				set:tLabel'="" tPath = tPath_"|"_tLabel
			} else {
				set tPath = tD
			}
			continue:tPath=""
			set pSetting = pSetting_$Select(pSetting="":"", 1:$Char(10))_tPath
		}
	} else {
		set pSetting = tDevices
	}

	if pSetting = "" {
		Quit $$$ERROR($$$GeneralError, "No devices supplied — provide 'devices' as newline-separated nodepaths or an array")
	}
	Quit $$$OK
}

/// Derive the SQL table name for a class, honoring SqlTableName and SqlSchemaName.
/// Returns the qualified name as "schema.table" (unquoted).
ClassMethod TableName(pClassName As %String) As %String
{
	Set tCompiledClass = ##class(%Dictionary.CompiledClass).%OpenId(pClassName)
	If '$IsObject(tCompiledClass) {
		// Fallback: derive from package structure
		Set tPackage = $Piece(pClassName, ".", 1, *-1)
		Set tShort = $Piece(pClassName, ".", *)
		Quit $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
	}

	// Get SqlTableName (defaults to short class name)
	Set tTableName = tCompiledClass.SqlTableName
	If tTableName = "" {
		Set tTableName = $Piece(pClassName, ".", *)
	}

	// Get SqlSchemaName (defaults to package with dots replaced by underscores)
	Set tSchemaName = tCompiledClass.SqlSchemaName
	If tSchemaName = "" {
		Set tPackage = $Piece(pClassName, ".", 1, *-1)
		If tPackage = "" {
			Set tSchemaName = "SQLUser"
		} Else {
			Set tSchemaName = $Replace(tPackage, ".", "_")
		}
	}

	Quit tSchemaName_"."_tTableName
}

}
