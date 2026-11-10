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

		set tSC = ##class(OPCUA.Security.Connection).Setup(pClient, pURL, pSecurityMode, pClientURI, pCertPath, pKeyPath, pTrustDir, pCrlDir, .tManaged)
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
///
/// The session's username and password come from <tt>credentials</tt>, the ID of an
/// IRIS credentials entry, read here on the server (what the console sends for a
/// saved server; see <class>OPCUA.REST.CredentialsService</class>), or from
/// <tt>username</tt> and <tt>password</tt> sent inline, which are used for this
/// request only and never stored (the console's test of an unsaved entry). Neither
/// means anonymous. Both is a 400.
ClassMethod ExtractConnectionParams(pBody As %DynamicObject, Output pURL As %String, Output pSecurityMode As %Integer, Output pUsername As %String, Output pPassword As %String, Output pCertPath As %String, Output pKeyPath As %String, Output pTrustDir As %String, Output pCrlDir As %String, Output pClientURI As %String) As %Status
{
	set pURL = pBody.%Get("url")
	if pURL = "" {
		Quit $$$ERROR($$$GeneralError, "Missing required parameter: url")
	}
	set tSecVal = pBody.%Get("securityMode")
	set pSecurityMode = $Select(tSecVal="":1, +tSecVal=0:1, 1:+tSecVal)
	set tCredId = pBody.%Get("credentials")
	if tCredId '= "" {
		if pBody.%Get("username") '= "" {
			Quit ##class(OPCUA.REST.Error).BadRequest("Send either 'credentials' (an existing credentials ID) or 'username' and 'password', not both.")
		}
		set tSC = ##class(OPCUA.REST.DeployService).ReadCredentials(tCredId, .pUsername, .pPassword)
		Quit:$$$ISERR(tSC) tSC
	} else {
		set pUsername = pBody.%Get("username")
		set pPassword = pBody.%Get("password")
	}
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
