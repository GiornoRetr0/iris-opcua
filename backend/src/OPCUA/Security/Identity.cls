Include %occInclude

/// The IRIS client identity (the OPC UA application instance certificate) for managed
/// Sign &amp; Encrypt: one per IRIS instance, shared by every namespace.
///
/// It is generated here, imported (PEM, DER, PKCS#12) or referenced in place on IRIS.
/// New material is built and checked in a staging directory first and only then moved
/// into <tt>own/</tt>; the identity it replaces goes to <tt>previous/&lt;timestamp&gt;/</tt>.
/// Nothing partial is left behind on failure. No method here returns key bytes, and a
/// passphrase or PKCS#12 password lives only for the call.
///
/// Configuration is <class>OPCUA.Security.Store</class>'s <tt>identity</tt> entry:
/// <tt>{source, certPath, keyPath, clientURI, fingerprint, created, replaced}</tt>.
/// Status always re-reads the files, so a file deleted or swapped after "use existing
/// files" turns the identity not ready at once.
Class OPCUA.Security.Identity Extends %RegisteredObject
{

/// Certificates expiring within this many days get a warning.
Parameter ExpiryWarnDays = 30;

Parameter DemoCert = "/usr/irissys/uac/certs/secuac.crt.der";

Parameter DemoKey = "/usr/irissys/uac/certs/secuac.key.der";

Parameter OwnCert = "client.crt.der";

Parameter OwnKey = "client.key.der";

/// "YYYY-MM-DD HH:MM:SS" in UTC, as the native layer writes certificate dates.
ClassMethod NowUTC() As %String
{
	Quit $ZDateTime($ZTimeStamp, 3, 1, 0)
}

/// Seconds since the IRIS epoch of a "YYYY-MM-DD HH:MM:SS" string, "" if it is none.
ClassMethod Secs(pTS As %String) As %Integer [ Private ]
{
	Quit:pTS="" ""
	Set h = $ZDateTimeH(pTS, 3, 1, , , , , , , "")
	Quit:h="" ""
	Quit ($Piece(h, ",", 1) * 86400) + $Piece(h, ",", 2)
}

ClassMethod Entry(pCode As %String, pMessage As %String) As %DynamicObject [ Private ]
{
	Quit {"code": (pCode), "message": (pMessage)}
}

/// Pure validation of an <method>OPCUA.Security.Native.InspectCert</method> result.
/// <var>pKeyMatch</var> is 1 (the key belongs to it), 0 (it does not) or "" (not checked).
/// <var>pNowUTC</var> is "YYYY-MM-DD HH:MM:SS" UTC. Blocking problems go to
/// <var>pErrors</var>, usable-but-worth-knowing ones to <var>pWarnings</var>; each entry
/// is <tt>{code, message}</tt>.
ClassMethod Evaluate(pInfo As %DynamicObject, pKeyMatch As %Boolean, pNowUTC As %String, Output pErrors As %DynamicArray, Output pWarnings As %DynamicArray) As %Status
{
	Set pErrors = [], pWarnings = []
	If '$IsObject(pInfo) {
		Do pErrors.%Push(..Entry("unparseable", "The certificate could not be parsed."))
		Quit $$$OK
	}
	Set now = ..Secs(pNowUTC)
	Set from = ..Secs(pInfo.notBefore), to = ..Secs(pInfo.notAfter)
	Set expired = 0
	If (pKeyMatch '= "") && ('pKeyMatch) {
		Do pErrors.%Push(..Entry("keyMismatch", "The private key does not belong to this certificate."))
	}
	If (from '= "") && (now '= "") && (from > now) {
		Do pErrors.%Push(..Entry("notYetValid", "The certificate is not valid yet (valid from "_pInfo.notBefore_" UTC)."))
	}
	If (to '= "") && (now '= "") && (to < now) {
		Set expired = 1
		Do pErrors.%Push(..Entry("expired", "The certificate expired on "_pInfo.notAfter_" UTC."))
	}
	If (pInfo.sanUris = "") || (pInfo.sanUris.%Size() = 0) {
		Do pErrors.%Push(..Entry("noUri", "The certificate has no URI in its Subject Alternative Name; OPC UA requires one."))
	}
	If pInfo.keyType '= "RSA" {
		Do pErrors.%Push(..Entry("notRsa", "The certificate key is not RSA; only RSA keys are supported."))
	}
	If 'expired && (to '= "") && (now '= "") && ((to - now) <= (..#ExpiryWarnDays * 86400)) {
		Do pWarnings.%Push(..Entry("expiresSoon", "The certificate expires on "_pInfo.notAfter_" UTC, in "_((to - now) \ 86400)_" days."))
	}
	If (+pInfo.keyBits > 0) && (pInfo.keyBits < 2048) {
		Do pWarnings.%Push(..Entry("weakKey", "The key has only "_pInfo.keyBits_" bits; 2048 or more is recommended."))
	}
	Set usage = pInfo.keyUsage
	If $IsObject(usage) && (usage.%Size() > 0) {
		Set have = ",", it = usage.%GetIterator()
		While it.%GetNext(.k, .v) { Set have = have_v_"," }
		If (have '[ ",digitalSignature,") || (have '[ ",keyEncipherment,") {
			Do pWarnings.%Push(..Entry("keyUsage", "The certificate's key usage lacks digitalSignature or keyEncipherment; some servers will refuse it."))
		}
	}
	Quit $$$OK
}

