Include (OPCUA.Constants, %occInclude)

/// Test OPC UA server connectivity and return response time.
Class OPCUA.REST.ConnectionService
{

/// Test connection to an OPC UA server.
/// Input: pBody with url, optional securityMode, username, password
/// Returns a %DynamicObject with connected status and response time in ms.
ClassMethod Test(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	#dim tClient As OPCUA.Client
	Try {
		// Extract connection params
		set tSC = ##class(OPCUA.REST.ClientManager).ExtractConnectionParams(pBody, .tURL, .tSecMode, .tUser, .tPass, .tCert, .tKey, .tTrust, .tCrl, .tClientURI)
		Quit:$$$ISERR(tSC)

		// Measure connection time
		set tStart = $ZH

		// Connect
		set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)

		set tElapsed = $ZH - tStart
		set tElapsedMs = $FNumber(tElapsed * 1000, "", 0)

		set pResult = {}
		set pResult.url = tURL
		set pResult.responseTimeMs = +tElapsedMs

		if $$$ISERR(tSC) {
			set pResult.connected = 0
			set pResult.error = $System.Status.GetErrorText(tSC)
			// Reset status — we report the error in the JSON body
			set tSC = $$$OK
		} else {
			set pResult.connected = 1
		}

	} Catch (e) {
		set tSC = e.AsStatus()
	}

	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

}
