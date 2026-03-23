Include (OPCUA.Constants, %occInclude)

/// Browse OPC UA node children and return JSON array for lazy-loading tree.
Class OPCUA.REST.BrowseService
{

/// Browse children of the specified node.
/// Input: pBody with url, optional nodeNs (default 0), nodeId (default 84=Root/Objects),
///        nodeIdType (default 0=numeric)
/// Returns a %DynamicArray of child node objects.
ClassMethod Browse(pBody As %DynamicObject, Output pResult As %DynamicArray) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim tClient As OPCUA.Client
	Try {
		// Extract connection params
		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass, .tCert, .tKey, .tTrust, .tCrl, .tClientURI)
		Quit:$$$ISERR(tSC)

		// Node parameters with defaults (Root/Objects folder)
		set tNsVal = pBody.%Get("nodeNs")
		set tNodeNS = $Select(tNsVal="":0, 1:+tNsVal)
		set tIdVal = pBody.%Get("nodeId")
		set tNodeId = $Select(tIdVal="":84, 1:tIdVal)
		set tTypeVal = pBody.%Get("nodeIdType")
		set tNodeIdType = $Select(tTypeVal="":0, 1:+tTypeVal)

		// If nodeId looks numeric and type is not explicitly string, use numeric
		if (tNodeIdType = 0) && ($Match(tNodeId, "^\d+$")) {
			set tNodeId = +tNodeId
		} elseif tNodeIdType = 0 {
			set tNodeIdType = $$$OpcuaNodeIdTypeString
		}

		// Connect
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)
		Quit:$$$ISERR(tSC)

		// Browse
		set tSC = tClient.Browse(.tResults, $LB(tNodeIdType), $LB(tNodeNS), $LB(tNodeId))
		if $$$ISERR(tSC) Quit

		// Parse results into JSON array
		set pResult = ..ParseBrowseResults(tResults)

	} Catch (e) {
		set tSC = e.AsStatus()
	}

	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

/// Parse raw browse results from C++ layer into a %DynamicArray of node objects.
/// Uses the 3-axis classification model: referenceType + typeDefinition + nodeClass(inferred).
///
/// C++ browse reference list positions:
///   [1] referenceTypeId (NodeId: ns, id, idType)
///   [2] isForward (boolean)
///   [3] nodeId (ExpandedNodeId: ns, id, idType, ...)
///   [4] browseName (QualifiedName: name, ns)
///   [5] displayName (LocalizedText: text, locale)
///   [6] nodeClass (empty — not exported by C++)
///   [7] typeDefinition (ExpandedNodeId: ns, id, idType, ...)
ClassMethod ParseBrowseResults(pResults As %List) As %DynamicArray [ Private ]
{
	set tArray = []
	Try {
		set tBrowseData = $LI(pResults, 4)
		set tFirstResult = $LI(tBrowseData, 1)
		set tRefList = $LI(tFirstResult, 4)
		set tRefCount = $LL(tRefList)

		for i=1:1:tRefCount {
			set tRef = $LI(tRefList, i)

			// --- Reference type (how child relates to parent) ---
			set tRefTypeInfo = $LI(tRef, 1)
			set tRefTypeNS = $LI(tRefTypeInfo, 1)
			set tRefTypeId = $LI(tRefTypeInfo, 2)

			// Skip HasTypeDefinition references (ns=0, id=40)
			if (tRefTypeNS = 0) && (tRefTypeId = 40) continue
			// Skip HasSubtype references (ns=0, id=45)
			if (tRefTypeNS = 0) && (tRefTypeId = 45) continue

			// Classify the reference type
			set tRefType = ..ClassifyReferenceType(tRefTypeNS, tRefTypeId)

			// --- Node identity ---
			set tNodeInfo = $LI(tRef, 3)
			set tChildNS = $LI(tNodeInfo, 1)
			set tChildId = $LI(tNodeInfo, 2)
			set tChildIdType = $LI(tNodeInfo, 3)

			// --- Display name: prefer displayName [5], fall back to browseName [4] ---
			set tDisplayText = ""
			Try {
				set tDisplayInfo = $LI(tRef, 5)
				if $ListValid($Get(tDisplayInfo)) set tDisplayText = $LI(tDisplayInfo, 1)
			} Catch (ex) {}
			if tDisplayText = "" {
				set tBrowseInfo = $LI(tRef, 4)
				set tDisplayText = $LI(tBrowseInfo, 1)
			}
			if tDisplayText = "" set tDisplayText = "Node"_tChildId

			// --- Type definition (what kind of Object/Variable) ---
			set tTypeDefNS = ""
			set tTypeDefId = ""
			Try {
				set tTypeDefInfo = $LI(tRef, 7)
				if $ListValid($Get(tTypeDefInfo)) {
					set tTypeDefNS = $LI(tTypeDefInfo, 1)
					set tTypeDefId = $LI(tTypeDefInfo, 2)
				}
			} Catch (ex) {}

			// --- 3-axis classification ---
			set tCategory = ..ClassifyNode(tRefType, tTypeDefNS, tTypeDefId)

			set tNode = {}
			set tNode.displayName = tDisplayText
			set tNode.nodeNs = tChildNS
			set tNode.nodeId = tChildId
			set tNode.nodeIdType = tChildIdType
			set tNode.nodeCategory = tCategory
			set tNode.referenceType = tRefType
			set tNode.typeDefNs = tTypeDefNS
			set tNode.typeDefId = tTypeDefId
			set tNode.hasChildren = ..CategoryHasChildren(tCategory)

			do tArray.%Push(tNode)
		}
	} Catch (e) {
		// Return whatever we have so far
	}
	Quit tArray
}

