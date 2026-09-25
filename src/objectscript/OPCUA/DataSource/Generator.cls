Include (OPCUA.Constants, Ensemble)

/// Auto-generates DataSource class definitions by browsing an OPC UA server.
/// Connects to the server, walks the node tree depth-first from a start node,
/// and produces a ready-to-use .cls file with properties mapped to discovered
/// variable nodes. Types come from each node's DataType and ValueRank attributes
/// (see <method>InferType</method>). Review the generated file and adjust any
/// types that could not be determined.
///
/// <b>Terminal-only, and not part of the pipeline path.</b> This writes a
/// <class>OPCUA.DataSource.Definition</class> subclass to a .cls file for a human
/// to review and import -- the declarative style the Examples and Tests use. It is
/// not how pipelines are built: <class>OPCUA.REST.SchemaService</class> generates
/// a <class>OPCUA.DataSource.DeviceSchema</class> subclass through the %Dictionary
/// API and compiles it in place, with no file and no manual step. The `/generate`
/// REST endpoint that used to expose this was removed with the Chrome extension,
/// its only consumer.
///
/// Two of its helpers are still on the live path and must not be moved:
/// <method>InferType</method> (used by <class>OPCUA.REST.ReadService</class>
/// to type a column) and <method>SanitizePropertyName</method> (used by
/// <class>OPCUA.REST.SchemaService</class> to turn OPC UA names into legal
/// property identifiers).
///
/// Example usage:
/// <example>
/// do ##class(OPCUA.DataSource.Generator).Generate(
///     "opc.tcp://plc", 0, 84,
///     "Generated.PLCDataSource", "PLCData",
///     "/usr/irissys/mgr/User/")
/// </example>
Class OPCUA.DataSource.Generator
{

/// Generate a DataSource class file by browsing an OPC UA server.
/// <ul>
/// <li>URL - OPC UA server URL (e.g., "opc.tcp://plc")</li>
/// <li>StartNodeNS - Namespace of the start node to browse from</li>
/// <li>StartNodeId - Node ID of the start node (e.g., 84 for Root)</li>
/// <li>ClassName - Fully qualified class name to generate</li>
/// <li>DataSourceName - Value for the OPCUADATASOURCE parameter</li>
/// <li>OutputPath - Directory to write the generated .cls file</li>
/// <li>StartNodeIdType - Node ID type of start node (0=numeric, 3=string)</li>
/// <li>SecurityMode - OPC UA security mode (1=None, 3=SignAndEncrypt)</li>
/// <li>MaxDepth - Maximum recursion depth for browsing (default 20)</li>
/// <li>Username - Optional username for authenticated connections</li>
/// <li>Password - Optional password for authenticated connections</li>
/// </ul>
ClassMethod Generate(URL As %String, StartNodeNS As %Integer, StartNodeId, ClassName As %String, DataSourceName As %String, OutputPath As %String, StartNodeIdType As %Integer = 0, SecurityMode As %Integer = 1, MaxDepth As %Integer = 20, Username As %String = "", Password As %String = "") As %Status
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException

	Try {
		write "OPCUA DataSource Generator", !
		write "==========================", !

		// Initialize library
		set tSC = ##class(OPCUA.Utils).Initialize()
		Quit:$$$ISERR(tSC)

		// Create and setup client
		write "Connecting to "_URL_"...", !
		set tClient = ##class(OPCUA.Client).%New()
		set tSC = tClient.Initialize()
		Quit:$$$ISERR(tSC)

		set tSC = tClient.SetupClient(, SecurityMode)
		Quit:$$$ISERR(tSC)

		set tSC = tClient.Connect(URL, Username, Password)
		Quit:$$$ISERR(tSC)
		write "Connected.", !

		// Browse recursively from the start node
		write "Browsing from node (ns="_StartNodeNS_", id="_StartNodeId_")...", !
		set tNodeCount = 0
		do ..BrowseRecursive(tClient, StartNodeNS, StartNodeId, StartNodeIdType, 0, MaxDepth, .tNodes, .tNodeCount, .tVisited)

		write "Found "_tNodeCount_" variable node(s).", !

		if tNodeCount > 0 {
			// Determine default namespace from discovered nodes
			set tDefaultNS = ..DetermineDefaultNamespace(.tNodes, tNodeCount, StartNodeNS)

			// Generate the class file
			set tSC = ..GenerateClassFile(ClassName, DataSourceName, tDefaultNS, OutputPath, .tNodes, tNodeCount)
			Quit:$$$ISERR(tSC)
		} else {
			write "No variable nodes found. No file generated.", !
		}

		// Disconnect
		write "Disconnecting...", !
		do tClient.Disconnect()
		write "Done.", !

	} Catch (e) {
		Set tSC = e.AsStatus()
		// Try to disconnect on error
		Try {
			if $IsObject($Get(tClient)) do tClient.Disconnect()
		} Catch (e2) {}
	}

	Quit tSC
}

