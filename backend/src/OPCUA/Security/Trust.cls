Include (%occInclude, OPCUA.Constants)

/// Which OPC UA servers IRIS trusts for managed Sign and Encrypt, and the exact
/// certificate it pinned for each.
///
/// Flow: <method>Inspect</method> fetches the server certificate by discovery (no trust
/// either way) and describes it; the user compares the fingerprint out of band;
/// <method>Trust</method> fetches it AGAIN and stores it only when its fingerprint equals
/// the reviewed one (bytes from the browser are never trusted). A CA-signed server also
/// needs its issuer certificate and CRL (<method>AddIssuer</method>), which are
/// user-supplied and verified to chain before they are stored. <method>Pin</method> gives
/// the connect path what the native layer needs and refuses anything not fully trusted.
///
/// Files per server (Store.ServerDir): trusted/server.der, trusted/issuer.der,
/// crl/issuer.crl. The trust directory is never left empty on a pinned connection: an
/// empty list would install open62541's allow-all verifier.
Class OPCUA.Security.Trust Extends %RegisteredObject
{

Parameter NotTrusted = "IRIS does not trust this OPC UA server yet. Review and trust its certificate in the server settings.";

Parameter ChangedMessage = "Server certificate changed—review and approve the replacement.";

Parameter NoKeyCertSign = "This server's self-signed certificate lacks the keyCertSign usage that IRIS's OPC UA library requires to trust it. Ask the server administrator to reissue it.";

/// Whether the certificate's SAN URI equals the server's application URI and its SAN
/// DNS/IP names cover <var>pHost</var> (no brackets). Pure. The problems are readable
/// sentences.
ClassMethod CheckEndpointIdentity(pCertInfo As %DynamicObject, pAppUri As %String, pHost As %String, Output pProblems As %DynamicArray) As %Boolean
{
    Set pProblems = []
    Set tUris = ..ListOf(pCertInfo.sanUris)
    If '$ListFind(tUris, pAppUri) || (pAppUri = "") {
        Set tShown = $Select(tUris = "": "(none)", 1: $ListToString(tUris, ", "))
        If pAppUri = "" {
            Do pProblems.%Push("The server did not report an application URI to check the certificate against.")
        } Else {
            Do pProblems.%Push("The certificate is for application "_tShown_", but the server says it is "_pAppUri_".")
        }
    }
    If '..HostMatches(pCertInfo, pHost) {
        Set tNames = ..ListOf(pCertInfo.sanDns) _ ..ListOf(pCertInfo.sanIps)
        Do pProblems.%Push("The certificate does not name "_pHost_"; it names "_$Select(tNames = "": "nothing", 1: $ListToString(tNames, ", "))_".")
    }
    Quit (pProblems.%Size() = 0)
}

