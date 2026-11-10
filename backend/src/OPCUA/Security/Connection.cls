Include %occInclude

/// Decides how a connection is secured and sets the client up for it.
///
/// Manual (mode 3 with a certificate and key path, or mode 1): the caller's arguments
/// reach SetupClient exactly as before. Managed (mode 3 with neither path): the IRIS
/// client identity and the server's pinned trust are used, and anything missing refuses
/// the connection before the native layer is called. Nothing here ever falls back to
/// mode 1.
Class OPCUA.Security.Connection
{

/// Managed Sign &amp; Encrypt: mode 3 and no certificate or key path of the caller's own.
ClassMethod IsManaged(pMode As %Integer, pCertPath As %String, pKeyPath As %String) As %Boolean
{
    Quit ((+pMode = 3) && ($Get(pCertPath) = "") && ($Get(pKeyPath) = ""))
}

/// Works out the SetupClient arguments. <var>pSetupArgs</var> is
/// <tt>$LB(mode, clientURI, certPath, keyPath, trustDir, crlDir)</tt>; for a managed
/// connection <var>pPins</var> and <var>pHost</var> are what SetServerPin needs. An
/// error means: do not call the native layer at all.
ClassMethod Resolve(pURL As %String, pMode As %Integer, pClientURI As %String, pCertPath As %String, pKeyPath As %String, pTrustDir As %String, pCrlDir As %String, Output pSetupArgs As %List, Output pPins As %List, Output pHost As %String, Output pManaged As %Boolean) As %Status
{
    Set (pSetupArgs, pPins, pHost) = ""
    Set pManaged = ..IsManaged(pMode, pCertPath, pKeyPath)
    If 'pManaged {
        Set pSetupArgs = $ListBuild(pMode, pClientURI, pCertPath, pKeyPath, pTrustDir, pCrlDir)
        Quit $$$OK
    }
    // The host first: an empty one (e.g. "[]") would make the native layer skip the
    // host check, and it only rejects a literally empty string.
    Set tHost = ##class(OPCUA.Security.Trust).PlainHost(pURL)
    If tHost = "" Quit $$$ERROR($$$GeneralError, "The server address has no host name. Enter it as opc.tcp://host:port.")
    Set tSC = ##class(OPCUA.Security.Identity).Active(.tCert, .tKey, .tURI)
    Quit:$$$ISERR(tSC) tSC
    Set tSC = ##class(OPCUA.Security.Trust).Pin(pURL, .tFps, .tTrust, .tCrl, .tPinHost)
    Quit:$$$ISERR(tSC) tSC
    If (tFps = "") || (tTrust = "") || (tCrl = "") || (tPinHost = "") {
        Quit $$$ERROR($$$GeneralError, ##class(OPCUA.Security.Trust).#NotTrusted)
    }
    Set pSetupArgs = $ListBuild(3, tURI, tCert, tKey, tTrust, tCrl)
    Set pPins = tFps, pHost = tPinHost
    Quit $$$OK
}

/// Sets <var>pClient</var> up for <var>pURL</var>. Call before Connect. Manual and mode 1
/// make the same SetupClient call as before; managed adds the server pin afterwards.
ClassMethod Setup(pClient As OPCUA.Client, pURL As %String, pMode As %Integer, pClientURI As %String, pCertPath As %String, pKeyPath As %String, pTrustDir As %String, pCrlDir As %String, Output pManaged As %Boolean, pTimeout As %String = 3000) As %Status
{
    Set tSC = ..Resolve(pURL, pMode, pClientURI, pCertPath, pKeyPath, pTrustDir, pCrlDir, .tArgs, .tPins, .tHost, .pManaged)
    Quit:$$$ISERR(tSC) tSC
    Set tSC = pClient.SetupClient(pTimeout, $List(tArgs, 1), $List(tArgs, 2), $List(tArgs, 3), $List(tArgs, 4), $List(tArgs, 5), $List(tArgs, 6))
    Quit:$$$ISERR(tSC) tSC
    If pManaged Set tSC = pClient.SetServerPin(tPins, tHost)
    Quit tSC
}

}
