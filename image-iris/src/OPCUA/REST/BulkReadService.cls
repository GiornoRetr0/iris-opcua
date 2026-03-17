Include (OPCUA.Constants, %occInclude)

/// Read multiple OPC UA node values in a single bulk operation.
/// Uses ReadBulkSetupC / ReadBulkPollC / ReadBulkClear for efficiency.
Class OPCUA.REST.BulkReadService
{

/// Read values for an array of nodes in one connection.
/// Input: pBody with url, securityMode, nodes (array of {nodeNs, nodeId, nodeIdType})
/// Returns a %DynamicObject with nodes array containing values, timestamps, and status.
ClassMethod ReadBulk(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim tClient As OPCUA.Client
	Try {
		// Extract connection params
		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass, .tCert, .tKey, .tTrust, .tCrl, .tClientURI)
		Quit:$$$ISERR(tSC)

		// Validate nodes array
		set tNodes = pBody.%Get("nodes")
		if '$IsObject($Get(tNodes)) || (tNodes.%Size() = 0) {
			set tSC = $$$ERROR($$$GeneralError, "Missing or empty required parameter: nodes")
			Quit
		}

		set tNodeCount = tNodes.%Size()

		// Build node list with auto-detection (same logic as ReadService)
		// Store processed node info for response building
		for i=0:1:tNodeCount-1 {
			set tNode = tNodes.%Get(i)
			if '$IsObject($Get(tNode)) {
				set tSC = $$$ERROR($$$GeneralError, "Invalid node entry at index "_i)
				Quit
			}

			set tNsVal = tNode.%Get("nodeNs")
			set tNodeNS(i) = $Select(tNsVal="":0, 1:+tNsVal)
			set tOrigNodeId(i) = tNode.%Get("nodeId")
			if tOrigNodeId(i) = "" {
				set tSC = $$$ERROR($$$GeneralError, "Missing nodeId at index "_i)
				Quit
			}
			set tTypeVal = tNode.%Get("nodeIdType")
			set tNodeIdType(i) = $Select(tTypeVal="":0, 1:+tTypeVal)

			// Auto-detect string vs numeric node ID
			set tNodeId(i) = tOrigNodeId(i)
			if (tNodeIdType(i) = 0) && ($Match(tOrigNodeId(i), "^\d+$")) {
				set tNodeId(i) = +tOrigNodeId(i)
			} elseif tNodeIdType(i) = 0 {
				set tNodeIdType(i) = $$$OpcuaNodeIdTypeString
			}
		}
		Quit:$$$ISERR(tSC)

		// Build specification for ReadBulkSetupC
		// Format: $LB(dataSourceName, storageGlobal, $LB("") _ nodeSpecs)
		// Each node spec: $LB(entryType, propertyPath, namespace, nodeName, attributeId)
		set tNodeSpecs = ""
		for i=0:1:tNodeCount-1 {
			set tEntry = $LB(2, "[BulkRead].Node"_(i+1), tNodeNS(i), tNodeId(i), $$$OpcuaAttributeValue)
			set tNodeSpecs = tNodeSpecs _ $LB(tEntry)
		}
		set tSpec = $LB("_BulkRead", "", $LB("") _ tNodeSpecs)

		// Connect
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)
		Quit:$$$ISERR(tSC)

		// Execute bulk read in isolated method
		set tSC = ..SafeBulkRead(tClient, tSpec, tNodeCount, .tResults, .tQueryHandle)

		// Clean up query handle
		if $Get(tQueryHandle) > 0 {
			Try { do tClient.ReadBulkClear(tQueryHandle) } Catch (ex) {}
		}
		Quit:$$$ISERR(tSC)

		// Build response
		set pResult = {}
		set tResultNodes = []
		for i=0:1:tNodeCount-1 {
			set tResultNode = {}
			set tResultNode.nodeNs = tNodeNS(i)
			set tResultNode.nodeId = tOrigNodeId(i)
			set tResultNode.nodeIdType = tNodeIdType(i)

			// Parse per-node result from ReadBulkPollC
			// tResults = $LB(errCode, dataVal1, dataVal2, ...)
			// Each dataVal = $LB(sourceTS, serverTS, status, value)
			set tDataVal = $ListGet(tResults, i + 2)
			if $ListValid($Get(tDataVal)) && ($ListLength(tDataVal) >= 4) {
				set tResultNode.value = ..SafeExtractValue($ListGet(tDataVal, 4))
				set tResultNode.sourceTimestamp = $ListGet(tDataVal, 1)
				set tResultNode.serverTimestamp = $ListGet(tDataVal, 2)
				set tResultNode.statusCode = $ListGet(tDataVal, 3)
			} else {
				set tResultNode.value = ""
				set tResultNode.sourceTimestamp = ""
				set tResultNode.serverTimestamp = ""
				set tResultNode.statusCode = 0
				set tResultNode.readError = "Failed to read node value"
			}
			do tResultNodes.%Push(tResultNode)
		}
		set pResult.nodes = tResultNodes

	} Catch (e) {
		set tSC = e.AsStatus()
	}

	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

/// Perform the bulk read in an isolated method to catch $ZF exceptions.
ClassMethod SafeBulkRead(pClient As OPCUA.Client, pSpec As %List, pNodeCount As %Integer, Output pResults As %List, Output pQueryHandle As %Integer) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResults = ""
	set pQueryHandle = 0
	Try {
		set tSC = pClient.ReadBulkSetupC(.pQueryHandle, pSpec)
		Quit:$$$ISERR(tSC)

		set tSC = pClient.ReadBulkPollC(.pResults, pQueryHandle)
		Quit:$$$ISERR(tSC)

		// Check top-level error code
		if $ListValid($Get(pResults)) && ($ListLength(pResults) >= 1) {
			set tErrCode = $ListGet(pResults, 1)
			if tErrCode '= 0 {
				set tSC = $$$ERROR($$$GeneralError, "Bulk read error code: "_tErrCode)
			}
		}
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Safely extract value from read results, converting $List arrays to JSON arrays.
ClassMethod SafeExtractValue(pValue) As %DynamicAbstractObject
{
	set tResult = pValue
	Try {
		if $ListValid(pValue) && ($ListLength(pValue) > 0) {
			set tArr = []
			for i=1:1:$ListLength(pValue) {
				do tArr.%Push($ListGet(pValue, i))
			}
			set tResult = tArr
		}
	} Catch (e) {
		// Fall through to return raw value
	}
	Quit tResult
}

}