/// SAN DNS (case-insensitive, one leading wildcard label) or SAN IP equals the host.
ClassMethod HostMatches(pCertInfo As %DynamicObject, pHost As %String) As %Boolean [ Internal ]
{
    Set tHost = $ZConvert(pHost, "L")
    If tHost = "" Quit 0
    Set tPtr = 0, tDns = ..ListOf(pCertInfo.sanDns)
    While $ListNext(tDns, tPtr, tName) {
        Set tName = $ZConvert(tName, "L")
        If tName = tHost Quit
        If ($Extract(tName, 1, 2) = "*.") && ($Find(tHost, ".")) && ($Extract(tHost, $Find(tHost, ".") - 1, *) = $Extract(tName, 2, *)) && (tHost '? 1.N1".".E) Quit
    }
    If tPtr '= 0 Quit 1
    Set tPtr = 0, tIps = ..ListOf(pCertInfo.sanIps)
    While $ListNext(tIps, tPtr, tIp) {
        If $ZConvert(tIp, "L") = tHost Quit
    }
    Quit (tPtr '= 0)
}

/// A JSON array of strings as a $List.
ClassMethod ListOf(pArr As %DynamicArray) As %List [ Internal ]
{
    Set l = ""
    If '$IsObject(pArr) Quit l
    For i = 0:1:pArr.%Size() - 1 { Set l = l _ $ListBuild(pArr.%Get(i)) }
    Quit l
}

/// The host as the native layer and the identity check want it: no IPv6 brackets.
ClassMethod PlainHost(pURL As %String) As %String [ Internal ]
{
    Set h = ##class(OPCUA.Security.Store).URLHost(pURL)
    If ($Extract(h) = "[") && ($Extract(h, *) = "]") Set h = $Extract(h, 2, *-1)
    Quit h
}

ClassMethod NormFp(pFp As %String) As %String [ Internal ]
{
    Quit $ZConvert($Translate(pFp, ": "), "U")
}

ClassMethod CertSummary(pInfo As %DynamicObject) As %DynamicObject [ Internal ]
{
    Quit {
        "subject": (pInfo.subject), "issuer": (pInfo.issuer),
        "notBefore": (pInfo.notBefore), "notAfter": (pInfo.notAfter),
        "sha256": (pInfo.sha256),
        "sanUris": (pInfo.sanUris), "sanDns": (pInfo.sanDns), "sanIps": (pInfo.sanIps),
        "selfSigned": (pInfo.selfSigned)
    }
}

/// Days from now (UTC) until a "YYYY-MM-DD HH:MM:SS" UTC time; negative when past.
ClassMethod DaysLeft(pNotAfter As %String) As %Integer [ Internal ]
{
    If pNotAfter = "" Quit 0
    Set tEnd = $ZDateTimeH(pNotAfter, 3, 1, , , , , , , "")
    If tEnd = "" Quit 0
    Set tNow = $ZTimeStamp
    Quit ($Piece(tEnd, ",", 1) - $Piece(tNow, ",", 1)) - ($Piece(tEnd, ",", 2) < $Piece(tNow, ",", 2))
}

/// True when <var>pTime</var> ("YYYY-MM-DD HH:MM:SS", UTC) is in the future (<var>pWantFuture</var> 1)
/// or the past (0).
ClassMethod IsAfterNow(pTime As %String) As %Boolean [ Internal ]
{
    Set t = $ZDateTimeH(pTime, 3, 1, , , , , , , "")
    If t = "" Quit 0
    Set n = $ZTimeStamp
    Quit ($Piece(t, ",", 1) > $Piece(n, ",", 1)) || (($Piece(t, ",", 1) = $Piece(n, ",", 1)) && ($Piece(t, ",", 2) > $Piece(n, ",", 2)))
}

/// Discovers the server at <var>pURL</var> and describes what it presents. See the class
/// description for the shape. Network or discovery failures come back as an error status.
ClassMethod Inspect(pURL As %String, Output pResult As %DynamicObject) As %Status
{
    Set pResult = ""
    Set tSC = $$$OK
    Try {
        Set tURL = ##class(OPCUA.Security.Store).NormaliseURL(pURL)
        If ($ZConvert($Piece(tURL, "://", 1), "L") '= "opc.tcp") || (##class(OPCUA.Security.Store).URLHost(tURL) = "") {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("Enter the server address as opc.tcp://host:port.") Quit
        }
        Set tSC = ##class(OPCUA.Security.Native).Gate()
        Quit:$$$ISERR(tSC)
        Set tSC = ##class(OPCUA.Utils).Initialize()
        Quit:$$$ISERR(tSC)
        Set tClient = ##class(OPCUA.Client).%New()
        Set tSC = tClient.Initialize()
        Quit:$$$ISERR(tSC)
        // Discovery uses an unsecured setup and leaves the throwaway client unusable.
        Set tSC = tClient.SetupClient(3000, 1)
        Quit:$$$ISERR(tSC)
        Set tSC = tClient.GetEndpoints(tURL, .tEndpoints, .tCertHex, .tAppUri)
        Quit:$$$ISERR(tSC)
        Kill tClient

        Set tOffers = 0, tPolicies = []
        Set tSeen = ""
        For i = 0:1:tEndpoints.%Size() - 1 {
            Set ep = tEndpoints.%Get(i)
            If ep.mode = 3 {
                Set tOffers = 1
                If '$Data(tSeen(ep.policyUri)) { Set tSeen(ep.policyUri) = 1  Do tPolicies.%Push(ep.policyUri) }
            }
        }
        If tCertHex = "" {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("The server did not present a certificate.") Quit
        }
        Set tSC = ##class(OPCUA.Security.Native).InspectCert(tCertHex, 0, .tInfo)
        Quit:$$$ISERR(tSC)

        Set tKey = ##class(OPCUA.Security.Store).ServerKey(tURL)
        Do ..CheckEndpointIdentity(tInfo, tAppUri, ..PlainHost(tURL), .tProblems)
        Set tUriOk = ('$ListFind(..ListOf(tInfo.sanUris), tAppUri) = 0) && (tAppUri '= "")
        Set tHostOk = ..HostMatches(tInfo, ..PlainHost(tURL))
        If tInfo.selfSigned {
            Set tUsage = ..ListOf(tInfo.keyUsage)
            If '$ListFind(tUsage, "keyCertSign") Do tProblems.%Push(..#NoKeyCertSign)
        }
        If '..IsAfterNow(tInfo.notAfter) {
            Do tProblems.%Push("The certificate expired on "_tInfo.notAfter_" UTC.")
        } ElseIf ..IsAfterNow(tInfo.notBefore) {
            Do tProblems.%Push("The certificate is not valid before "_tInfo.notBefore_" UTC.")
        }

        Set tNeedsIssuer = 'tInfo.selfSigned
        Set tHas = ##class(OPCUA.Security.Store).GetServer(tKey, .tEntry)
        Set tPinned = $Select(tHas: tEntry.fingerprint, 1: "")
        Set tChanged = (tHas && (..NormFp(tPinned) '= ..NormFp(tInfo.sha256)))
        Set pResult = {
            "url": (tURL), "key": (tKey),
            "offersSignAndEncrypt": (+tOffers),
            "policies": (tPolicies),
            "applicationUri": (tAppUri),
            "certificate": (..CertSummary(tInfo)),
            "identity": {"uriMatches": (+tUriOk), "hostMatches": (+tHostOk), "problems": (tProblems)},
            "trusted": (+(tHas && 'tChanged)),
            "pinnedFingerprint": (tPinned),
            "changed": (+tChanged),
            "needsIssuer": (+tNeedsIssuer),
            "hasIssuer": (+(tHas && 'tChanged && tEntry.hasIssuer)),
            "issuerName": ($Select(tNeedsIssuer: tInfo.issuer, 1: ""))
        }
        If tChanged {
            Set pResult.previous = {"subject": (tEntry.subject), "issuer": (tEntry.issuer), "notBefore": (tEntry.notBefore), "notAfter": (tEntry.notAfter), "sha256": (tEntry.fingerprint), "selfSigned": (+tEntry.selfSigned)}
        }
    } Catch e {
        Set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Pins the certificate the user reviewed. IRIS fetches the certificate again; if its
/// fingerprint differs from <var>pFingerprint</var> nothing is stored (409). Identity
/// problems refuse it (400). Replaces any earlier pin for the same server.
ClassMethod Trust(pURL As %String, pFingerprint As %String, pLabel As %String = "", Output pResult As %DynamicObject) As %Status
{
    Set pResult = ""
    Set tSC = $$$OK
    Try {
        Set tSC = ..Inspect(pURL, .tInspect)
        Quit:$$$ISERR(tSC)
        If (pFingerprint = "") || (..NormFp(pFingerprint) '= ..NormFp(tInspect.certificate.sha256)) {
            Set tSC = ##class(OPCUA.REST.Error).Conflict("The server presented a different certificate than the one you reviewed. Review it again.") Quit
        }
        If 'tInspect.offersSignAndEncrypt {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("This server does not offer a Sign & Encrypt endpoint.") Quit
        }
        If tInspect.identity.problems.%Size() {
            Set tText = ""
            For i = 0:1:tInspect.identity.problems.%Size() - 1 { Set tText = tText _ $Select(tText = "": "", 1: " ") _ tInspect.identity.problems.%Get(i) }
            Set tSC = ##class(OPCUA.REST.Error).BadRequest(tText) Quit
        }
        // Re-read the bytes we just verified (Inspect does not return them).
        Set tSC = ..FetchCertHex(tInspect.url, tInspect.certificate.sha256, .tHex)
        Quit:$$$ISERR(tSC)

        Set tKey = tInspect.key
        Set tTrusted = ##class(OPCUA.Security.Store).ServerDir(tKey, "trusted"), tCrl = ##class(OPCUA.Security.Store).ServerDir(tKey, "crl")
        If (tTrusted = "") || (tCrl = "") Set tSC = ##class(OPCUA.REST.Error).BadRequest("Invalid server address.") Quit
        Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(tTrusted)
        Quit:$$$ISERR(tSC)
        Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(tCrl)
        Quit:$$$ISERR(tSC)

        // The old pin (if any) goes first. A kept issuer must still vouch for the new certificate.
        Set tHadIssuer = 0
        If ##class(OPCUA.Security.Store).GetServer(tKey, .tOld) {
            Set tHadIssuer = +tOld.hasIssuer
            Do ##class(%File).Delete(tTrusted_"server.der")
        }
        Set tSC = ##class(OPCUA.Security.Native).Normalise("cert", tHex, "", tTrusted_"server.der")
        Quit:$$$ISERR(tSC)
        Set tHasIssuer = 0
        If tHadIssuer && 'tInspect.certificate.selfSigned {
            If ..ChainsTo(tTrusted_"server.der", tTrusted_"issuer.der", tCrl_"issuer.crl", .tWhy) Set tHasIssuer = 1
        }
        If 'tHasIssuer {
            Do ##class(%File).Delete(tTrusted_"issuer.der")
            Do ##class(%File).Delete(tCrl_"issuer.crl")
        }
        Set tEntry = {
            "url": (tInspect.url),
            "label": (pLabel),
            "fingerprint": (tInspect.certificate.sha256),
            "subject": (tInspect.certificate.subject),
            "issuer": (tInspect.certificate.issuer),
            "notBefore": (tInspect.certificate.notBefore),
            "notAfter": (tInspect.certificate.notAfter),
            "selfSigned": (+tInspect.certificate.selfSigned),
            "needsIssuer": (+tInspect.needsIssuer),
            "hasIssuer": (+tHasIssuer),
            "trustedAt": ($ZDateTime($ZTimeStamp, 3, 1, 0))
        }
        If (pLabel = "") && $IsObject(tOld) Set tEntry.label = tOld.label
        Set tSC = ##class(OPCUA.Security.Store).SaveServer(tKey, tEntry)
        If $$$ISERR(tSC) {
            Do ##class(%File).Delete(tTrusted_"server.der")
            Quit
        }
        Set tSC = ..Inspect(tInspect.url, .pResult)
    } Catch e {
        Set tSC = e.AsStatus()
    }
    Quit tSC
}

/// The server certificate as hex, fetched again and required to match <var>pFingerprint</var>.
ClassMethod FetchCertHex(pURL As %String, pFingerprint As %String, Output pHex As %String) As %Status [ Internal, Private ]
{
    Set pHex = ""
    Set tSC = $$$OK
    Try {
        Set tClient = ##class(OPCUA.Client).%New()
        Set tSC = tClient.Initialize()
        Quit:$$$ISERR(tSC)
        Set tSC = tClient.SetupClient(3000, 1)
        Quit:$$$ISERR(tSC)
        Set tSC = tClient.GetEndpoints(pURL, .tEndpoints, .tCertHex, .tAppUri)
        Quit:$$$ISERR(tSC)
        Set tSC = ##class(OPCUA.Security.Native).InspectCert(tCertHex, 0, .tInfo)
        Quit:$$$ISERR(tSC)
        If ..NormFp(tInfo.sha256) '= ..NormFp(pFingerprint) {
            Set tSC = ##class(OPCUA.REST.Error).Conflict("The server presented a different certificate than the one you reviewed. Review it again.") Quit
        }
        Set pHex = tCertHex
    } Catch e {
        Set tSC = e.AsStatus()
    }
    Quit tSC
}

/// DER bytes (file) as PEM text.
ClassMethod DerToPem(pDerPath As %String, pLabel As %String = "CERTIFICATE") As %String [ Internal ]
{
    Set s = ##class(%Stream.FileBinary).%New()
    Do s.LinkToFile(pDerPath)
    Set tRaw = ""
    While 's.AtEnd { Set tRaw = tRaw _ s.Read(3000) }
    Set tB64 = $System.Encryption.Base64Encode(tRaw)
    Set tB64 = $Translate(tB64, $Char(10, 13))
    Set tPem = "-----BEGIN "_pLabel_"-----"_$Char(10)
    For i = 1:64:$Length(tB64) { Set tPem = tPem _ $Extract(tB64, i, i + 63) _ $Char(10) }
    Quit tPem _ "-----END "_pLabel_"-----"_$Char(10)
}

ClassMethod WriteText(pPath As %String, pText As %String) As %Boolean [ Internal ]
{
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.TranslateTable = "RAW"
    Do f.LinkToFile(pPath)
    Do f.Write(pText)
    Quit $$$ISOK(f.%Save())
}

/// Whether the server certificate (DER file) chains to the CA (DER file), and when
/// <var>pCrlDer</var> is given, whether that CRL is one the CA signed (the check is run
/// with the CRL, so an unrelated CRL fails it). <var>pWhy</var> names the failure.
ClassMethod ChainsTo(pServerDer As %String, pCaDer As %String, pCrlDer As %String = "", Output pWhy As %String) As %Boolean [ Internal ]
{
    Set pWhy = ""
    Set tTmp = ##class(%File).NormalizeDirectory(##class(%File).GetDirectory(pServerDer)_"chk"_$Job)
    Do ##class(%File).CreateDirectoryChain(tTmp)
    Set tOk = 0
    Try {
        If '..WriteText(tTmp_"ca.pem", ..DerToPem(pCaDer)) Set pWhy = "internal: cannot write a temporary file" Quit
        Set tCert = ..DerToPem(pServerDer)
        Set tRes = $System.Encryption.X509VerifyCertChain(tCert, tTmp_"ca.pem")
        If tRes '= "OK" Set pWhy = "The server certificate was not issued by this CA ("_tRes_")." Quit
        If pCrlDer '= "" {
            If '..WriteText(tTmp_"crl.pem", ..DerToPem(pCrlDer, "X509 CRL")) Set pWhy = "internal: cannot write a temporary file" Quit
            Set tRes = $System.Encryption.X509VerifyCertChain(tCert, tTmp_"ca.pem", tTmp_"crl.pem")
            If tRes '= "OK" Set pWhy = "The revocation list was not signed by this CA, or lists this server certificate as revoked ("_tRes_")." Quit
        }
        Set tOk = 1
    } Catch e {
        Set pWhy = "Verification failed: "_e.DisplayString()
    }
    Do ##class(%File).RemoveDirectoryTree(tTmp)
    Quit tOk
}

/// Stores the CA certificate and CRL for a server whose certificate is pinned. Both
/// are normalised to DER; the pinned certificate must chain to the CA and the CRL must
/// be signed by it, or nothing is stored (400).
ClassMethod AddIssuer(pURL As %String, pCaHex As %String, pCrlHex As %String, Output pResult As %DynamicObject) As %Status
{
    Set pResult = ""
    Set tSC = $$$OK
    Try {
        Set tURL = ##class(OPCUA.Security.Store).NormaliseURL(pURL)
        Set tKey = ##class(OPCUA.Security.Store).ServerKey(tURL)
        If '##class(OPCUA.Security.Store).GetServer(tKey, .tEntry) {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("Trust the server's certificate first, then add its issuer.") Quit
        }
        If tEntry.selfSigned {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("This server's certificate is self-signed; it has no separate issuer.") Quit
        }
        If (pCaHex = "") || (pCrlHex = "") {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest("Both the CA certificate and its revocation list (CRL) are required.") Quit
        }
        Set tTrusted = ##class(OPCUA.Security.Store).ServerDir(tKey, "trusted"), tCrl = ##class(OPCUA.Security.Store).ServerDir(tKey, "crl")
        Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(tTrusted)
        Quit:$$$ISERR(tSC)
        Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(tCrl)
        Quit:$$$ISERR(tSC)
        If '##class(%File).Exists(tTrusted_"server.der") {
            Set tSC = ##class(OPCUA.REST.Error).BadRequest(..#NotTrusted) Quit
        }
        // Stage outside the trust and CRL directories; move in only after it all checks out.
        Set tStage = ##class(%File).NormalizeDirectory(##class(OPCUA.Security.Store).Dir("servers")_tKey_"/stage"_$Job)
        Do ##class(%File).CreateDirectoryChain(tStage)
        Try {
            Set tSC = ##class(OPCUA.Security.Native).Normalise("cert", pCaHex, "", tStage_"issuer.der")
            If $$$ISERR(tSC) Set tSC = ##class(OPCUA.REST.Error).BadRequest("The CA certificate could not be read: "_..Cut(tSC)) Quit
            Set tSC = ##class(OPCUA.Security.Native).Normalise("crl", pCrlHex, "", tStage_"issuer.crl")
            If $$$ISERR(tSC) Set tSC = ##class(OPCUA.REST.Error).BadRequest("The revocation list could not be read: "_..Cut(tSC)) Quit
            If '..ChainsTo(tTrusted_"server.der", tStage_"issuer.der", tStage_"issuer.crl", .tWhy) {
                Set tSC = ##class(OPCUA.REST.Error).BadRequest(tWhy) Quit
            }
            If '##class(%File).CopyFile(tStage_"issuer.der", tTrusted_"issuer.der", 1) || '##class(%File).CopyFile(tStage_"issuer.crl", tCrl_"issuer.crl", 1) {
                Do ##class(%File).Delete(tTrusted_"issuer.der")
                Do ##class(%File).Delete(tCrl_"issuer.crl")
                Set tSC = $$$ERROR($$$GeneralError, "Could not store the issuer files.") Quit
            }
            Set tEntry.hasIssuer = 1
            Set tSC = ##class(OPCUA.Security.Store).SaveServer(tKey, tEntry)
            If $$$ISERR(tSC) {
                Do ##class(%File).Delete(tTrusted_"issuer.der")
                Do ##class(%File).Delete(tCrl_"issuer.crl")
            }
        } Catch inner {
            Set tSC = inner.AsStatus()
        }
        Do ##class(%File).RemoveDirectoryTree(tStage)
        Quit:$$$ISERR(tSC)
        Set tSC = ..Inspect(tURL, .pResult)
    } Catch e {
        Set tSC = e.AsStatus()
    }
    Quit tSC
}

