Include (OPCUA.Constants, %occInclude)

/// Read a single OPC UA node value and return as JSON with type inference.
Class OPCUA.REST.ReadService
{

/// Read the value of a specified node.
/// Input: pBody with url, nodeNs (default 0), nodeId (required), nodeIdType (default 0)
/// Returns a %DynamicObject with value, timestamps, and inferred type.
ClassMethod Read(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim tClient As OPCUA.Client
	Try {
		// Extract connection params
		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass)
		Quit:$$$ISERR(tSC)

		// Node parameters
		set tNsVal = pBody.%Get("nodeNs")
		set tNodeNS = $Select(tNsVal="":0, 1:+tNsVal)
		set tNodeId = pBody.%Get("nodeId")
		if tNodeId = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing required parameter: nodeId")
			Quit
		}
		set tTypeVal = pBody.%Get("nodeIdType")
		set tNodeIdType = $Select(tTypeVal="":0, 1:+tTypeVal)

		// Auto-detect string vs numeric node ID
		if (tNodeIdType = 0) && ($Match(tNodeId, "^\d+$")) {
			set tNodeId = +tNodeId
		} elseif tNodeIdType = 0 {
			set tNodeIdType = $$$OpcuaNodeIdTypeString
		}

		// Connect
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass)
		Quit:$$$ISERR(tSC)

		// Read and parse — delegated to a separate method so its Try/Catch
		// reliably catches <NULL VALUE> from the C++ $ZF layer
		set tSC = ..SafeReadAndParse(tClient, tNodeNS, tNodeId, tNodeIdType, pBody.%Get("nodeId"), .pResult)
		Quit:$$$ISERR(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}

	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

/// Perform the read, type inference, and result parsing in an isolated method.
/// This ensures Try/Catch reliably catches $ZF errors from the C++ layer.
ClassMethod SafeReadAndParse(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer, pOrigNodeId As %String, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	set pResult.nodeNs = pNodeNS
	set pResult.nodeId = pOrigNodeId
	set pResult.nodeIdType = pNodeIdType

	// Step 1: Read value attribute
	set tReadOK = 0
	set tResults = ""
	set tSC = ..SafeReadValue(pClient, pNodeId, pNodeNS, pNodeIdType, .tResults, .tReadOK)

	// Step 2: Infer type (only if read succeeded)
	set tInferredType = ""
	if tReadOK {
		set tInferredType = ..SafeInferType(pClient, pNodeNS, pNodeId, pNodeIdType)
	}
	if tInferredType = "" set tInferredType = "OPCUA.Types.StringDataValue"

	// Step 3: Parse results
	if 'tReadOK {
		set pResult.value = ""
		set pResult.readError = "Failed to read node (node may not exist or has an unsupported type)"
		set pResult.inferredType = tInferredType
		Quit $$$OK
	}

	// Parse read results: $LB(errCode, sourceTS, serverTS, status, value)
	if $ListValid($Get(tResults)) && ($ListLength(tResults) >= 5) {
		set tErrCode = $ListGet(tResults, 1)
		if tErrCode = 0 {
			set pResult.value = ..SafeExtractValue($ListGet(tResults, 5))
			set pResult.sourceTimestamp = $ListGet(tResults, 2)
			set pResult.serverTimestamp = $ListGet(tResults, 3)
			set pResult.statusCode = $ListGet(tResults, 4)
		} else {
			set pResult.value = ""
			set pResult.readError = "Error code: "_tErrCode
		}
	} else {
		set pResult.value = ""
		set pResult.readError = "Unexpected result format"
	}

	set pResult.inferredType = tInferredType
	Quit $$$OK
}

/// Safely call ReadValueAttribute, catching any C++ layer exceptions.
ClassMethod SafeReadValue(pClient As OPCUA.Client, pNodeId, pNodeNS As %Integer, pNodeIdType As %Integer, Output pResults, Output pOK As %Boolean) As %Status
{
	set pOK = 0
	set pResults = ""
	Try {
		set tSC = pClient.ReadValueAttribute(.pResults, pNodeId, pNodeNS, pNodeIdType)
		if $$$ISOK(tSC) set pOK = 1
	} Catch (e) {
		set tSC = $$$OK
	}
	Quit tSC
}

/// Safely infer the OPCUA type, catching any exceptions.
ClassMethod SafeInferType(pClient As OPCUA.Client, pNodeNS As %Integer, pNodeId, pNodeIdType As %Integer) As %String
{
	set tType = ""
	Try {
		set tType = ##class(OPCUA.DataSource.Generator).InferTypeFromValue(pClient, pNodeNS, pNodeId, pNodeIdType)
	} Catch (e) {
		// Fall back to empty (caller defaults to StringDataValue)
	}
	Quit tType
}

/// Safely extract value from read results, converting arrays to JSON.
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
