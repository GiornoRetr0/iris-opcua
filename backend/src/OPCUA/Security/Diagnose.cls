Include %occInclude

/// Explains why a managed Sign &amp; Encrypt connection failed. The native layer reports
/// a pin or host rejection only as BadConnectionClosed, so <method>Run</method> asks the
/// server again, over a throwaway unsecured discovery client, and compares what it
/// presents with what IRIS pinned.
Class OPCUA.Security.Diagnose
{

Parameter NotApproved = "The OPC UA server has not approved IRIS's certificate yet. Download the IRIS client certificate, ask the server administrator to trust it (often: move it from the server's ""rejected"" to its ""trusted"" certificates), then test again.";

ClassMethod Result(pCategory As %String, pMessage As %String) As %DynamicObject [ Private ]
{
    Quit {"category": (pCategory), "message": (pMessage)}
}

/// Pure. <var>pDiscovery</var>: <tt>{reachable, offersSignAndEncrypt, hostMatches, sha256}</tt>
/// from a fresh discovery. <var>pErrorText</var> carries the failure (status names such
/// as BadCertificateUriInvalid appear in it).
ClassMethod Classify(pErrorText As %String, pDiscovery As %DynamicObject, pPinnedFp As %String, pClientFp As %String) As %DynamicObject
{
    Set tErr = $Get(pErrorText)
    If '$IsObject(pDiscovery) || 'pDiscovery.reachable {
        Quit ..Result("network", "IRIS could not reach the OPC UA server. Check the URL, port and firewall.")
    }
    If 'pDiscovery.offersSignAndEncrypt {
        Quit ..Result("noSecureEndpoint", "The server does not offer Sign & Encrypt with a security policy IRIS supports.")
    }
    Set tPresented = ##class(OPCUA.Security.Trust).NormFp(pDiscovery.sha256)
    Set tPinned = ##class(OPCUA.Security.Trust).NormFp($Get(pPinnedFp))
    If (tPinned '= "") && (tPresented '= tPinned) {
        Quit ..Result("serverChanged", ##class(OPCUA.Security.Trust).#ChangedMessage)
    }
    If ($Find(tErr, "BadCertificateHostNameInvalid")) || (pDiscovery.hostMatches = 0) {
        Quit ..Result("hostMismatch", "The server's certificate does not name the host in this URL.")
    }
    If $Find(tErr, "BadCertificateUriInvalid") {
        Quit ..Result("uriInvalid", "The Client URI does not match IRIS's certificate.")
    }
    If $Find(tErr, "BadCertificateTimeInvalid") {
        Quit ..Result("timeInvalid", "A certificate is expired or not yet valid, or the clocks differ.")
    }
    If $Find(tErr, "BadSecurityChecksFailed") || $Find(tErr, "BadCertificateUntrusted") || $Find(tErr, "BadCertificateInvalid") || $Find(tErr, "BadSecureChannelClosed") || $Find(tErr, "BadConnectionClosed") {
        Set r = ..Result("clientNotApproved", ..#NotApproved)
        Set r.clientFingerprint = $Get(pClientFp)
        Quit r
    }
    Quit ..Result("other", tErr)
}

/// Discovers the server afresh (mode 1, used for GetEndpoints only, never for a session)
/// and classifies <var>pFailure</var>.
ClassMethod Run(pURL As %String, pFailure As %Status) As %DynamicObject
{
    Set tErr = $System.Status.GetErrorText(pFailure)
    Set tDisc = {"reachable": 0}
    Try {
        Set tURL = ##class(OPCUA.Security.Store).NormaliseURL(pURL)
        Set tSC = ##class(OPCUA.Utils).Initialize()
        Set tClient = ""
        If $$$ISOK(tSC) { Set tClient = ##class(OPCUA.Client).%New()  Set tSC = tClient.Initialize() }
        If $$$ISOK(tSC) Set tSC = tClient.SetupClient(3000, 1)
        If $$$ISOK(tSC) Set tSC = tClient.GetEndpoints(tURL, .tEndpoints, .tCertHex, .tAppUri)
        If $$$ISOK(tSC) {
            Set tDisc = {"reachable": 1, "offersSignAndEncrypt": 0, "hostMatches": 1, "sha256": ""}
            For i = 0:1:tEndpoints.%Size() - 1 {
                If tEndpoints.%Get(i).mode = 3 Set tDisc.offersSignAndEncrypt = 1
            }
            If tCertHex '= "" {
                If $$$ISOK(##class(OPCUA.Security.Native).InspectCert(tCertHex, 0, .tInfo)) {
                    Set tDisc.sha256 = tInfo.sha256
                    Set tDisc.hostMatches = +##class(OPCUA.Security.Trust).HostMatches(tInfo, ##class(OPCUA.Security.Trust).PlainHost(tURL))
                }
            }
        }
        Set tPinned = ""
        If ##class(OPCUA.Security.Store).GetServer(##class(OPCUA.Security.Store).ServerKey(tURL), .tEntry) Set tPinned = tEntry.fingerprint
        Set tClientFp = ""
        If ##class(OPCUA.Security.Store).GetIdentity(.tCfg) Set tClientFp = tCfg.fingerprint
        Quit
    } Catch e {
        Set tPinned = "", tClientFp = ""
    }
    Quit ..Classify(tErr, tDisc, $Get(tPinned), $Get(tClientFp))
}

}