/// Classify the reference type from its NodeId.
/// Standard reference type IDs (ns=0):
///   35=Organizes, 46=HasProperty, 47=HasComponent, 49=HasOrderedComponent
///   44=Aggregates, 36=HasEventSource, 48=HasNotifier
ClassMethod ClassifyReferenceType(pNS As %Integer, pId) As %String [ Private ]
{
	if pNS '= 0 Quit "HasComponent"
	if pId = 46 Quit "HasProperty"
	if pId = 35 Quit "Organizes"
	if (pId = 47) || (pId = 49) Quit "HasComponent"
	if pId = 36 Quit "HasEventSource"
	if pId = 48 Quit "HasNotifier"
	// Other hierarchical references default to HasComponent
	Quit "HasComponent"
}

/// Classify a node into a UI category using referenceType + typeDefinition.
/// Categories: "folder", "object", "variable", "property", "method", "view"
///
/// Key TypeDefinition IDs (ns=0):
///   FolderType=61, BaseObjectType=58
///   BaseVariableType=62, BaseDataVariableType=63, PropertyType=68
///   DataItemType=2365, AnalogItemType=2368, DiscreteItemType=2372
///   TwoStateDiscreteType=2373, MultiStateDiscreteType=2376
///   See full list in research doc.
ClassMethod ClassifyNode(pRefType As %String, pTypeDefNS, pTypeDefId) As %String [ Private ]
{
	// Properties are always metadata regardless of TypeDefinition
	if pRefType = "HasProperty" Quit "property"

	// No type definition info — fall back to reference type heuristic
	if (pTypeDefNS = "") || (pTypeDefId = "") || (pTypeDefId = 0) {
		if pRefType = "Organizes" Quit "folder"
		Quit "object"
	}

	// Standard namespace (ns=0) — use well-known TypeDefinition IDs
	if pTypeDefNS = 0 {
		// FolderType and subtypes
		if pTypeDefId = 61 Quit "folder"

		// PropertyType (should have been caught by HasProperty above, but just in case)
		if pTypeDefId = 68 Quit "property"

		// Variable types: BaseVariableType(62), BaseDataVariableType(63),
		// and all data-bearing subtypes
		if ..IsVariableTypeDef(pTypeDefId) Quit "variable"

		// Everything else in ns=0 is an Object type
		Quit "object"
	}

	// Custom namespace — use reference type as hint
	if pRefType = "Organizes" Quit "folder"
	// Custom types via HasComponent are likely variables (vendor data points)
	Quit "variable"
}