/// Walk the node tree depth-first from the given node, collecting variable nodes.
/// Uses browse reference metadata to classify nodes:
///  - Reference type [1]: skip HasTypeDefinition (id=40) references
///  - Type definition [7]: classify Variable vs Object by type def node ID
ClassMethod BrowseRecursive(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer, pDepth As %Integer, pMaxDepth As %Integer, ByRef pNodes, ByRef pNodeCount As %Integer, ByRef pVisited) [ Private ]
{
	// Check max depth
	if pDepth >= pMaxDepth {
		write $Justify("", (pDepth+1)*2)_"[max depth reached]", !
		Quit
	}

	// Check for cycles
	set tKey = pNodeNS_":"_pNodeIdType_":"_pNodeId
	if $Data(pVisited(tKey)) Quit
	set pVisited(tKey) = 1

	Try {
		// Browse this node's children
		set tSC = pClient.Browse(.tResults, $LB(pNodeIdType), $LB(pNodeNS), $LB(pNodeId))
		if $$$ISERR(tSC) {
			write $Justify("", (pDepth+1)*2)_"Warning: Browse failed for node (ns="_pNodeNS_", id="_pNodeId_")", !
			Quit
		}

		// Extract reference list from browse results
		// Each reference: [1]=refType, [2]=isForward, [3]=nodeInfo, [4]=browseName,
		//                 [5]=displayName, [6]=nodeClass(empty), [7]=typeDef
		set tBrowseData = $LI(tResults, 4)
		set tFirstResult = $LI(tBrowseData, 1)
		set tRefList = $LI(tFirstResult, 4)
		set tRefCount = $LL(tRefList)

		if tRefCount = 0 Quit

		// Process each child reference
		for i=1:1:tRefCount {
			set tRef = $LI(tRefList, i)

			// Check reference type - skip HasTypeDefinition (ns=0, id=40)
			set tRefTypeInfo = $LI(tRef, 1)
			set tRefTypeNS = $LI(tRefTypeInfo, 1)
			set tRefTypeId = $LI(tRefTypeInfo, 2)
			if (tRefTypeNS = 0) && (tRefTypeId = 40) continue

			set tNodeInfo = $LI(tRef, 3)
			set tDisplayInfo = $LI(tRef, 4)

			set tChildNS = $LI(tNodeInfo, 1)
			set tChildId = $LI(tNodeInfo, 2)
			set tChildIdType = $LI(tNodeInfo, 3)
			set tChildName = $LI(tDisplayInfo, 1)

			// Skip empty display names
			if tChildName = "" set tChildName = "Node"_tChildId

			set tIndent = $Justify("", (pDepth+1)*2)

			// Classify using type definition from browse metadata [7]
			set tClass = ..ClassifyByTypeDef($LI(tRef, 7))

			if tClass = "Variable" {
				do ..ProcessVariableNode(pClient, tChildNS, tChildId, tChildIdType, tChildName, .pNodes, .pNodeCount)
				set tInferred = $LI(pNodes(pNodeCount), 5)
				set tShortType = $Piece(tInferred, ".", *)
				write tIndent_"+ "_tChildName_" (ns="_tChildNS_", id="_tChildId_") ["_tShortType_"]", !
			} elseif tClass = "Object" {
				write tIndent_"> "_tChildName_"/", !
				// Recurse into folder/object
				do ..BrowseRecursive(pClient, tChildNS, tChildId, tChildIdType, pDepth + 1, pMaxDepth, .pNodes, .pNodeCount, .pVisited)
			}
			// "Unknown" nodes are silently skipped
		}

	} Catch (e) {
		write $Justify("", (pDepth+1)*2)_"Warning: Error processing node (ns="_pNodeNS_", id="_pNodeId_"): "_e.DisplayString(), !
	}

	Quit
}

