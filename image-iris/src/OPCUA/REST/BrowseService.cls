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

/// Walk the raw browse result list from the C++ layer and return one entry per
/// child reference. This is the single shared decoding of the C++ browse wire
/// format: <method>ParseBrowseResults</method> renders it as JSON for the REST
/// API, and <class>OPCUA.DataSource.Resolver</class> uses it to match children
/// by name at runtime. Keeping one walk means the REST and runtime views of a
/// server cannot drift apart.
///
/// C++ browse reference list positions:
///   [1] referenceTypeId (NodeId: ns, id, idType)
///   [2] isForward (boolean)
///   [3] nodeId (ExpandedNodeId: ns, id, idType, ...)
///   [4] browseName (QualifiedName: name, ns)
///   [5] displayName (LocalizedText: text, locale)
///   [6] nodeClass (UA_NodeClass as Int32 — see <method>ClassifyNode</method>)
///   [7] typeDefinition (ExpandedNodeId: ns, id, idType, ...)
///
/// Output: pChildren(i) = $LB(browseName, displayName, ns, id, idType, category, refType, nodeClass)
/// where browseName and displayName are kept SEPARATE (unlike the JSON view, which
/// collapses them) because name-based resolution prefers the stable BrowseName.
/// nodeClass is appended last so existing callers reading positions 1-7 are unaffected.
ClassMethod WalkBrowseResults(pResults As %List, Output pChildren) As %Integer
{
	kill pChildren
	set tCount = 0
	Try {
		set tBrowseData = $LI(pResults, 4)
		set tFirstResult = $LI(tBrowseData, 1)
		set tRefList = $LI(tFirstResult, 4)

		for i=1:1:$LL(tRefList) {
			set tRef = $LI(tRefList, i)

			// --- Reference type (how child relates to parent) ---
			set tRefTypeInfo = $LI(tRef, 1)
			set tRefTypeNS = $LI(tRefTypeInfo, 1)
			set tRefTypeId = $LI(tRefTypeInfo, 2)

			// Skip HasTypeDefinition references (ns=0, id=40)
			if (tRefTypeNS = 0) && (tRefTypeId = 40) continue
			// Skip HasSubtype references (ns=0, id=45)
			if (tRefTypeNS = 0) && (tRefTypeId = 45) continue

			set tRefType = ..ClassifyReferenceType(tRefTypeNS, tRefTypeId)

			// --- Node identity ---
			set tNodeInfo = $LI(tRef, 3)
			set tChildNS = $LI(tNodeInfo, 1)
			set tChildId = $LI(tNodeInfo, 2)
			set tChildIdType = $LI(tNodeInfo, 3)

			// --- BrowseName [4]: the stable, non-localized identifier ---
			set tBrowseName = ""
			Try {
				set tBrowseInfo = $LI(tRef, 4)
				if $ListValid($Get(tBrowseInfo)) set tBrowseName = $LI(tBrowseInfo, 1)
			} Catch (ex) {}

			// --- DisplayName [5]: localized presentation text ---
			set tDisplayName = ""
			Try {
				set tDisplayInfo = $LI(tRef, 5)
				if $ListValid($Get(tDisplayInfo)) set tDisplayName = $LI(tDisplayInfo, 1)
			} Catch (ex) {}

			// --- NodeClass [6]: the server's own answer, when the library gives it ---
			// Older prebuilt binaries predate the UA2CL_ReferenceDescription export of
			// this field and leave it empty; ClassifyNode falls back to inference then.
			set tNodeClass = ""
			Try {
				set tNodeClass = $LI(tRef, 6)
			} Catch (ex) {}

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

			set tCategory = ..ClassifyNode(tRefType, tTypeDefNS, tTypeDefId, tNodeClass)

			set tCount = tCount + 1
			set pChildren(tCount) = $LB(tBrowseName, tDisplayName, tChildNS, tChildId, tChildIdType, tCategory, tRefType, tNodeClass)
			set pChildren(tCount, "typeDefNs") = tTypeDefNS
			set pChildren(tCount, "typeDefId") = tTypeDefId
		}
	} Catch (e) {
		// Return whatever we have so far
	}
	Quit tCount
}