/// Reads the configured identity from disk and evaluates it. Returns whether one is
/// configured. <var>pInfo</var> is "" when the certificate could not be read.
ClassMethod Examine(Output pCfg As %DynamicObject, Output pInfo As %DynamicObject, Output pErrors As %DynamicArray, Output pWarnings As %DynamicArray) As %Boolean [ Private ]
{
	Set pInfo = "", pErrors = [], pWarnings = []
	If '##class(OPCUA.Security.Store).GetIdentity(.pCfg) Quit 0
	Do ..ExaminePair(pCfg.certPath, pCfg.keyPath, .pInfo, .pErrors, .pWarnings)
	Quit 1
}

/// Examines a certificate and key on disk: readable, parseable, matching, and the rules
/// of <method>Evaluate</method>.
ClassMethod ExaminePair(pCertPath As %String, pKeyPath As %String, Output pInfo As %DynamicObject, Output pErrors As %DynamicArray, Output pWarnings As %DynamicArray) [ Private ]
{
	Set pInfo = "", pErrors = [], pWarnings = []
	If (pCertPath = "") || '##class(%File).Exists(pCertPath) {
		Do pErrors.%Push(..Entry("unreadable", "The certificate file "_pCertPath_" cannot be read."))
	}
	If (pKeyPath = "") || '##class(%File).Exists(pKeyPath) {
		Do pErrors.%Push(..Entry("unreadable", "The private key file "_pKeyPath_" cannot be read."))
	}
	If pErrors.%Size() Quit
	Set tSC = ##class(OPCUA.Security.Native).InspectCert(pCertPath, 1, .pInfo)
	If $$$ISERR(tSC) || '$IsObject(pInfo) {
		Set pInfo = ""
		Do pErrors.%Push(..Entry("unparseable", "The certificate could not be parsed."))
		Quit
	}
	Set tMatch = ""
	Set tSC = ##class(OPCUA.Security.Native).CheckKeyPair(pCertPath, pKeyPath, .tMatch)
	If $$$ISERR(tSC) {
		Set tMatch = ""
		Do pErrors.%Push(..Entry("unparseable", "The private key could not be read."))
	}
	Do ..Evaluate(pInfo, tMatch, ..NowUTC(), .tE, .tW)
	Set it = tE.%GetIterator()
	While it.%GetNext(.k, .v) { Do pErrors.%Push(v) }
	Set pWarnings = tW
}

