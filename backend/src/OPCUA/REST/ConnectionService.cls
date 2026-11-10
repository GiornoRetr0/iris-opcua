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

		// Managed Sign & Encrypt (mode 3, no certificate or key path of the caller's
		// own): IRIS's identity and the server's pin decide, and a refusal is reported
		// here, never answered by trying an unsecured session.
		set tManaged = ##class(OPCUA.Security.Connection).IsManaged(tSecMode, tCert, tKey)
		set tSecurity = ""
		set tRefusal = $$$OK
		if tManaged {
			set tSecurity = {"managed": 1, "identityReady": 0, "serverTrusted": 0}
			set tRefusal = ##class(OPCUA.Security.Connection).Resolve(tURL, tSecMode, tClientURI, tCert, tKey, tTrust, tCrl, .tArgs, .tPins, .tPinHost, .tIsManaged)
			set tSecurity.identityReady = $$$ISOK(##class(OPCUA.Security.Identity).Active())
			set tSecurity.serverTrusted = tSecurity.identityReady && $$$ISOK(##class(OPCUA.Security.Trust).Pin(tURL))
		}

		// Measure connection time
		set tStart = $ZH

		// Connect
		if $$$ISOK(tRefusal) {
			set tSC = ##class(OPCUA.REST.ClientManager).Connect(.tClient, tURL, tSecMode, tUser, tPass, tCert, tKey, tTrust, tCrl, tClientURI)
		} else {
			set tSC = tRefusal
		}

		set tElapsed = $ZH - tStart
		set tElapsedMs = $FNumber(tElapsed * 1000, "", 0)

		set pResult = {}
		set pResult.url = tURL
		set pResult.responseTimeMs = +tElapsedMs

		if $$$ISERR(tSC) {
			set pResult.connected = 0
			set pResult.error = ##class(OPCUA.REST.Error).Text(tSC)
			if tManaged {
				if $$$ISERR(tRefusal) {
					set tSecurity.diagnosis = {"category": "other", "message": (pResult.error)}
				} else {
					set tSecurity.diagnosis = ##class(OPCUA.Security.Diagnose).Run(tURL, tSC)
				}
			}
			// Reset status — we report the error in the JSON body
			set tSC = $$$OK
		} else {
			set pResult.connected = 1
			set:tManaged pResult.securityMode = 3
		}
		set:tManaged pResult.security = tSecurity

	} Catch (e) {
		set tSC = e.AsStatus()
	}

	do ##class(OPCUA.REST.ClientManager).Disconnect($Get(tClient))
	Quit tSC
}

}
