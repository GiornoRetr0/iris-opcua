Include (%occInclude, OPCUA.Constants)

/// ObjectScript face of the connector's certificate operations (create, inspect, check,
/// import). Thin: it checks the connector version, calls the native entry point and
/// turns the result into a status or a <class>%DynamicObject</class>. Key bytes only
/// ever travel as hex in a $ZF argument and are not logged here.
Class OPCUA.Security.Native
{

/// A $ZF argument or result is capped near 32 KB; hex doubles the bytes.
Parameter MaxHexChars = 32000;

ClassMethod Gate() As %Status [ Internal ]
{
	If ##class(OPCUA.Utils).SupportsPki() Quit $$$OK
	Quit $$$ERROR($$$GeneralError, "The OPC UA connector on this server is older than 0.5.0 and cannot manage certificates. Reinstall it with iris-opcua-setup.")
}

/// Generates a self-signed identity: the certificate and key are written as DER files.
ClassMethod CreateIdentity(pCertPath As %String, pKeyPath As %String, pClientURI As %String, pHostname As %String, pCommonName As %String, pDays As %Integer = 3650, pKeyBits As %Integer = 2048) As %Status
{
	Set tSC = ..Gate()
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set tRet = $ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfPkiCreateIdentity,"",$LB(pCertPath,pKeyPath,pClientURI,pHostname,pCommonName,pDays,pKeyBits))
		If $List(tRet,1)'=0 Set tSC = ##class(OPCUA.Client).DecodeError(tRet)
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Describes a certificate, from a file (<var>pIsPath</var> 1) or from hex bytes (0).
ClassMethod InspectCert(pSource As %String, pIsPath As %Boolean, Output pInfo As %DynamicObject) As %Status
{
	Set pInfo = ""
	Set tSC = ..Gate()
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set tRet = $ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfPkiInspectCert,"",$LB(pSource,+pIsPath))
		If $List(tRet,1)'=0 Set tSC = ##class(OPCUA.Client).DecodeError(tRet) Quit
		// $LB(0, 0, subject, issuer, notBefore, notAfter, uris, dns, ips, sha256, selfSigned, isCA, keyType, keyBits, usage, derHex)
		Set pInfo = {
			"subject": ($ListGet(tRet,3)),
			"issuer": ($ListGet(tRet,4)),
			"notBefore": ($ListGet(tRet,5)),
			"notAfter": ($ListGet(tRet,6)),
			"sanUris": (..ToArray($ListGet(tRet,7))),
			"sanDns": (..ToArray($ListGet(tRet,8))),
			"sanIps": (..ToArray($ListGet(tRet,9))),
			"sha256": ($ListGet(tRet,10)),
			"selfSigned": (+$ListGet(tRet,11)),
			"isCA": (+$ListGet(tRet,12)),
			"keyType": ($ListGet(tRet,13)),
			"keyBits": (+$ListGet(tRet,14)),
			"keyUsage": (..ToArray($ListGet(tRet,15))),
			"derHex": ($ListGet(tRet,16))
		}
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Whether the key belongs to the certificate. A readable but unrelated pair is OK with
/// <var>pMatch</var> 0; an unreadable file is an error.
ClassMethod CheckKeyPair(pCertPath As %String, pKeyPath As %String, Output pMatch As %Boolean) As %Status
{
	Set pMatch = 0
	Set tSC = ..Gate()
	Quit:$$$ISERR(tSC) tSC
	Try {
		Set tRet = $ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfPkiCheckKeyPair,"",$LB(pCertPath,pKeyPath))
		If $List(tRet,1)'=0 Set tSC = ##class(OPCUA.Client).DecodeError(tRet) Quit
		Set pMatch = +$ListGet(tRet,3)
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Converts an uploaded file (hex) into the form open62541 reads (DER; the key as
/// unencrypted PKCS#8) and writes it to the given paths. <var>pKind</var> is
/// cert, key, p12 or crl; nothing is written unless everything parsed. The native layer
/// takes a key's path in the key slot, so for kind "key" a single path may be given as
/// <var>pOutCertPath</var> and is used for the key.
ClassMethod Normalise(pKind As %String, pDataHex As %String, pPassword As %String, pOutCertPath As %String, pOutKeyPath As %String = "") As %Status
{
	Set tSC = ..Gate()
	Quit:$$$ISERR(tSC) tSC
	If $Length(pDataHex) > ..#MaxHexChars {
		Quit $$$ERROR($$$GeneralError, "The file is too large to import (max 16 KB); use files already on IRIS instead.")
	}
	If pKind = "key", pOutKeyPath = "" Set pOutKeyPath = pOutCertPath
	Try {
		Set tRet = $ZF(-5,%ZUtilsIrisOpcuaLibraryId,$$$zfPkiNormalise,"",$LB(pKind,pDataHex,pPassword,pOutCertPath,pOutKeyPath))
		If $List(tRet,1)'=0 Set tSC = ##class(OPCUA.Client).DecodeError(tRet)
	} Catch e {
		Set tSC = e.AsStatus()
	}
	Quit tSC
}

/// A $LB (possibly "" for none) as a JSON array of strings.
ClassMethod ToArray(pList As %List) As %DynamicArray [ Internal ]
{
	Set tArr = []
	Set tPtr = 0
	While $ListNext(pList, tPtr, tItem) { Do tArr.%Push(tItem) }
	Quit tArr
}

}