/// Classify a node using its type definition from browse reference metadata.
/// Well-known OPC UA variable types (ns=0): BaseVariableType(62),
/// BaseDataVariableType(63), PropertyType(68).
/// Anything else in ns=0 is treated as Object. Unknown/custom types
/// default to Variable (user can review the generated file).
ClassMethod ClassifyByTypeDef(pTypeDef As %List) As %String
{
	set tResult = "Unknown"
	Try {
		set tTypeDefNS = $LI(pTypeDef, 1)
		set tTypeDefId = $LI(pTypeDef, 2)

		// Empty or null type definition
		if (tTypeDefNS = "") || (tTypeDefId = "") || (tTypeDefId = 0) {
			Quit
		}

		// Well-known OPC UA variable types in namespace 0
		if tTypeDefNS = 0 {
			if (tTypeDefId = 62) || (tTypeDefId = 63) || (tTypeDefId = 68) {
				set tResult = "Variable"
			} else {
				// Everything else in ns=0 is an Object type (FolderType, ServerType, etc.)
				set tResult = "Object"
			}
			Quit
		}

		// Custom type in non-standard namespace: default to Variable
		// (user reviews and adjusts the generated file)
		set tResult = "Variable"
	} Catch (e) {
		// Malformed type definition
	}
	Quit tResult
}

/// Add a variable node to the collection, typed from the server's own
/// DataType attribute.
ClassMethod ProcessVariableNode(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer, pDisplayName As %String, ByRef pNodes, ByRef pNodeCount As %Integer) [ Private ]
{
	set tType = ..InferType(pClient, pNodeNS, pNodeId, pNodeIdType)
	set pNodeCount = $Get(pNodeCount, 0) + 1
	set pNodes(pNodeCount) = $LB(pNodeNS, pNodeId, pNodeIdType, pDisplayName, tType)
}

