/// Instance-wide store for the OPC UA client identity and per-server trust.
///
/// Metadata lives in the global ^%OPCUA.Security as JSON strings:
///   ^%OPCUA.Security("identity")      -> identity config
///   ^%OPCUA.Security("servers", key)  -> trusted-server entry
/// Files (certificates, keys, CRLs) live under Root() = <manager dir>/opcua-pki/
/// (own/, previous/, servers/<key>/trusted|crl).
///
/// Mapping: globals whose names start with "%" are system globals and are stored
/// in IRISSYS (the %SYS default routing), so every namespace sees the same data
/// and the identity is per instance. Verified in the OPCUA namespace as SuperUser:
/// ##class(%SYS.Namespace).GetGlobalDest("OPCUA","^%OPCUA.Security") resolves to
/// the IRISSYS directory (mgr/), and a Set from OPCUA is visible from %SYS (checked as irisowner/SuperUser on 2025.3).
///
/// Tests redirect the store with ^%OPCUA.Security.Override("global") and
/// ("root"); they must kill both afterwards.
Class OPCUA.Security.Store Extends %RegisteredObject
{

Parameter DEFAULTPORT = 4840;

ClassMethod Global() As %String
{
    Set o = $Get(^%OPCUA.Security.Override("global"))
    Quit $Select(o '= "": o, 1: "^%OPCUA.Security")
}

ClassMethod Root() As %String
{
    Set o = $Get(^%OPCUA.Security.Override("root"))
    Quit ##class(%File).NormalizeDirectory($Select(o '= "": o, 1: $System.Util.ManagerDirectory()_"opcua-pki"))
}

/// pWhich: own | previous | servers. Anything else is refused (returns "").
ClassMethod Dir(pWhich As %String) As %String
{
    If (pWhich '= "own") && (pWhich '= "previous") && (pWhich '= "servers") Quit ""
    Quit ##class(%File).NormalizeDirectory(..Root()_pWhich)
}

/// A server key is exactly what ServerKey() produces.
ClassMethod ValidServerKey(pKey As %String) As %Boolean
{
    Quit $Match(pKey, "^[0-9a-f]{16}\z")
}

/// pWhich: trusted | crl. An invalid key or pWhich returns "" (never a path).
ClassMethod ServerDir(pKey As %String, pWhich As %String) As %String
{
    If '..ValidServerKey(pKey) Quit ""
    If (pWhich '= "trusted") && (pWhich '= "crl") Quit ""
    Quit ##class(%File).NormalizeDirectory(..Dir("servers")_pKey_"/"_pWhich)
}

/// Create pPath (and parents); 0700 on non-Windows. Fails if any chmod fails.
ClassMethod EnsureDirs(pPath As %String) As %Status
{
    If $Get(pPath) = "" Quit $$$ERROR($$$GeneralError, "No directory given")
    Set root = ..Root()
    Set path = ##class(%File).NormalizeDirectory(pPath)
    If '##class(%File).DirectoryExists(path) {
        If '##class(%File).CreateDirectoryChain(path, .rc) {
            Quit $$$ERROR($$$GeneralError, "Cannot create directory "_path_": "_$Get(rc))
        }
    }
    If $$$isWINDOWS Quit $$$OK
    // Tighten every level from path up to and including the root.
    Set cur = path
    While (cur '= "") && ($Extract(cur, 1, $Length(root)) = root) {
        If '##class(%File).SetAttributes($Extract(cur, 1, $Length(cur) - 1), 448, .rc) {
            Quit
        }
        Set rc = ""
        If cur = root Quit
        Set cur = ##class(%File).ParentDirectoryName(cur)
    }
    If $Get(rc) '= "" Quit $$$ERROR($$$GeneralError, "Cannot set mode 0700 on "_cur_" (code "_rc_")")
    Quit $$$OK
}