/// Parse raw browse results from C++ layer into a %DynamicArray of node objects.
/// Uses the 3-axis classification model: nodeClass + referenceType + typeDefinition.
/// Decoding is delegated to <method>WalkBrowseResults</method>; this method only
/// shapes the result as JSON for the REST API.
ClassMethod ParseBrowseResults(pResults As %List) As %DynamicArray [ Private ]
{
	set tArray = []
	Try {
		set tCount = ..WalkBrowseResults(pResults, .tChildren)

		for i=1:1:tCount {
			set tChild = tChildren(i)
			set tChildNS = $LI(tChild, 3)
			set tChildId = $LI(tChild, 4)

			// Display name: prefer displayName, fall back to browseName (unchanged behaviour)
			set tDisplayText = $LI(tChild, 2)
			if tDisplayText = "" set tDisplayText = $LI(tChild, 1)
			if tDisplayText = "" set tDisplayText = "Node"_tChildId

			set tCategory = $LI(tChild, 6)

			set tNode = {}
			set tNode.displayName = tDisplayText
			set tNode.nodeNs = tChildNS
			set tNode.nodeId = tChildId
			set tNode.nodeIdType = $LI(tChild, 5)
			set tNode.nodeCategory = tCategory
			set tNode.referenceType = $LI(tChild, 7)
			// The raw UA_NodeClass, for callers that want the spec value rather than
			// this UI's categories. "" when the library did not report one.
			set tNode.nodeClass = $LI(tChild, 8)
			set tNode.typeDefNs = tChildren(i, "typeDefNs")
			set tNode.typeDefId = tChildren(i, "typeDefId")
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

/// Classify a node into a UI category using nodeClass + referenceType + typeDefinition.
/// Categories: "folder", "object", "variable", "property", "method". A View is
/// reported as "folder", since to a browsing user it behaves as one.
///
/// pNodeClass is the server's own UA_NodeClass, and it is authoritative about the
/// coarse kind — a Method is a Method no matter what references point at it. Where
/// OPC UA's node classes are coarser than the categories this UI needs, the older
/// TypeDefinition heuristics still do the refining: Object splits into
/// folder-vs-object, Variable into variable-vs-property.
///
/// It stays optional. Prebuilt binaries older than the
/// <method>UA2CL_ReferenceDescription</method> nodeClass export send "" here, so
/// an empty value falls through to inferring the kind exactly as before.
///
/// UA_NodeClass values: 1=Object, 2=Variable, 4=Method, 8=ObjectType,
/// 16=VariableType, 32=ReferenceType, 64=DataType, 128=View
///
/// Key TypeDefinition IDs (ns=0):
///   FolderType=61, BaseObjectType=58
///   BaseVariableType=62, BaseDataVariableType=63, PropertyType=68
///   DataItemType=2365, AnalogItemType=2368, DiscreteItemType=2372
///   TwoStateDiscreteType=2373, MultiStateDiscreteType=2376
///   See full list in research doc.
ClassMethod ClassifyNode(pRefType As %String, pTypeDefNS, pTypeDefId, pNodeClass As %Integer = "") As %String [ Private ]
{
	// --- Node classes the heuristics could never identify on their own ---
	if pNodeClass = $$$OpcuaNodeClassMethod Quit "method"
	if pNodeClass = $$$OpcuaNodeClassView Quit "folder"

	// A type-definition node (ObjectType, VariableType, ReferenceType, DataType) is
	// a schema node, not an instance. Reached only when browsing the type hierarchy,
	// since WalkBrowseResults drops HasTypeDefinition/HasSubtype references.
	if (pNodeClass = $$$OpcuaNodeClassObjectType) || (pNodeClass = $$$OpcuaNodeClassVariableType) Quit "object"
	if (pNodeClass = $$$OpcuaNodeClassReferenceType) || (pNodeClass = $$$OpcuaNodeClassDataType) Quit "object"

	// --- Variable: split into variable vs property ---
	if pNodeClass = $$$OpcuaNodeClassVariable {
		if pRefType = "HasProperty" Quit "property"
		if (pTypeDefNS = 0) && (pTypeDefId = 68) Quit "property"
		Quit "variable"
	}

	// --- Object: split into folder vs object ---
	if pNodeClass = $$$OpcuaNodeClassObject {
		if (pTypeDefNS = 0) && (pTypeDefId = 61) Quit "folder"
		// No usable TypeDefinition — Organizes implies a folder-like grouping.
		if (pTypeDefNS = "") || (pTypeDefId = "") || (pTypeDefId = 0) {
			if pRefType = "Organizes" Quit "folder"
		}
		Quit "object"
	}

	// --- No nodeClass from the library: infer it, as before ---

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
	// Methods carry InputArguments/OutputArguments as HasProperty children.
	if pCategory = "method" Quit 1
	// A property is a leaf.
	Quit 0
}

}