/// Shortens a native error text for inclusion in a message.
ClassMethod Cut(pSC As %Status) As %String [ Internal ]
{
    Set t = $System.Status.GetErrorText(pSC)
    Quit $Select($Length(t) > 160: $Extract(t, 1, 160)_"...", 1: t)
}

/// Stops trusting a server and deletes its files.
ClassMethod Remove(pKey As %String) As %Status
{
    If '##class(OPCUA.Security.Store).ValidServerKey(pKey) Quit ##class(OPCUA.REST.Error).BadRequest("Invalid server key.")
    If '##class(OPCUA.Security.Store).GetServer(pKey, .tEntry) Quit ##class(OPCUA.REST.Error).NotFound("No trusted server with this key.")
    Set tSC = ##class(OPCUA.Security.Store).RemoveServer(pKey)
    Quit:$$$ISERR(tSC) tSC
    Do ##class(%File).RemoveDirectoryTree(##class(%File).NormalizeDirectory(##class(OPCUA.Security.Store).Dir("servers")_pKey))
    Quit $$$OK
}

/// Every trusted server: key, url, label, fingerprint, subject, notAfter, daysLeft,
/// needsIssuer, hasIssuer.
ClassMethod List(Output pList As %DynamicArray) As %Status
{
    Set pList = []
    Set tAll = ##class(OPCUA.Security.Store).ListServers()
    For i = 0:1:tAll.%Size() - 1 {
        Set e = tAll.%Get(i)
        Do pList.%Push({
            "key": (##class(OPCUA.Security.Store).ServerKey(e.url)),
            "url": (e.url),
            "label": (e.label),
            "fingerprint": (e.fingerprint),
            "subject": (e.subject),
            "notAfter": (e.notAfter),
            "daysLeft": (..DaysLeft(e.notAfter)),
            "needsIssuer": (+e.needsIssuer),
            "hasIssuer": (+e.hasIssuer)
        })
    }
    Quit $$$OK
}

/// What the connect path needs for a managed connection to <var>pURL</var>: the pinned
/// fingerprint list, the trust and CRL directories, and the host (no brackets). Refuses
/// when the server is not fully trusted: no pin, issuer missing, or an empty trust
/// directory (open62541 would treat that as allow-all).
ClassMethod Pin(pURL As %String, Output pFps As %List, Output pTrustDir As %String, Output pCrlDir As %String, Output pHost As %String) As %Status
{
    Set pFps = "", pTrustDir = "", pCrlDir = "", pHost = ""
    Set tURL = ##class(OPCUA.Security.Store).NormaliseURL(pURL)
    Set tKey = ##class(OPCUA.Security.Store).ServerKey(tURL)
    Set tNo = $$$ERROR($$$GeneralError, ..#NotTrusted)
    If '##class(OPCUA.Security.Store).GetServer(tKey, .tEntry) || (tEntry.fingerprint = "") Quit tNo
    Set tTrusted = ##class(OPCUA.Security.Store).ServerDir(tKey, "trusted"), tCrl = ##class(OPCUA.Security.Store).ServerDir(tKey, "crl")
    If (tTrusted = "") || (tCrl = "") Quit tNo
    If tEntry.needsIssuer && ('tEntry.hasIssuer || '##class(%File).Exists(tTrusted_"issuer.der") || '##class(%File).Exists(tCrl_"issuer.crl")) {
        Quit $$$ERROR($$$GeneralError, "This server's certificate was issued by "_tEntry.issuer_". Add that CA certificate and its revocation list before connecting.")
    }
    If '##class(%File).Exists(tTrusted_"server.der") Quit tNo
    Set pFps = $ListBuild(tEntry.fingerprint)
    Set pTrustDir = tTrusted, pCrlDir = tCrl
    Set pHost = ..PlainHost(tURL)
    Quit $$$OK
}

}
