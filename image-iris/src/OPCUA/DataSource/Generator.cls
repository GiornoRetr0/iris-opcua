Include (OPCUA.Constants, Ensemble)

/// Auto-generates DataSource class definitions by browsing an OPC UA server.
/// Connects to the server, walks the node tree depth-first from a start node,
/// and produces a ready-to-use .cls file with properties mapped to discovered
/// variable nodes. Types are inferred by reading each node's current value
/// (integer, double, boolean, timestamp, string, or array variants).
/// Review the generated file and adjust any types that could not be determined.
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

/// Add a variable node to the collection. Infers the IRIS type by reading
/// the node's current value.
ClassMethod ProcessVariableNode(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer, pDisplayName As %String, ByRef pNodes, ByRef pNodeCount As %Integer) [ Private ]
{
	set tType = ..InferTypeFromValue(pClient, pNodeNS, pNodeId, pNodeIdType)
	set pNodeCount = $Get(pNodeCount, 0) + 1
	set pNodes(pNodeCount) = $LB(pNodeNS, pNodeId, pNodeIdType, pDisplayName, tType)
}

/// Map an OPC UA data type NodeId (ns=0) to an OPCUA.Types class name.
/// For future use when C++ layer supports reading the DataType attribute.
ClassMethod MapDataTypeToIRIS(pTypeNodeId As %Integer) As %String
{
	if pTypeNodeId = 1 Quit "OPCUA.Types.BooleanDataValue"
	if (pTypeNodeId >= 2) && (pTypeNodeId <= 9) Quit "OPCUA.Types.IntegerDataValue"
	if pTypeNodeId = 10 Quit "OPCUA.Types.FloatDataValue"
	if pTypeNodeId = 11 Quit "OPCUA.Types.DoubleDataValue"
	if pTypeNodeId = 12 Quit "OPCUA.Types.StringDataValue"
	if pTypeNodeId = 13 Quit "OPCUA.Types.TimeStampDataValue"
	Quit "OPCUA.Types.StringDataValue"
}

/// Infer the IRIS OPCUA.Types class by reading the node's current value.
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