/// Check if a TypeDefinition ID (ns=0) is a variable type.
/// Covers BaseVariableType, BaseDataVariableType, and all standard
/// data-bearing VariableType subtypes from the OPC UA specification.
ClassMethod IsVariableTypeDef(pTypeDefId As %Integer) As %Boolean [ Private ]
{
	// Core variable types
	if (pTypeDefId = 62) Quit 1   ; BaseVariableType
	if (pTypeDefId = 63) Quit 1   ; BaseDataVariableType

	// DataType description/dictionary (metadata variables, but still Variable class)
	if (pTypeDefId = 69) || (pTypeDefId = 72) Quit 1

	// Server/diagnostic variable types
	if (pTypeDefId >= 2137) && (pTypeDefId <= 2244) Quit 1

	// DataAccess variable types: DataItemType..MultiStateDiscreteType
	if (pTypeDefId = 2365) Quit 1  ; DataItemType
	if (pTypeDefId = 2368) Quit 1  ; AnalogItemType
	if (pTypeDefId = 2372) Quit 1  ; DiscreteItemType
	if (pTypeDefId = 2373) Quit 1  ; TwoStateDiscreteType
	if (pTypeDefId = 2376) Quit 1  ; MultiStateDiscreteType
	if (pTypeDefId = 2380) Quit 1  ; ProgramDiagnosticType

	// State machine variable types
	if (pTypeDefId = 2755) || (pTypeDefId = 2760) Quit 1  ; StateVariableType, FiniteStateVariableType
	if (pTypeDefId = 2762) || (pTypeDefId = 2767) Quit 1  ; TransitionVariableType, FiniteTransitionVariableType

	// BuildInfoType
	if (pTypeDefId = 3051) Quit 1

	// TwoStateVariableType, ConditionVariableType
	if (pTypeDefId = 8995) || (pTypeDefId = 9002) Quit 1

	// MultiStateValueDiscreteType, OptionSetType
	if (pTypeDefId = 11238) || (pTypeDefId = 11487) Quit 1

	// ArrayItemType family
	if (pTypeDefId >= 12021) && (pTypeDefId <= 12068) Quit 1

	// Guard variables, BaseAnalogType, ProgramDiagnostic2Type
	if (pTypeDefId = 15113) || (pTypeDefId = 15128) || (pTypeDefId = 15317) Quit 1
	if (pTypeDefId = 15318) || (pTypeDefId = 15383) Quit 1

	// SelectionListType, AlarmRateVariableType
	if (pTypeDefId = 16309) || (pTypeDefId = 17277) Quit 1

	// AnalogUnitType, AnalogUnitRangeType
	if (pTypeDefId = 17497) || (pTypeDefId = 17570) Quit 1

	// RationalNumberType, VectorType, ThreeDVectorType
	if (pTypeDefId = 17709) || (pTypeDefId = 17714) || (pTypeDefId = 17716) Quit 1

	// AudioVariableType
	if (pTypeDefId = 17986) Quit 1

	// Coordinate/orientation/frame types
	if (pTypeDefId >= 18772) && (pTypeDefId <= 18791) Quit 1

	// MultiStateDictionary types
	if (pTypeDefId = 19077) || (pTypeDefId = 19084) Quit 1

	// PubSubDiagnosticsCounterType
	if (pTypeDefId = 19725) Quit 1

	Quit 0
}

/// Determine if a node category should be expandable in the tree.
ClassMethod CategoryHasChildren(pCategory As %String) As %Boolean [ Private ]
{
	if (pCategory = "folder") || (pCategory = "object") Quit 1
	// Variables can have child properties (e.g., EURange under AnalogItemType)
	if pCategory = "variable" Quit 1
	Quit 0
}

}
