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
			set tSC = $$$ERROR($$$GeneralError, "Class '"_tClassName_"' already exists. Choose a different name.")
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

		set tSC = ..GenerateSchemaClass(tClassName, tDataSourceName, tColumns, tDefaultNS, .tColNS, .tSerialClasses)
		Quit:$$$ISERR(tSC)

		set pResult.created = 1
		set pResult.schemaClass = tClassName
		set pResult.dataSourceName = tDataSourceName
		set pResult.tableName = ..TableName(tClassName)
		set pResult.columnCount = tColumns.%Size()
		set pResult.serialClasses = $Get(tSerialClasses, 0)

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
		do ..MapSchemaUsage(.tUsage)

		set tRS = ##class(%ResultSet).%New("%Dictionary.ClassDefinition:SubclassOf")
		set tSC = tRS.Execute("OPCUA.DataSource.DeviceSchema")
		Quit:$$$ISERR(tSC)

		while tRS.Next() {
			set tClass = tRS.Data("Name")
			continue:tClass="OPCUA.DataSource.DeviceSchema"
			// Skip abstract classes — they cannot back a pipeline.
			continue:$$$comClassKeyGet(tClass,$$$cCLASSabstract)

			set tItem = ..DescribeSchema(tClass, 0)
			set tItem.usedBy = ..UsageArray($Get(tUsage(tClass), ""))
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

		do ..MapSchemaUsage(.tUsage)
		set pResult = ..DescribeSchema(tClassName, 1)
		set pResult.usedBy = ..UsageArray($Get(tUsage(tClassName), ""))
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

		do ..MapSchemaUsage(.tUsage)
		set tUsedBy = $Get(tUsage(tClassName), "")
		if tUsedBy '= "" {
			set tSC = $$$ERROR($$$GeneralError, "Schema '"_tClassName_"' is still used by pipeline(s): "_$Replace(tUsedBy, $Char(1), ", ")_". Delete those pipelines first.")
			Quit
		}

		do ##class(OPCUA.REST.PipelineService).DeleteSerialSubclasses(tClassName)
		do $System.OBJ.Delete(tClassName, "-d")
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
			set tMsg = $System.Status.GetOneErrorText(tSC)
			for i=1:1:$LL(tParseErrors) { set tMsg = tMsg_"; "_$LI(tParseErrors, i) }
			set tSC = $$$ERROR($$$GeneralError, tMsg)
			Quit
		}

		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass, .tCert, .tKey, .tTrust, .tCrl, .tClientURI)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.DataSource.Resolver).ResolveSpecification(tClient, tClassName, tDevices, .tSpec, .tMasks, .tDiag)
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

// ==================== schema generation ====================