/// scheme+host lowercased, default port explicit, trailing "/" removed, path kept.
ClassMethod NormaliseURL(pURL As %String) As %String
{
    Set url = $ZStrip(pURL, "<>W")
    Set scheme = "opc.tcp"
    If url [ "://" {
        Set scheme = $ZConvert($Piece(url, "://", 1), "L")
        Set rest = $Piece(url, "://", 2, *)
    } Else {
        Set rest = url
    }
    Set slash = $Find(rest, "/")
    If slash {
        Set auth = $Extract(rest, 1, slash - 2), path = $Extract(rest, slash - 1, *)
    } Else {
        Set auth = rest, path = ""
    }
    Set auth = $ZConvert(auth, "L")
    // strip userinfo, if any
    If auth [ "@" Set auth = $Piece(auth, "@", 2, *)
    If $Extract(auth) = "[" {
        Set host = $Piece(auth, "]", 1)_"]", port = $Piece($Piece(auth, "]", 2), ":", 2)
    } Else {
        Set host = $Piece(auth, ":", 1), port = $Piece(auth, ":", 2)
    }
    If port = "" Set port = ..#DEFAULTPORT
    While $Extract(path, $Length(path)) = "/" { Set path = $Extract(path, 1, $Length(path) - 1) }
    Quit scheme_"://"_host_":"_port_path
}

ClassMethod URLHost(pURL As %String) As %String
{
    Set n = ..NormaliseURL(pURL)
    Set auth = $Piece($Piece(n, "://", 2), "/", 1)
    If $Extract(auth) = "[" Quit $Piece(auth, "]", 1)_"]"
    Quit $Piece(auth, ":", 1)
}

/// First 16 lowercase hex characters of SHA-256 over the normalised URL.
ClassMethod ServerKey(pURL As %String) As %String
{
    Set hash = $System.Encryption.SHAHash(256, ..NormaliseURL(pURL))
    Set hex = ""
    For i = 1:1:8 Set hex = hex_$ZConvert($Extract($ZHex($Ascii(hash, i) + 256), 2, 3), "L")
    Quit hex
}

/// urn:<hostname>:intersystems:iris:<instance>:opcua, lowercased, allowlisted.
ClassMethod DefaultClientURI() As %String
{
    Set host = ..Clean($ZConvert($System.INetInfo.LocalHostName(), "L"))
    Set inst = ..Clean($Piece($System, ":", 2))
    Quit "urn:"_$Select(host '= "": host, 1: "localhost")_":intersystems:iris:"_$Select(inst '= "": inst, 1: "iris")_":opcua"
}

/// Replace characters outside [a-z0-9._-] with "-".
ClassMethod Clean(pText As %String) As %String [ Private ]
{
    Set t = $ZConvert(pText, "L"), out = ""
    For i = 1:1:$Length(t) Set c = $Extract(t, i), out = out_$Select(c?1(1L,1N,1".",1"_",1"-"): c, 1: "-")
    Quit $ZStrip(out, "<>", "-")
}

ClassMethod ValidClientURI(pURI As %String) As %Boolean
{
    Quit $Match(pURI, "^[a-z0-9:._-]+\z") && (pURI [ ":") && ($Length(pURI) <= 255)
}

ClassMethod GetIdentity(Output pCfg As %DynamicObject) As %Boolean
{
    Set pCfg = ""
    Set g = ..Global()
    Set raw = $Get(@g@("identity"))
    If raw = "" Quit 0
    Set pCfg = {}.%FromJSON(raw)
    Quit 1
}

ClassMethod SaveIdentity(pCfg As %DynamicObject)
{
    Set g = ..Global()
    Set @g@("identity") = pCfg.%ToJSON()
}

ClassMethod ClearIdentity()
{
    Set g = ..Global()
    Kill @g@("identity")
}

ClassMethod GetServer(pKey As %String, Output pEntry As %DynamicObject) As %Boolean
{
    Set pEntry = ""
    If '..ValidServerKey(pKey) Quit 0
    Set g = ..Global()
    Set raw = $Get(@g@("servers", pKey))
    If raw = "" Quit 0
    Set pEntry = {}.%FromJSON(raw)
    Quit 1
}

ClassMethod SaveServer(pKey As %String, pEntry As %DynamicObject) As %Status
{
    If '..ValidServerKey(pKey) Quit $$$ERROR($$$GeneralError, "Invalid server key")
    Set g = ..Global()
    Set @g@("servers", pKey) = pEntry.%ToJSON()
    Quit $$$OK
}

ClassMethod RemoveServer(pKey As %String) As %Status
{
    If '..ValidServerKey(pKey) Quit $$$ERROR($$$GeneralError, "Invalid server key")
    Set g = ..Global()
    Kill @g@("servers", pKey)
    Quit $$$OK
}

ClassMethod ListServers() As %DynamicArray
{
    Set arr = []
    Set g = ..Global()
    Set k = ""
    For {
        Set k = $Order(@g@("servers", k), 1, raw)
        Quit:k=""
        // One corrupt entry must not hide the others.
        Try { Do arr.%Push({}.%FromJSON(raw)) } Catch {}
    }
    Quit arr
}

}
