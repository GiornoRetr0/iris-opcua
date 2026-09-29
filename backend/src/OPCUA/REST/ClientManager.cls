Include (OPCUA.Constants, %occInclude)

/// Manages per-request OPC UA client lifecycle for REST endpoints.
/// Creates a connected client, executes work, then disconnects.
Class OPCUA.REST.ClientManager
{

/// Create a connected OPC UA client from request parameters.
/// Returns the client instance by reference; caller must call Disconnect() when done.
ClassMethod Connect(Output pClient As OPCUA.Client, pURL As %String, pSecurityMode As %Integer = 1, pUsername As %String = "", pPassword As %String = "", pCertPath As %String = "", pKeyPath As %String = "", pTrustDir As %String = "", pCrlDir As %String = "", pClientURI As %String = "") As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		// Initialize library
		set tSC = ##class(OPCUA.Utils).Initialize()
		Quit:$$$ISERR(tSC)

		// Create and setup client
		set pClient = ##class(OPCUA.Client).%New()
		set tSC = pClient.Initialize()
		Quit:$$$ISERR(tSC)

		set tSC = pClient.SetupClient(, pSecurityMode, pClientURI, pCertPath, pKeyPath, pTrustDir, pCrlDir)
		Quit:$$$ISERR(tSC)

		set tSC = pClient.Connect(pURL, pUsername, pPassword)
		Quit:$$$ISERR(tSC)

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Safely disconnect a client, ignoring errors.
ClassMethod Disconnect(pClient As OPCUA.Client)
{
	Try {
		if $IsObject($Get(pClient)) do pClient.Disconnect()
	} Catch (e) {
		// Ignore disconnect errors
	}
}

/// Extract common connection parameters from a JSON request body.
/// Returns URL by reference. Other params are optional with defaults.
ClassMethod ExtractConnectionParams(pBody As %DynamicObject, Output pURL As %String, Output pSecurityMode As %Integer, Output pUsername As %String, Output pPassword As %String, Output pCertPath As %String, Output pKeyPath As %String, Output pTrustDir As %String, Output pCrlDir As %String, Output pClientURI As %String) As %Status
{
	set pURL = pBody.%Get("url")
	if pURL = "" {
		Quit $$$ERROR($$$GeneralError, "Missing required parameter: url")
	}
	set tSecVal = pBody.%Get("securityMode")
	set pSecurityMode = $Select(tSecVal="":1, +tSecVal=0:1, 1:+tSecVal)
	set tUser = pBody.%Get("username")
	set pUsername = $Select(tUser="":"", 1:tUser)
	set tPass = pBody.%Get("password")
	set pPassword = $Select(tPass="":"", 1:tPass)
	set tCert = pBody.%Get("certPath")
	set pCertPath = $Select(tCert="":"", 1:tCert)
	set tKey = pBody.%Get("keyPath")
	set pKeyPath = $Select(tKey="":"", 1:tKey)
	set tTrust = pBody.%Get("trustDir")
	set pTrustDir = $Select(tTrust="":"", 1:tTrust)
	set tCrl = pBody.%Get("crlDir")
	set pCrlDir = $Select(tCrl="":"", 1:tCrl)
	set tURI = pBody.%Get("clientURI")
	set pClientURI = $Select(tURI="":"", 1:tURI)
	Quit $$$OK
}

}
