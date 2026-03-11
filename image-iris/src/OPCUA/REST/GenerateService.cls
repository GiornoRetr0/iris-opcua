Include (OPCUA.Constants, %occInclude)

/// Trigger DataSource class generation via REST and return JSON result.
Class OPCUA.REST.GenerateService
{

/// Generate a DataSource class from an OPC UA server.
/// Input: pBody with url, className, dataSourceName, outputPath,
///        optional startNodeNs, startNodeId, startNodeIdType, securityMode,
///        username, password, maxDepth
/// Returns a %DynamicObject with generation results.
ClassMethod Generate(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		// Required parameters
		set tURL = pBody.%Get("url")
		if tURL = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing required parameter: url")
			Quit
		}
		set tClassName = pBody.%Get("className")
		if tClassName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing required parameter: className")
			Quit
		}
		set tDataSourceName = pBody.%Get("dataSourceName")
		if tDataSourceName = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing required parameter: dataSourceName")
			Quit
		}
		set tOutputPath = pBody.%Get("outputPath")
		if tOutputPath = "" {
			set tSC = $$$ERROR($$$GeneralError, "Missing required parameter: outputPath")
			Quit
		}

		// Optional parameters with defaults
		set tVal = pBody.%Get("startNodeNs")
		set tStartNodeNS = $Select(tVal="":0, 1:+tVal)
		set tVal = pBody.%Get("startNodeId")
		set tStartNodeId = $Select(tVal="":84, 1:tVal)
		set tVal = pBody.%Get("startNodeIdType")
		set tStartNodeIdType = $Select(tVal="":0, 1:+tVal)
		set tVal = pBody.%Get("securityMode")
		set tSecurityMode = $Select(tVal="":1, +tVal=0:1, 1:+tVal)
		set tVal = pBody.%Get("maxDepth")
		set tMaxDepth = $Select(tVal="":20, +tVal=0:20, 1:+tVal)
		set tVal = pBody.%Get("username")
		set tUsername = $Select(tVal="":"", 1:tVal)
		set tVal = pBody.%Get("password")
		set tPassword = $Select(tVal="":"", 1:tVal)

		// Auto-detect string vs numeric start node ID
		if (tStartNodeIdType = 0) && ($Match(tStartNodeId, "^\d+$")) {
			set tStartNodeId = +tStartNodeId
		} elseif tStartNodeIdType = 0 {
			set tStartNodeIdType = $$$OpcuaNodeIdTypeString
		}

		// Redirect write output so it doesn't pollute the response
		set tOldIO = $IO
		set tNullDev = $Select($ZVersion["Windows":"//./nul", 1:"/dev/null")
		open tNullDev:"w"
		use tNullDev

		// Call the existing Generator
		set tSC = ##class(OPCUA.DataSource.Generator).Generate(
			tURL, tStartNodeNS, tStartNodeId,
			tClassName, tDataSourceName, tOutputPath,
			tStartNodeIdType, tSecurityMode, tMaxDepth,
			tUsername, tPassword)

		// Restore IO
		use tOldIO
		close tNullDev

		// Build result
		set pResult = {}
		set pResult.className = tClassName
		set pResult.dataSourceName = tDataSourceName
		set pResult.outputPath = tOutputPath

		if $$$ISERR(tSC) {
			set pResult.generated = 0
			set pResult.error = $System.Status.GetErrorText(tSC)
			// Report error in JSON but return OK status for proper envelope
			set tSC = $$$OK
		} else {
			set pResult.generated = 1
			// Compute expected file path
			set tFileName = $Translate(tClassName, ".", "/") _ ".cls"
			set tDir = tOutputPath
			if $Extract(tDir, *) '= "/" set tDir = tDir _ "/"
			set pResult.filePath = tDir _ tFileName
		}

	} Catch (e) {
		// Make sure IO is restored even on exception
		Try { use tOldIO close tNullDev } Catch (e2) {}
		set tSC = e.AsStatus()
	}

	Quit tSC
}

}