ClassMethod FirstUri(pInfo As %DynamicObject, pDefault As %String = "") As %String [ Private ]
{
	If $IsObject(pInfo) && $IsObject(pInfo.sanUris) && (pInfo.sanUris.%Size() > 0) Quit pInfo.sanUris.%Get(0)
	Quit pDefault
}

ClassMethod DaysLeft(pInfo As %DynamicObject) As %Integer [ Private ]
{
	If '$IsObject(pInfo) Quit ""
	Set to = ..Secs(pInfo.notAfter), now = ..Secs(..NowUTC())
	Quit:(to="")||(now="") ""
	Quit (to - now) \ 86400
}

/// The identity's state for the console. Never contains key material.
ClassMethod Status(Output pStatus As %DynamicObject) As %Status
{
	Set pStatus = "", tSC = $$$OK
	Try {
		Set tConfigured = ..Examine(.tCfg, .tInfo, .tErrors, .tWarnings)
		Set pStatus = {
			"configured": (tConfigured),
			"ready": 0,
			"source": "",
			"clientURI": "",
			"fingerprint": "",
			"subject": "",
			"notBefore": "",
			"notAfter": "",
			"daysLeft": null,
			"errors": (tErrors),
			"warnings": (tWarnings),
			"candidates": [],
			"advanced": {"certPath": "", "keyPath": "", "storeRoot": (##class(OPCUA.Security.Store).Root())}
		}
		If tConfigured {
			Set pStatus.ready = (tErrors.%Size() = 0)
			Set pStatus.source = tCfg.source
			Set pStatus.clientURI = ..FirstUri(tInfo, tCfg.clientURI)
			Set pStatus.fingerprint = $Select($IsObject(tInfo): tInfo.sha256, 1: tCfg.fingerprint)
			If $IsObject(tInfo) {
				Set pStatus.subject = tInfo.subject, pStatus.notBefore = tInfo.notBefore, pStatus.notAfter = tInfo.notAfter
				Set tDays = ..DaysLeft(tInfo)
				If tDays '= "" Set pStatus.daysLeft = tDays
				Set pStatus.sanUris = tInfo.sanUris
			}
			Set pStatus.advanced.certPath = tCfg.certPath, pStatus.advanced.keyPath = tCfg.keyPath
		} Else {
			Do ..AddCandidates(pStatus.candidates)
		}
		Do ..Impact(.tImpact)
		Set pStatus.impact = tImpact
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

/// The demo/legacy identity, offered only if both files exist. Never adopted by itself.
ClassMethod AddCandidates(pList As %DynamicArray) [ Private ]
{
	Set tCert = ..#DemoCert, tKey = ..#DemoKey
	If '##class(%File).Exists(tCert) || '##class(%File).Exists(tKey) Quit
	Do ..ExaminePair(tCert, tKey, .tInfo, .tErrors, .tWarnings)
	Do pList.%Push({
		"certPath": (tCert),
		"keyPath": (tKey),
		"clientURI": (..FirstUri(tInfo)),
		"fingerprint": ($Select($IsObject(tInfo): tInfo.sha256, 1: "")),
		"notAfter": ($Select($IsObject(tInfo): tInfo.notAfter, 1: "")),
		"ready": (tErrors.%Size() = 0)
	})
}

/// The fingerprint of the identity as it is now (re-read from the file; the stored
/// one when the file cannot be read), "" when none is configured.
ClassMethod CurrentFingerprint() As %String [ Private ]
{
	If '##class(OPCUA.Security.Store).GetIdentity(.tCfg) Quit ""
	If (tCfg.certPath '= "") && ##class(%File).Exists(tCfg.certPath) {
		Set tSC = ##class(OPCUA.Security.Native).InspectCert(tCfg.certPath, 1, .tInfo)
		If $$$ISOK(tSC) && $IsObject(tInfo) && (tInfo.sha256 '= "") Quit tInfo.sha256
	}
	Quit tCfg.fingerprint
}

/// Refuses to touch a configured identity unless the caller confirmed the replacement
/// against the identity it actually reviewed.
ClassMethod GuardReplace(pReplace As %Boolean, pCurrentFp As %String) As %Status
{
	If '##class(OPCUA.Security.Store).GetIdentity(.tCfg) Quit $$$OK
	If 'pReplace {
		Quit ##class(OPCUA.REST.Error).Conflict("An IRIS client identity is already configured. Replacing it means every OPC UA server must approve the new certificate.")
	}
	If pCurrentFp '= ..CurrentFingerprint() {
		Quit ##class(OPCUA.REST.Error).Conflict("The client identity changed since you reviewed it. Reload and review the replacement again.")
	}
	Quit $$$OK
}

/// The paths and Client URI managed connections use. An error unless the identity is
/// configured and passes every blocking rule.
ClassMethod Active(Output pCert As %String, Output pKey As %String, Output pURI As %String) As %Status
{
	Set (pCert, pKey, pURI) = ""
	If '..Examine(.tCfg, .tInfo, .tErrors, .tWarnings) {
		Quit $$$ERROR($$$GeneralError, "No IRIS client identity is set up. Open Settings "_$Char(8250)_" OPC UA Security to create one.")
	}
	If tErrors.%Size() {
		Quit $$$ERROR($$$GeneralError, "The IRIS client identity is not usable: "_tErrors.%Get(0).message)
	}
	Set pCert = tCfg.certPath, pKey = tCfg.keyPath, pURI = ..FirstUri(tInfo, tCfg.clientURI)
	Quit $$$OK
}

/// What replacing the identity affects: every managed Sign &amp; Encrypt pipeline (mode 3,
/// no certificate paths of its own) in any namespace that has the adapter, and every
/// trusted server.
ClassMethod Impact(Output pImpact As %DynamicObject) As %Status
{
	Set pImpact = {"pipelines": [], "servers": []}
	Set tNames = ""
	Try {
		Set rs = ##class(%ResultSet).%New("%SYS.Namespace:List")
		Set tSC = rs.Execute()
		If $$$ISERR(tSC) Quit
		While rs.Next() {
			Set tNs = rs.Get("Nsp")
			If $Extract(tNs) '= "%" Set tNames = tNames_$ListBuild(tNs)
		}
	} Catch e {
		Set tNames = $ListBuild($Namespace)
	}
	Set tPtr = 0
	While $ListNext(tNames, tPtr, tNs) {
		Do ..CollectPipelines(tNs, pImpact.pipelines)
	}
	Set tServers = ##class(OPCUA.Security.Store).ListServers()
	Set it = tServers.%GetIterator()
	While it.%GetNext(.k, .v) {
		Do pImpact.servers.%Push({"key": (v.key), "url": (v.url), "label": (v.label)})
	}
	Quit $$$OK
}

/// Managed-identity pipelines of one namespace. <tt>New $Namespace</tt> restores the
/// caller's namespace however this method exits.
ClassMethod CollectPipelines(pNs As %String, pList As %DynamicArray) [ Private ]
{
	New $Namespace
	Try {
		Set $Namespace = pNs
		If '##class(%Dictionary.CompiledClass).%ExistsId("OPCUA.Adapter.Common") Quit
		If '##class(%Dictionary.CompiledClass).%ExistsId("Ens.Config.Item") Quit
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens_Config.Item")
		While rs.%Next() {
			Set tItem = ##class(Ens.Config.Item).%OpenId(rs.%GetData(1))
			If '$IsObject(tItem) Continue
			Kill tVal
			For i = 1:1:tItem.Settings.Count() {
				Set tS = tItem.Settings.GetAt(i)
				If (tS.Target = "Adapter") && '$Data(tVal(tS.Name)) Set tVal(tS.Name) = tS.Value
			}
			If $Get(tVal("SecurityMode")) '= 3 Continue
			If ($Get(tVal("PublicCertificate")) '= "") || ($Get(tVal("PrivateKey")) '= "") Continue
			Do pList.%Push({"namespace": (pNs), "name": (tItem.Name), "url": ($Get(tVal("URL")))})
		}
	} Catch e {
		// a namespace without Interoperability or that cannot be entered has no pipelines to list
	}
}

/// The certificate for download, as DER or PEM. Public data only.
ClassMethod CertificateBytes(pFormat As %String, Output pData As %String, Output pFilename As %String) As %Status
{
	Set pData = "", pFilename = ""
	If (pFormat '= "der") && (pFormat '= "pem") Quit ##class(OPCUA.REST.Error).BadRequest("The format must be der or pem.")
	If '##class(OPCUA.Security.Store).GetIdentity(.tCfg) {
		Quit ##class(OPCUA.REST.Error).NotFound("No IRIS client identity is set up.")
	}
	Set tSC = ##class(OPCUA.Security.Native).InspectCert(tCfg.certPath, 1, .tInfo)
	If $$$ISERR(tSC) || '$IsObject(tInfo) Quit ##class(OPCUA.REST.Error).BadRequest("The certificate could not be read.")
	Set tDer = ""
	Set tHex = tInfo.derHex
	For i = 1:2:$Length(tHex) { Set tDer = tDer_$Char($ZHex($Extract(tHex, i, i + 1))) }
	If pFormat = "der" {
		Set pData = tDer, pFilename = "iris-opcua-client.der"
		Quit $$$OK
	}
	Set tB64 = $System.Encryption.Base64Encode(tDer, 1)
	Set tPem = "-----BEGIN CERTIFICATE-----"_$Char(10)
	For i = 1:64:$Length(tB64) { Set tPem = tPem_$Extract(tB64, i, i + 63)_$Char(10) }
	Set pData = tPem_"-----END CERTIFICATE-----"_$Char(10)
	Set pFilename = "iris-opcua-client.pem"
	Quit $$$OK
}

/// Generates a self-signed identity. <var>pClientURI</var> "" means the default for a
/// first identity and the current one's URI on a replacement.
ClassMethod Create(pClientURI As %String = "", pReplace As %Boolean = 0, pCurrentFp As %String = "", Output pStatus As %DynamicObject) As %Status
{
	Set pStatus = ""
	Set tSC = ..GuardReplace(pReplace, pCurrentFp)
	Quit:$$$ISERR(tSC) tSC
	Set tURI = pClientURI
	If tURI = "" {
		Set tURI = $Select(##class(OPCUA.Security.Store).GetIdentity(.tOld): tOld.clientURI, 1: "")
		If tURI = "" Set tURI = ##class(OPCUA.Security.Store).DefaultClientURI()
	}
	If '##class(OPCUA.Security.Store).ValidClientURI(tURI) {
		Quit ##class(OPCUA.REST.Error).BadRequest("The Client URI may only contain lowercase letters, digits and : . _ - and must contain a colon.")
	}
	Set tHost = $System.INetInfo.LocalHostName()
	Set tCN = "IRIS OPC UA Client ("_tHost_"/"_$Piece($System, ":", 2)_")"
	Set tStage = ..NewStage(.tSC)
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set tCert = tStage_..#OwnCert, tKey = tStage_..#OwnKey
		Set tSC = ##class(OPCUA.Security.Native).CreateIdentity(tCert, tKey, tURI, tHost, tCN)
		If $$$ISERR(tSC) Set tSC = ..NativeError(tSC) Quit
		Set tSC = ..Adopt("generated", tStage, tCert, tKey, pReplace, .pStatus)
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Do ##class(%File).RemoveDirectoryTree(tStage)
	Quit tSC
}

/// Imports uploaded material (hex): a certificate plus key (PEM or DER, the key
/// possibly passphrase protected), or one PKCS#12 bundle. Exactly one of the two forms.
ClassMethod Import(pCertHex As %String = "", pKeyHex As %String = "", pP12Hex As %String = "", pPassword As %String = "", pReplace As %Boolean = 0, pCurrentFp As %String = "", Output pStatus As %DynamicObject) As %Status
{
	Set pStatus = ""
	Set tPair = (pCertHex '= "") || (pKeyHex '= "")
	If (tPair && (pP12Hex '= "")) || ('tPair && (pP12Hex = "")) || (tPair && ((pCertHex = "") || (pKeyHex = ""))) {
		Quit ##class(OPCUA.REST.Error).BadRequest("Give either a certificate together with its private key, or one PKCS#12 file.")
	}
	Set tSC = ..GuardReplace(pReplace, pCurrentFp)
	Quit:$$$ISERR(tSC) tSC
	Set tStage = ..NewStage(.tSC)
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set tCert = tStage_..#OwnCert, tKey = tStage_..#OwnKey
		If tPair {
			Set tSC = ##class(OPCUA.Security.Native).Normalise("cert", pCertHex, "", tCert)
			If $$$ISOK(tSC) Set tSC = ##class(OPCUA.Security.Native).Normalise("key", pKeyHex, pPassword, tKey)
		} Else {
			Set tSC = ##class(OPCUA.Security.Native).Normalise("p12", pP12Hex, pPassword, tCert, tKey)
		}
		If $$$ISERR(tSC) Set tSC = ..NativeError(tSC) Quit
		Set tSC = ..Adopt("imported", tStage, tCert, tKey, pReplace, .pStatus)
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Do ##class(%File).RemoveDirectoryTree(tStage)
	Quit tSC
}

/// References a certificate and key already on IRIS, in place (nothing is copied).
ClassMethod UseFiles(pCertPath As %String, pKeyPath As %String, pReplace As %Boolean = 0, pCurrentFp As %String = "", Output pStatus As %DynamicObject) As %Status
{
	Set pStatus = ""
	If (pCertPath = "") || (pKeyPath = "") Quit ##class(OPCUA.REST.Error).BadRequest("Give the path of the certificate and of its private key.")
	Set tSC = ..GuardReplace(pReplace, pCurrentFp)
	Quit:$$$ISERR(tSC) tSC
	Quit ..Adopt("files", "", pCertPath, pKeyPath, pReplace, .pStatus)
}

/// Creates the staging directory under the store root (0700 like the rest).
ClassMethod NewStage(Output pSC As %Status) As %String [ Private ]
{
	Set tDir = ##class(%File).NormalizeDirectory(##class(OPCUA.Security.Store).Root()_"staging/"_$ZStrip($ZDateTime($ZTimeStamp, 8, 1, 3), "*P")_"-"_$Job)
	Set pSC = ##class(OPCUA.Security.Store).EnsureDirs(tDir)
	Quit tDir
}

/// Native errors arrive as "Application Error [9] : Other error : <text>". A wrong or
/// missing password gets one fixed message; anything else its own text, prefix removed.
ClassMethod NativeError(pSC As %Status) As %Status [ Private ]
{
	Set tText = $System.Status.GetErrorText(pSC)
	If $ZConvert(tText, "L") [ "password" Quit ##class(OPCUA.REST.Error).BadRequest("The password for the key or PKCS#12 file is wrong or missing.")
	If tText [ "Other error : " {
		Set tText = $Piece(tText, "Other error : ", 2, *)
	} ElseIf $Extract(tText, 1, 13) = "ERROR #5001: " {
		Set tText = $Extract(tText, 14, *)
	}
	Quit ##class(OPCUA.REST.Error).BadRequest(tText)
}

/// Validates the new pair; on success moves the old <tt>own/</tt> aside, moves the new
/// pair in (unless it is referenced in place) and stores the configuration.
ClassMethod Adopt(pSource As %String, pStage As %String, pCert As %String, pKey As %String, pReplace As %Boolean, Output pStatus As %DynamicObject) As %Status [ Private ]
{
	Do ..ExaminePair(pCert, pKey, .tInfo, .tErrors, .tWarnings)
	If tErrors.%Size() {
		Set tMsg = "", it = tErrors.%GetIterator()
		While it.%GetNext(.k, .v) { Set tMsg = tMsg_$Select(tMsg="": "", 1: " ")_v.message }
		Quit ##class(OPCUA.REST.Error).BadRequest(tMsg)
	}
	Set tHadOld = ##class(OPCUA.Security.Store).GetIdentity(.tOldCfg)
	Set tOwn = ##class(OPCUA.Security.Store).Dir("own")
	If tOwn = "" Quit $$$ERROR($$$GeneralError, "The identity store is not available.")
	Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(tOwn)
	Quit:$$$ISERR(tSC) tSC
	// 1. move what is in own/ aside
	Set tPrev = "", tMoved = ""
	Set tSC = ..MoveOwnAside(tOwn, .tPrev, .tMoved)
	If $$$ISERR(tSC) {
		Do ..RestoreOwn(tMoved)
		Quit tSC
	}
	// 2. move the new pair in
	Set tCertPath = pCert, tKeyPath = pKey
	If pSource '= "files" {
		Set tCertPath = tOwn_..#OwnCert, tKeyPath = tOwn_..#OwnKey
		If '##class(%File).Rename(pCert, tCertPath) || '##class(%File).Rename(pKey, tKeyPath) {
			Do ##class(%File).Delete(tCertPath), ##class(%File).Delete(tKeyPath)
			Do ..RestoreOwn(tMoved)
			Quit $$$ERROR($$$GeneralError, "The new identity could not be moved into place; nothing was changed.")
		}
		If '$$$isWINDOWS Do ##class(%File).SetAttributes($Extract(tKeyPath, 1, *), 384)
	}
	// 3. record it
	Set tNow = ..NowUTC()
	Set tCfg = {"source": (pSource), "certPath": (tCertPath), "keyPath": (tKeyPath), "clientURI": (..FirstUri(tInfo)), "fingerprint": (tInfo.sha256), "created": (tNow)}
	If tHadOld && pReplace Set tCfg.replaced = tNow
	Do ##class(OPCUA.Security.Store).SaveIdentity(tCfg)
	Quit ..Status(.pStatus)
}

/// Moves every file in <tt>own/</tt> into <tt>previous/&lt;timestamp&gt;/</tt>.
/// <var>pMoved</var> is a $LB of $LB(from, to) pairs, for undoing.
ClassMethod MoveOwnAside(pOwn As %String, Output pPrev As %String, Output pMoved As %List) As %Status [ Private ]
{
	Set pPrev = "", pMoved = ""
	Set rs = ##class(%ResultSet).%New("%File:FileSet")
	Do rs.Execute(pOwn, "*")
	Set tFiles = ""
	While rs.Next() { If rs.Get("Type") = "F" Set tFiles = tFiles_$ListBuild(rs.Get("Name")) }
	If tFiles = "" Quit $$$OK
	Set tBase = ##class(OPCUA.Security.Store).Dir("previous")
	Set tStamp = $ZStrip($ZDateTime($ZTimeStamp, 8, 1, 0), "*P")
	Set pPrev = ##class(%File).NormalizeDirectory(tBase_tStamp)
	Set n = 1
	While ##class(%File).DirectoryExists(pPrev) { Set n = n + 1, pPrev = ##class(%File).NormalizeDirectory(tBase_tStamp_"-"_n) }
	Set tSC = ##class(OPCUA.Security.Store).EnsureDirs(pPrev)
	Quit:$$$ISERR(tSC) tSC
	Set tPtr = 0
	While $ListNext(tFiles, tPtr, tFile) {
		Set tTo = pPrev_##class(%File).GetFilename(tFile)
		If '##class(%File).Rename(tFile, tTo) Quit
		Set pMoved = pMoved_$ListBuild($ListBuild(tFile, tTo))
	}
	If $ListLength(pMoved) '= $ListLength(tFiles) Quit $$$ERROR($$$GeneralError, "The current identity could not be moved to previous/; nothing was changed.")
	Quit $$$OK
}

ClassMethod RestoreOwn(pMoved As %List) [ Private ]
{
	Set tPtr = 0
	While $ListNext(pMoved, tPtr, tPair) { Do ##class(%File).Rename($List(tPair, 2), $List(tPair, 1)) }
}

}
