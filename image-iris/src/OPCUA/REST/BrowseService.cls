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
		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass)
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
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass)
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

			// Skip HasTypeDefinition references (ns=0, id=40)
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
			if tChildName = "" set tChildName = "Node"_tChildId

			// Classify using type definition
			set tClass = ##class(OPCUA.DataSource.Generator).ClassifyByTypeDef($LI(tRef, 7))

			set tNode = {}
			set tNode.displayName = tChildName
			set tNode.nodeNs = tChildNS
			set tNode.nodeId = tChildId
			set tNode.nodeIdType = tChildIdType
			set tNode.nodeClass = tClass
			set tNode.hasChildren = (tClass = "Object")

			do tArray.%Push(tNode)
		}
	} Catch (e) {
		// Return whatever we have so far
	}
	Quit tArray
}

}