/// Type a node from what the server declares about it, rather than from what
/// its current value happens to look like.
///
/// Reads two attributes of the node: DataType (14), which names the type, and
/// ValueRank (15), which says scalar, array or matrix. That settles the cases a
/// value cannot: the native layer renders a Boolean as 0/1 like any integer,
/// and a Double of 0.0 as "0". The value is read only when the server leaves the
/// shape open (ValueRank Any / ScalarOrOneDimension), and the old value-based
/// guess, <method>InferTypeFromValue</method>, is used only for a DataType that
/// <method>MapDataTypeToIRIS</method> does not know -- a vendor-defined type, say.
///
/// The single-attribute read in the native layer supports only the Value
/// attribute, so the attributes are fetched as a one-shot bulk query
/// (<method>ReadAttributesOnce</method>). DataType and ValueRank share one query
/// and the Value, when needed, gets its own: a value of a type the native layer
/// cannot convert (a Guid, an ExtensionObject) fails the whole poll, while
/// DataType and ValueRank are always a NodeId and an integer.
ClassMethod InferType(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer) As %String
{
	set tType = ""
	// A bulk specification identifies a node by a bare string, and the native
	// layer treats one made of digits as a numeric id. A string id that is all
	// digits, a GUID or a ByteString therefore cannot be asked about this way.
	set tProbeable = (pNodeIdType = $$$OpcuaNodeIdTypeNumeric) || ((pNodeIdType = $$$OpcuaNodeIdTypeString) && '$Match(pNodeId, "^\d+$"))
	if tProbeable && ..ReadTypeAttributes(pClient, pNodeNS, pNodeId, .tDataType, .tValueRank) {
		// ValueRank: -1 scalar, 1 array, >1 matrix, 0 one or more dimensions;
		// -2 (Any) and -3 (ScalarOrOneDimension) leave it to the value.
		set tDims = $Select(tValueRank >= 0:$Select(tValueRank = 0:1, 1:tValueRank), tValueRank = -1:0, 1:..ValueDimensions(pClient, pNodeNS, pNodeId))
		set tType = ..MapDataTypeToIRIS(tDataType, tDims)
	}
	Quit $Select(tType '= "":tType, 1:..InferTypeFromValue(pClient, pNodeNS, pNodeId, pNodeIdType))
}

/// Fetch a node's DataType and ValueRank. Returns 0 if either is unavailable --
/// the node does not exist, or is not a variable. pDataType is the numeric id of
/// a namespace-0 type, or "" for a type defined in another namespace.
ClassMethod ReadTypeAttributes(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, Output pDataType, Output pValueRank) As %Boolean [ Private ]
{
	set (pDataType, pValueRank) = ""
	Quit:'..ReadAttributesOnce(pClient, pNodeNS, pNodeId, $LB($$$OpcuaAttributeDataType, $$$OpcuaAttributeValueRank), .tResults) 0
	// A missing attribute is "", not a DataValue. DataType arrives as a NodeId
	// inlined into its DataValue:
	// $LB(sourceTS, serverTS, status, namespace, identifier, identifierType, ...)
	set tDT = $ListGet(tResults, 1)
	set tVR = $ListGet(tResults, 2)
	Quit:'$ListValid(tDT)||($ListLength(tDT) < 5)||'$ListValid(tVR)||($ListLength(tVR) < 4) 0
	// A node the attribute does not apply to answers with a bad status.
	Quit:($ListGet(tDT, 3) '= 0)||($ListGet(tVR, 3) '= 0) 0
	set pDataType = $Select($ListGet(tDT, 4) = 0:$ListGet(tDT, 5), 1:"")
	set pValueRank = $ListGet(tVR, 4)
	Quit (pValueRank '= "")
}

/// Number of dimensions the node's current value actually has: 0 for a scalar,
/// 1 for an array, 2 for a matrix. Used only when ValueRank leaves it open.
/// A value that cannot be read counts as a scalar.
///
/// This cannot use <method>OPCUA.Client.ReadValueAttribute</method>: the native
/// single read returns an array value as null. The bulk read returns it intact.
ClassMethod ValueDimensions(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId) As %Integer [ Private ]
{
	Quit:'..ReadAttributesOnce(pClient, pNodeNS, pNodeId, $LB($$$OpcuaAttributeValue), .tResults) 0
	// $LB(sourceTS, serverTS, status, value[, dimensions])
	set tDV = $ListGet(tResults, 1)
	Quit:'$ListValid(tDV)||($ListLength(tDV) < 4) 0
	set tValue = $ListGet(tDV, 4)
	// An empty String reads back as an empty list, so only a non-empty list is an array.
	Quit:'$ListValid(tValue)||($ListLength(tValue) = 0) 0
	Quit $Select($ListValid($ListGet(tValue, 1)) && ($ListGet(tValue, 1) '= ""):2, 1:1)
}

/// Read some attributes of one node as a one-shot bulk query: ReadBulkSetupC,
/// one ReadBulkPollC, ReadBulkClear. pResults holds one entry per attribute in
/// pAttributes, "" for any the server did not return. Returns 0 if the query
/// itself failed -- including when a value cannot be converted, which fails
/// the whole poll, so callers keep attributes that might not convert in a
/// query of their own.
ClassMethod ReadAttributesOnce(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pAttributes As %List, Output pResults As %List) As %Boolean [ Private ]
{
	set pResults = ""
	set tEntries = $LB("")
	for i=1:1:$ListLength(pAttributes) {
		set tEntries = tEntries _ $LB($LB(2, "[TypeProbe].A"_$List(pAttributes, i), pNodeNS, pNodeId, $List(pAttributes, i)))
	}
	set tSpec = $LB("TypeProbe", "", tEntries)
	set tHandle = ""
	set tOK = 0
	Try {
		Quit:$$$ISERR(pClient.ReadBulkSetupC(.tHandle, .tSpec))
		Quit:$$$ISERR(pClient.ReadBulkPollC(.tPoll, tHandle))
		// $LB(errCode, result1, result2, ...)
		set pResults = $List(tPoll, 2, *)
		set tOK = 1
	} Catch (e) {
		set tOK = 0
	}
	if tHandle '= "" {
		Try { do pClient.ReadBulkClear(tHandle) } Catch (eClear) {}
	}
	Quit tOK
}

/// Map an OPC UA DataType to an OPCUA.Types class. pTypeNodeId is the numeric
/// id of a namespace-0 type (1 = Boolean ... 13 = DateTime, 21 = LocalizedText).
/// pDimensions is 0 for a scalar, 1 for an array, 2+ for a matrix.
/// Returns "" for a type this does not know, so the caller can fall back.
ClassMethod MapDataTypeToIRIS(pTypeNodeId As %Integer, pDimensions As %Integer = 0) As %String
{
	// A few standard subtypes that servers commonly declare instead of their base:
	// Duration, UtcTime, IntegerId, Counter, VersionTime, Enumeration (an Int32
	// on the wire), LocaleId, and the Normalized/Decimal/Duration/Time/DateString
	// string types.
	set tBase = pTypeNodeId
	if pTypeNodeId = 290 { set tBase = 11 }
	elseif pTypeNodeId = 294 { set tBase = 13 }
	elseif (pTypeNodeId = 288) || (pTypeNodeId = 289) || (pTypeNodeId = 20998) { set tBase = 7 }
	elseif pTypeNodeId = 29 { set tBase = 6 }
	elseif (pTypeNodeId = 295) || ((pTypeNodeId >= 12877) && (pTypeNodeId <= 12881)) { set tBase = 12 }

	// Scalar class, and the array class where one exists.
	if tBase = 1 { set tScalar = "BooleanDataValue", tArray = "Boolean" }
	elseif (tBase >= 2) && (tBase <= 9) { set tScalar = "IntegerDataValue", tArray = "Integer" }
	elseif tBase = 10 { set tScalar = "FloatDataValue", tArray = "Float" }
	elseif tBase = 11 { set tScalar = "DoubleDataValue", tArray = "Double" }
	elseif tBase = 12 { set tScalar = "StringDataValue", tArray = "String" }
	elseif tBase = 13 { set tScalar = "TimeStampDataValue", tArray = "TimeStamp" }
	elseif tBase = 16 { set tScalar = "StringDataValue", tArray = "String" }    // XmlElement
	elseif tBase = 19 { set tScalar = "IntegerDataValue", tArray = "Integer" }  // StatusCode
	elseif tBase = 17 { set tScalar = "NodeIdDataValue", tArray = "" }
	elseif tBase = 20 { set tScalar = "QualifiedNameDataValue", tArray = "" }
	elseif tBase = 21 { set tScalar = "LocalizedTextDataValue", tArray = "" }
	else { Quit "" }

	if pDimensions = 0 Quit "OPCUA.Types."_tScalar
	// A matrix, or an array of a type with no typed array class, is kept as the
	// generic list-of-lists.
	if (pDimensions > 1) || (tArray = "") Quit "OPCUA.Types.Multidimensional"
	Quit "OPCUA.Types.ArrayDataValue."_tArray
}

/// Guess the IRIS OPCUA.Types class from the node's current value. This is
/// the fallback behind <method>InferType</method>, for nodes whose declared
/// DataType is unknown to <method>MapDataTypeToIRIS</method>; it cannot tell a
/// Boolean from an integer, nor a Double of 0.0 from one.
/// Falls back to StringDataValue if the value is null or unreadable.
ClassMethod InferTypeFromValue(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer) As %String
{
	set tDefault = "OPCUA.Types.StringDataValue"
	Try {
		// Read the value attribute (attribute 13 - the only one the C++ layer supports)
		set tSC = pClient.ReadValueAttribute(.tResults, pNodeId, pNodeNS, pNodeIdType)
		if $$$ISERR(tSC) Quit

		// Result format: $LB(errCode, sourceTS, serverTS, status, value)
		if $ListLength(tResults) < 5 Quit
		if $LI(tResults, 1) '= 0 Quit

		set tValue = $LI(tResults, 5)

		// Null or empty value — can't infer
		if tValue = "" Quit

		// Check if the value is a $List (array type)
		if $ListValid(tValue) {
			// Array — peek at first element to determine element type
			if $ListLength(tValue) = 0 Quit
			set tFirst = $LI(tValue, 1)
			if tFirst = "" Quit
			if (tFirst = 1) || (tFirst = 0) {
				// Could be boolean array, but also integer 0/1 — prefer integer
				Quit  // fall through to default
			}
			if $Match(tFirst, "^-?\d+$") {
				set tDefault = "OPCUA.Types.ArrayDataValue.Integer"
				Quit
			}
			if $Match(tFirst, "^-?\d*\.\d+([eE][+-]?\d+)?$") || $Match(tFirst, "^-?\d+[eE][+-]?\d+$") {
				set tDefault = "OPCUA.Types.ArrayDataValue.Double"
				Quit
			}
			set tDefault = "OPCUA.Types.ArrayDataValue.String"
			Quit
		}

		// Scalar type inference
		// Boolean: exactly "true"/"false" or 0/1 from OPC UA booleans
		// Note: C++ layer converts booleans to 0/1, same as small integers.
		// We can't distinguish boolean from integer by value alone,
		// so we only match if the value is clearly non-numeric for string,
		// or numeric for integer/double.

		// Timestamp pattern: "YYYY-MM-DD HH:MM:SS[.fraction]" (ODBC format from C++ layer)
		// $Match requires full string match, so use .* to allow trailing fractional seconds
		if $Match(tValue, "^\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}.*") {
			set tDefault = "OPCUA.Types.TimeStampDataValue"
			Quit
		}

		// Pure integer (possibly negative)
		if $Match(tValue, "^-?\d+$") {
			// Known limitation: Double/Float values of 0.0 are canonicalized to "0"
			// by ObjectScript string conversion, making them indistinguishable from
			// integer 0 here. Non-zero doubles (e.g. 3.14) are correctly detected
			// below. Proper fix requires reading the OPC UA DataType attribute.
			set tDefault = "OPCUA.Types.IntegerDataValue"
			Quit
		}

		// Floating point (with decimal point or scientific notation)
		if $Match(tValue, "^-?\d*\.\d+([eE][+-]?\d+)?$") || $Match(tValue, "^-?\d+[eE][+-]?\d+$") || ($IsValidDouble(tValue) && (tValue '= +tValue)) {
			set tDefault = "OPCUA.Types.DoubleDataValue"
			Quit
		}

		// Everything else is a string
		set tDefault = "OPCUA.Types.StringDataValue"

	} Catch (e) {
		// Read failed — use default
	}
	Quit tDefault
}

/// Sanitize a node display name for use as an ObjectScript property name.
/// Replaces non-alphanumeric characters, handles leading digits, and deduplicates.
ClassMethod SanitizePropertyName(pName As %String, ByRef pUsedNames) As %String
{
	set tClean = ""
	set tPrevUnderscore = 0
	for i=1:1:$Length(pName) {
		set tChar = $Extract(pName, i)
		if (tChar ? 1A) || (tChar ? 1N) || (tChar = "_") {
			set tClean = tClean _ tChar
			set tPrevUnderscore = (tChar = "_")
		} else {
			// Replace with underscore, avoiding consecutive underscores
			if 'tPrevUnderscore && (tClean '= "") {
				set tClean = tClean _ "_"
				set tPrevUnderscore = 1
			}
		}
	}

	// Remove trailing underscores
	while ($Length(tClean) > 0) && ($Extract(tClean, *) = "_") {
		set tClean = $Extract(tClean, 1, *-1)
	}

	// Ensure doesn't start with a digit
	if ($Length(tClean) > 0) && ($Extract(tClean, 1) ? 1N) {
		set tClean = "N" _ tClean
	}

	// Fallback if empty
	if tClean = "" set tClean = "Node"

	// Truncate to reasonable length
	if $Length(tClean) > 96 set tClean = $Extract(tClean, 1, 96)

	// Deduplicate by appending counter suffix
	set tBase = tClean
	set tCounter = 1
	while $Data(pUsedNames(tClean)) {
		set tCounter = tCounter + 1
		set tClean = tBase _ tCounter
	}
	set pUsedNames(tClean) = 1

	Quit tClean
}

/// Determine the most common namespace among discovered nodes.
ClassMethod DetermineDefaultNamespace(ByRef pNodes, pNodeCount As %Integer, pFallback As %Integer) As %Integer [ Private ]
{
	if pNodeCount = 0 Quit pFallback

	// Count namespace frequency
	for i=1:1:pNodeCount {
		set tNS = $LI(pNodes(i), 1)
		if '$Data(tNSCount(tNS)) {
			set tNSCount(tNS) = 1
		} else {
			set tNSCount(tNS) = tNSCount(tNS) + 1
		}
	}

	// Find most common namespace
	set tMaxCount = 0
	set tMaxNS = pFallback
	set tNS = ""
	for {
		set tNS = $Order(tNSCount(tNS))
		if tNS = "" Quit
		if tNSCount(tNS) > tMaxCount {
			set tMaxCount = tNSCount(tNS)
			set tMaxNS = tNS
		}
	}

	Quit tMaxNS
}

/// Write the generated DataSource class definition to a .cls file.
ClassMethod GenerateClassFile(pClassName As %String, pDataSourceName As %String, pDefaultNS As %Integer, pOutputPath As %String, ByRef pNodes, pNodeCount As %Integer) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException

	Try {
		// Build file path: "Generated.PLCDataSource" -> "Generated/PLCDataSource.cls"
		set tFileName = $Translate(pClassName, ".", "/") _ ".cls"
		set tOutputDir = pOutputPath
		if $Extract(tOutputDir, *) '= "/" {
			set tOutputDir = tOutputDir _ "/"
		}
		set tFilePath = tOutputDir _ tFileName

		// Create directory chain if needed
		set tDir = ##class(%File).GetDirectory(tFilePath)
		if '##class(%File).DirectoryExists(tDir) {
			if '##class(%File).CreateDirectoryChain(tDir) {
				set tSC = $$$ERROR($$$GeneralError, "Failed to create directory: "_tDir)
				Quit
			}
		}

		// Open file stream for writing
		set tStream = ##class(%Stream.FileCharacter).%New()
		set tSC = tStream.LinkToFile(tFilePath)
		Quit:$$$ISERR(tSC)

		// Write class header
		do tStream.WriteLine("/// Auto-generated DataSource definition from OPC UA server browse.")
		do tStream.WriteLine("/// Review property types and adjust as needed (default: StringDataValue).")
		do tStream.WriteLine("Class "_pClassName_" Extends (%Persistent, OPCUA.DataSource.Definition)")
		do tStream.WriteLine("{")
		do tStream.WriteLine("")
		do tStream.WriteLine("Parameter OPCUADATASOURCE = """_pDataSourceName_""";")
		do tStream.WriteLine("")
		do tStream.WriteLine("Parameter OPCUDEFAULTANAMESPACE = "_pDefaultNS_";")

		// Write properties
		for i=1:1:pNodeCount {
			set tNodeInfo = pNodes(i)
			set tNodeNS = $LI(tNodeInfo, 1)
			set tNodeId = $LI(tNodeInfo, 2)
			set tNodeIdType = $LI(tNodeInfo, 3)
			set tDisplayName = $LI(tNodeInfo, 4)

			// Sanitize display name for property name
			set tPropName = ..SanitizePropertyName(tDisplayName, .tUsedNames)

			// Use inferred type from position 5, fall back to StringDataValue
			set tType = $LI(tNodeInfo, 5)
			if tType = "" set tType = "OPCUA.Types.StringDataValue"

			// Build property parameter list
			set tParams = "OPCUANODENAME = """_tNodeId_""""

			// Add explicit namespace if different from default
			if tNodeNS '= pDefaultNS {
				set tParams = tParams _ ", OPCUANAMESPACE = """_tNodeNS_""""
			}

			do tStream.WriteLine("")
			do tStream.WriteLine("Property "_tPropName_" As "_tType_"("_tParams_");")
		}

		do tStream.WriteLine("")
		do tStream.WriteLine("}")
		do tStream.WriteLine("")

		// Save the file
		set tSC = tStream.%Save()
		Quit:$$$ISERR(tSC)

		write "Generated: "_tFilePath, !
		write pNodeCount_" properties written.", !

	} Catch (e) {
		Set tSC = e.AsStatus()
	}

	Quit tSC
}

}