/// Generate and compile a device schema class, plus any %SerialObject classes its
/// nested columns need. No production or device-binding side effects.
///
/// pColNamespaces(i) optionally overrides the OPC UA namespace for the column at
/// 0-based index i; columns without an entry use pDefaultNS. This is how the
/// wizard deploy path preserves the per-node namespaces it browsed.
ClassMethod GenerateSchemaClass(pClassName As %String, pDataSourceName As %String, pColumns As %DynamicArray, pDefaultNS As %Integer, ByRef pColNamespaces, Output pSerialClasses) As %Status
{
	#dim tSC As %Status = $$$OK
	kill pSerialClasses
	set pSerialClasses = 0
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
			set tSC = ..GenerateSerialClasses(pClassName, pDefaultNS, .tFolderColumns, .pSerialClasses)
			Quit:$$$ISERR(tSC)
		}

		set tClassDef = ##class(%Dictionary.ClassDefinition).%New(pClassName)
		set tClassDef.Description = "Auto-generated OPC UA DataSource class (v2 row-source model)."
		// Extend DeviceSchema (not Definition) so the class is discoverable by the
		// DataSourceClass dropdown, which filters on this superclass.
		set tClassDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

		do ..AddParameter(tClassDef, "OPCUADATASOURCE", pDataSourceName)
		do ..AddParameter(tClassDef, "OPCUDEFAULTANAMESPACE", pDefaultNS)
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

				set tSerialClassName = pClassName_"."_tFolderName_"Type"
				set tPropName = ##class(OPCUA.DataSource.Generator).SanitizePropertyName(tFolderName, .tUsedNames)
				set tProp = ##class(%Dictionary.PropertyDefinition).%New()
				set tProp.Name = tPropName
				set tProp.Type = tSerialClassName
				do tProp.Parameters.SetAt(tFolderName, "OPCUANODENAME")
				do tClassDef.Properties.Insert(tProp)
			} else {
				set tType = ..MapToPlainType(tInferredType)
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
		set tSC = $System.OBJ.Compile(pClassName, "ck-d")
		$$$ThrowOnError(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Generate and compile %SerialObject classes for nested folder columns.
ClassMethod GenerateSerialClasses(pMainClassName As %String, pDefaultNS As %Integer, ByRef pFolderColumns, Output pSerialClasses) As %Status
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

			set pSerialClasses = pSerialClasses + 1
			set pSerialClasses(pSerialClasses) = $LB(tSerialClassName, "")
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
ClassMethod ResolveClassName(pBody As %DynamicObject, Output pClassName As %String) As %Status [ Private ]
{
	set pClassName = pBody.%Get("className")
	if pClassName '= "" Quit $$$OK

	set tName = pBody.%Get("name")
	if tName = "" {
		Quit $$$ERROR($$$GeneralError, "Missing schema name (supply 'className', or 'name' with optional 'packagePath')")
	}
	// A dotted name is already fully qualified.
	if tName [ "." {
		set pClassName = tName
		Quit $$$OK
	}
	set tPackage = pBody.%Get("packagePath")
	if tPackage = "" set tPackage = ..#DefaultPackage
	set pClassName = tPackage_"."_tName
	Quit $$$OK
}

/// Resolve and validate that the requested schema exists and really is a schema.
ClassMethod RequireSchema(pBody As %DynamicObject, Output pClassName As %String) As %Status [ Private ]
{
	set tSC = ..ResolveClassName(pBody, .pClassName)
	Quit:$$$ISERR(tSC) tSC

	if '##class(%Dictionary.ClassDefinition).%ExistsId(pClassName) {
		Quit $$$ERROR($$$GeneralError, "Schema '"_pClassName_"' does not exist")
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
ClassMethod DescribeSchema(pClassName As %String, pWithColumns As %Boolean = 0) As %DynamicObject
{
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
			set tItem.columnCount = 0
		}
	} Catch (e) {}

	Quit tItem
}

/// Map schemaClass → $Char(1)-delimited list of config items referencing it.
ClassMethod MapSchemaUsage(Output pUsage) [ Private ]
{
	kill pUsage
	Try {
		set tProdClass = ##class(OPCUA.REST.DeployService).#ProductionClass
		if '##class(%Dictionary.ClassDefinition).%ExistsId(tProdClass) Quit
		set tProd = ##class(Ens.Config.Production).%OpenId(tProdClass)
		if '$IsObject(tProd) Quit

		for i=1:1:tProd.Items.Count() {
			set tItem = tProd.Items.GetAt(i)
			for j=1:1:tItem.Settings.Count() {
				set tS = tItem.Settings.GetAt(j)
				continue:tS.Name'="DataSourceClass"
				continue:tS.Value=""
				set pUsage(tS.Value) = $Get(pUsage(tS.Value), "")_$Select($Get(pUsage(tS.Value))="":"", 1:$Char(1))_tItem.Name
			}
		}
	} Catch (e) {}
}

/// Turn a $Char(1)-delimited usage list into a JSON array.
ClassMethod UsageArray(pList As %String) As %DynamicArray [ Private ]
{
	set tArr = []
	Quit:pList="" tArr
	for i=1:1:$Length(pList, $Char(1)) {
		do tArr.%Push($Piece(pList, $Char(1), i))
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

/// Derive the SQL table name for a class.
ClassMethod TableName(pClassName As %String) As %String
{
	set tPackage = $Piece(pClassName, ".", 1, *-1)
	set tShort = $Piece(pClassName, ".", *)
	Quit $Select(tPackage="":tShort, 1:$Replace(tPackage, ".", "_")_"."_tShort)
}

}
