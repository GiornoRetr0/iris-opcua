Include %occInclude

/// Server half of the terminal installer (<tt>installer/</tt>). The CLI uploads and
/// compiles this class into <tt>%SYS</tt> over the Atelier REST API, then calls these
/// SQL procedures through <tt>/api/atelier/v1/%SYS/action/query</tt>.
///
/// Rules: every procedure returns one JSON object with <tt>step</tt>, <tt>ok</tt>,
/// <tt>message</tt> and step-specific fields, and never throws. Arguments arrive as
/// SQL parameters and are validated here; nothing is ever evaluated as code.
/// Inspection procedures change nothing. Mutating procedures refuse to run without
/// the installer privileges, and never modify a resource this class did not create.
///
/// Separate from <class>IRISConfig.Installer</class>, the Docker demo installer, on purpose.
Class IRISConfig.ClientInstaller
{

/// REST dispatch class the web application must point to.
Parameter DispatchClass = "OPCUA.REST.Handler";

/// Resource every OPC UA REST application requires.
Parameter ApiResource = "OPCUA_API";

/// Per-namespace role granting the API resource plus the namespace's database: OPCUA_API_&lt;NS&gt;.
/// One role per namespace, so installing a second namespace never widens an existing role.
Parameter ApiRolePrefix = "OPCUA_API_";

/// Native files the CLI may stage into the IRIS bin directory, Linux then Windows. Nothing else is writable.
Parameter NativeFiles = "irisopcua.so,libopen62541.so.0,libcrypto.so.1.1,IrisOPCUA.dll,open62541.dll,libcrypto-1_1-x64.dll";

/// Crypto libraries are never replaced: an existing copy belongs to IRIS or the OS.
Parameter CryptoFiles = "libcrypto.so.1.1,libcrypto-1_1-x64.dll";

/// Instance identity, platform, privileges and whether IRIS can write its bin directory.
ClassMethod Info() As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("info")
	Try {
		Set r.user = $Username
		Set r.version = $ZVersion
		Set r.os = $System.Version.GetOS()
		Set r.platform = $System.Version.GetPlatform()
		Set r.guid = ##class(%SYS.System).InstanceGUID()
		Set r.binDir = $System.Util.BinaryDirectory()
		Set r.mgrDir = $System.Util.ManagerDirectory()
		Set p = {}
		Do p.%Set("development", $System.Security.Check("%Development","USE"), "boolean")
		Do p.%Set("adminManage", $System.Security.Check("%Admin_Manage","USE"), "boolean")
		Do p.%Set("adminSecure", $System.Security.Check("%Admin_Secure","USE"), "boolean")
		Do p.%Set("irissysWrite", $System.Security.Check("%DB_IRISSYS","WRITE"), "boolean")
		Set r.privileges = p
		Do r.%Set("binWritable", ..BinWritable(), "boolean")
		Set list = []
		Do ##class(%SYS.Namespace).ListAll(.all)
		Set ns = ""
		For {
			Set ns = $Order(all(ns))
			Quit:ns=""
			Continue:..IsSystemNamespace(ns)||'##class(Config.Namespaces).Exists(ns)
			Do list.%Push(..DescribeNamespace(ns))
		}
		Set r.namespaces = list
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Classify one namespace: missing (create), reusable, or a conflict with reasons.
ClassMethod InspectNamespace(pNS As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("namespace")
	Try {
		Set pNS = $ZConvert(pNS, "U")
		If '..ValidNamespace(pNS) { Set r.message = "Invalid namespace name '"_pNS_"'. Use letters, digits, '-' or '_', starting with a letter." Quit }
		If ..IsSystemNamespace(pNS) { Set r.message = pNS_" is a system namespace. Choose a dedicated namespace such as OPCUA." Quit }
		Set r.namespace = ..DescribeNamespace(pNS)
		Set r.databaseDir = ..DatabaseDir(pNS)
		Do r.%Set("databaseExists", ##class(%File).Exists(r.databaseDir_"IRIS.DAT") && '..DatabaseOwned(pNS), "boolean")
		// Creating or reusing the namespace only helps if this account can then use its database.
		// %All passes any check; otherwise an administrator must grant the resource first.
		Set res = $Select(r.namespace.state = "missing":"%DB_"_pNS, 1:..DatabaseResource(pNS))
		Set:res="" res = "%DB_"_pNS
		Set r.databaseResource = res
		Do r.%Set("databaseAccess", $System.Security.Check(res, "READ,WRITE"), "boolean")
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Classify the REST application path for a namespace: missing, reusable, or conflict.
ClassMethod InspectApp(pPath As %String, pNS As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("app")
	Try {
		Set pNS = $ZConvert(pNS, "U")
		If '..ValidAppPath(pPath) { Set r.message = "Invalid web application path '"_pPath_"'. Use a path such as /csp/opcua/api." Quit }
		Set r.app = ..DescribeApp(pPath, pNS)
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Existing native files in the bin directory: size, SHA-256, and whether this installer put them there.
/// <var>pNames</var> is a comma-separated subset of <parameter>NativeFiles</parameter>.
ClassMethod InspectFiles(pNames As %String(MAXLEN="")) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("files")
	Try {
		Set files = []
		For i=1:1:$Length(pNames, ",") {
			Set name = $Piece(pNames, ",", i)
			If '..AllowedFile(name) { Set r.message = "File '"_name_"' is not an OPC UA native file." Return r.%ToJSON() }
			Set path = $System.Util.BinaryDirectory()_name
			Set f = {"name":(name), "path":(path)}
			Do f.%Set("exists", ##class(%File).Exists(path), "boolean")
			If f.exists {
				Set f.size = ##class(%File).GetFileSize(path)
				Set f.sha256 = ..FileSha(path)
			}
			Do f.%Set("owned", $Data(^IRISConfig.ClientInstaller("file", name))#2 && (^IRISConfig.ClientInstaller("file", name) = f.sha256), "boolean")
			Do f.%Set("crypto", ..IsCrypto(name), "boolean")
			Do files.%Push(f)
		}
		Set r.files = files
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Write one base64 chunk to the staging file for <var>pName</var>. <var>pFirst</var>=1 starts a new file.
ClassMethod StageChunk(pName As %String, pB64 As %String(MAXLEN=""), pFirst As %Integer) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("stage")
	Try {
		Quit:'..Guard(r)
		If '..AllowedFile(pName) { Set r.message = "File '"_pName_"' is not an OPC UA native file." Quit }
		Set path = ..StagingPath(pName)
		Set s = ##class(%Stream.FileBinary).%New()
		$$$ThrowOnError(s.LinkToFile(path))
		If pFirst { Do s.Clear() } Else { Do s.MoveToEnd() }
		$$$ThrowOnError(s.Write($System.Encryption.Base64Decode(pB64)))
		$$$ThrowOnError(s.%Save())
		Set r.size = s.Size
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Verify the staged file against <var>pSha</var> and move it into place.
/// An identical existing file is reused; a different existing file is never overwritten.
ClassMethod CommitFile(pName As %String, pSha As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("commit")
	Try {
		Quit:'..Guard(r)
		If '..AllowedFile(pName) { Set r.message = "File '"_pName_"' is not an OPC UA native file." Quit }
		Set pSha = $ZConvert(pSha, "L")
		Set staged = ..StagingPath(pName), final = $System.Util.BinaryDirectory()_pName
		Set r.path = final
		If '##class(%File).Exists(staged) { Set r.message = "No staged upload for "_pName_"." Quit }
		Set got = ..FileSha(staged)
		If got '= pSha {
			Do ##class(%File).Delete(staged)
			Set r.message = "Upload of "_pName_" is corrupt (SHA-256 "_got_", expected "_pSha_"). Retry the installation."
			Quit
		}
		If ##class(%File).Exists(final) {
			Do ##class(%File).Delete(staged)
			If ..FileSha(final) = pSha { Set r.action = "reuse" Do r.%Set("ok", 1, "boolean") Quit }
			Set r.action = "conflict"
			Set r.message = final_" already exists with different content. It was not replaced. "_$Select(..IsCrypto(pName):"Crypto libraries are never replaced.", 1:"Replace it during a maintenance window, then retry.")
			Quit
		}
		If '##class(%File).Rename(staged, final) { Set r.message = "Could not move "_staged_" to "_final_"." Quit }
		Set ^IRISConfig.ClientInstaller("file", pName) = pSha
		Set r.action = "installed"
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Create the namespace and its database with interoperability enabled. Reuses an existing one
/// only when <method>DescribeNamespace</method> classifies it as reusable.
/// Uses the Security/Config APIs rather than %Installer: its manifest writes ^SECURITY directly,
/// which fails for an administrator without %All. Every step is repeatable, so an interrupted
/// creation resumes; a database this class did not create is never adopted.
ClassMethod CreateNamespace(pNS As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("namespace")
	Try {
		Quit:'..Guard(r)
		Set pNS = $ZConvert(pNS, "U")
		If '..ValidNamespace(pNS) || ..IsSystemNamespace(pNS) { Set r.message = "Namespace '"_pNS_"' cannot be used." Quit }
		Set d = ..DescribeNamespace(pNS)
		If d.state = "conflict" { Set r.message = "Namespace "_pNS_" is in use by something else: "_d.reason Quit }
		If (d.state '= "missing") && d.interoperability { Set r.action = "reuse" Do r.%Set("ok", 1, "boolean") Quit }
		Set dir = ..DatabaseDir(pNS), res = "%DB_"_pNS
		If ##class(%File).Exists(dir_"IRIS.DAT") && '..DatabaseOwned(pNS) { Set r.message = "A database file already exists at "_dir_". It was not touched; choose another namespace name." Quit }
		If '##class(Security.Resources).Exists(res) {
			$$$ThrowOnError(##class(Security.Resources).Create(res, "Database "_pNS_" (created by the terminal installer)", "", ""))
		}
		If '##class(%File).Exists(dir_"IRIS.DAT") {
			Set ^IRISConfig.ClientInstaller("db", pNS) = dir
			If '##class(%File).CreateDirectoryChain(dir) { Set r.message = "Could not create "_dir_"." Quit }
			$$$ThrowOnError(##class(SYS.Database).CreateDatabase(dir, , , , res))
		}
		If ##class(Config.Databases).Exists(pNS) {
			$$$ThrowOnError(##class(Config.Databases).Get(pNS, .db))
			If ##class(%File).NormalizeDirectory(db("Directory")) '= dir { Set r.message = "A database named "_pNS_" already exists at "_db("Directory")_". Choose another namespace name." Quit }
		} Else {
			Set db("Directory") = dir
			$$$ThrowOnError(##class(Config.Databases).Create(pNS, .db))
		}
		If '##class(Config.Namespaces).Exists(pNS) {
			Set ns("Globals") = pNS, ns("Routines") = pNS
			$$$ThrowOnError(##class(Config.Namespaces).Create(pNS, .ns))
		}
		Set ^IRISConfig.ClientInstaller("ns", pNS) = $ZDateTime($Horolog, 3)
		If '##class(%EnsembleMgr).IsEnsembleNamespace(pNS) {
			$$$ThrowOnError(##class(%EnsembleMgr).EnableNamespace(pNS, 0))
		}
		Set r.action = $Select(d.state = "missing":"created", 1:"completed")
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Register the native library for the namespace, then load it and read its version.
ClassMethod RegisterLibrary(pNS As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("library")
	Try {
		Quit:'..Guard(r)
		Set pNS = $ZConvert(pNS, "U")
		If '..NamespaceReady(pNS, r) Quit
		Set path = $System.Util.BinaryDirectory()_..LibraryFile()
		If '##class(%File).Exists(path) { Set r.message = path_" is missing. Install the native libraries first." Quit }
		Set home = $Namespace, $Namespace = pNS
		Set sc = ##class(OPCUA.Utils).Install(path)
		Set $Namespace = home
		$$$ThrowOnError(sc)
		Do ..LoadInto(r, path, pNS)
	} Catch e { Set $Namespace = "%SYS" Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Create the REST application (plus its resource and role), or reuse a matching one.
ClassMethod CreateApp(pPath As %String, pNS As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("app")
	Try {
		Quit:'..Guard(r)
		Set pNS = $ZConvert(pNS, "U")
		If '..ValidAppPath(pPath) { Set r.message = "Invalid web application path '"_pPath_"'." Quit }
		If '..NamespaceReady(pNS, r) Quit
		Set d = ..DescribeApp(pPath, pNS)
		If d.state = "conflict" { Set r.message = d.reason Quit }
		Set role = ..#ApiRolePrefix_pNS, r.role = role
		If d.state = "reuse" { Set r.action = "reuse", r.resource = d.resource Do r.%Set("ok", 1, "boolean") Quit }
		Set res = ..#ApiResource
		If '##class(Security.Resources).Exists(res) {
			$$$ThrowOnError(##class(Security.Resources).Create(res, "OPC UA REST API (created by the terminal installer)", ""))
			Set ^IRISConfig.ClientInstaller("resource", res) = 1
		}
		If '##class(Security.Roles).Exists(role) {
			Set dbres = ..DatabaseResource(pNS)
			Set grants = res_":U"_$Select(dbres'="":","_dbres_":RW", 1:"")
			$$$ThrowOnError(##class(Security.Roles).Create(role, "Access to the OPC UA REST API (created by the terminal installer)", grants))
			Set ^IRISConfig.ClientInstaller("role", role) = 1
			Set r.roleCreated = role
		}
		Set p("NameSpace") = pNS
		Set p("DispatchClass") = ..#DispatchClass
		Set p("Description") = "OPC UA Adapter REST API (created by the terminal installer)"
		Set p("Enabled") = 1
		Set p("AutheEnabled") = 32
		Set p("Resource") = res
		$$$ThrowOnError(##class(Security.Applications).Create(pPath, .p))
		Set ^IRISConfig.ClientInstaller("app", pPath) = pNS
		Set r.action = "created", r.resource = res
		Do r.%Set("ok", 1, "boolean")
	} Catch e { Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// Read-only check of an installation: classes, library registration and load, REST application.
ClassMethod Verify(pNS As %String, pPath As %String) As %String(MAXLEN="") [ SqlProc ]
{
	Set r = ..Result("verify")
	Try {
		Set pNS = $ZConvert(pNS, "U")
		If '..ValidNamespace(pNS) || '..ValidAppPath(pPath) { Set r.message = "Invalid namespace or path." Quit }
		Set d = ..DescribeNamespace(pNS)
		Set r.namespace = d
		Set checks = []
		Set ok = (d.state '= "missing") && d.interoperability
		Do checks.%Push(..Check("namespace", ok, $Select(ok:"Namespace "_pNS_" exists with interoperability", d.state="missing":"Namespace "_pNS_" does not exist", 1:"Namespace "_pNS_" has no interoperability")))
		// Only system classes may be called while in the target namespace: this class lives in %SYS.
		Set classes = 0, path = "", dispatch = ..#DispatchClass
		If ok {
			Set home = $Namespace, $Namespace = pNS
			Set classes = ##class(%Dictionary.CompiledClass).%ExistsId(dispatch) && ##class(%Dictionary.CompiledClass).%ExistsId("OPCUA.Utils") && ##class(%Dictionary.CompiledClass).%ExistsId("OPCUA.Client")
			Set path = $Get(^OPCUA.Library.Pathname)
			Set $Namespace = home
		}
		Do checks.%Push(..Check("classes", classes, $Select(classes:"OPC UA classes compiled", 1:"OPC UA classes are not compiled in "_pNS)))
		Set lib = {"ok":false}
		If classes {
			If path = "" { Set lib.message = "Native library is not registered in "_pNS }
			Else { Do ..LoadInto(lib, path, pNS) }
		} Else { Set lib.message = "Skipped: classes are not compiled" }
		Do checks.%Push(..Check("library", lib.ok, lib.message, lib.version))
		Set a = ..DescribeApp(pPath, pNS)
		Set r.app = a
		// Whether this account may use the application: tells an access problem from a routing problem.
		Do r.%Set("apiAccess", (a.resource = "") || $System.Security.Check(a.resource, "USE"), "boolean")
		Do checks.%Push(..Check("app", a.state = "reuse", $Case(a.state, "reuse":"REST application "_pPath_" serves "_pNS, "missing":"REST application "_pPath_" does not exist", :a.reason)))
		Set r.checks = checks
		Set all = 1
		For i=0:1:checks.%Size()-1 Set all = all && checks.%Get(i).ok
		Do r.%Set("ok", all, "boolean")
		Set:'all r.message = "Some checks failed."
	} Catch e { Set $Namespace = "%SYS" Do ..Fail(r, e) }
	Quit r.%ToJSON()
}

/// ---- internals ----
ClassMethod Result(pStep As %String) As %DynamicObject [ Internal, Private ]
{
	Set r = {"step":(pStep), "message":""}
	Do r.%Set("ok", 0, "boolean")
	Quit r
}

ClassMethod Fail(r As %DynamicObject, e As %Exception.AbstractException) [ Internal, Private ]
{
	Do r.%Set("ok", 0, "boolean")
	Set r.message = $Select(e.%IsA("%Exception.StatusException"):$System.Status.GetErrorText(e.AsStatus()), 1:e.DisplayString())
}

ClassMethod Check(pName, pOk, pMessage, pValue = "") As %DynamicObject [ Internal, Private ]
{
	Set c = {"name":(pName), "message":(pMessage)}
	Do c.%Set("ok", ''pOk, "boolean")
	Set:pValue'="" c.value = pValue
	Quit c
}

/// Mutating procedures require every installer privilege, whoever calls them.
ClassMethod Guard(r As %DynamicObject) As %Boolean [ Internal, Private ]
{
	Set missing = ""
	For p = "%Development", "%Admin_Manage", "%Admin_Secure" {
		Set:'$System.Security.Check(p, "USE") missing = missing_$ListBuild(p_":USE")
	}
	Set:'$System.Security.Check("%DB_IRISSYS", "WRITE") missing = missing_$ListBuild("%DB_IRISSYS:WRITE")
	If missing = "" Quit 1
	Set r.message = "Missing IRIS privileges: "_$ListToString(missing, ", ")
	Quit 0
}

ClassMethod ValidNamespace(pNS As %String) As %Boolean [ Internal, Private ]
{
	Quit $Match(pNS, "[A-Za-z][A-Za-z0-9_-]{0,62}")
}

ClassMethod ValidAppPath(pPath As %String) As %Boolean [ Internal, Private ]
{
	Quit $Match(pPath, "/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*")
}

ClassMethod IsSystemNamespace(pNS As %String) As %Boolean [ Internal, Private ]
{
	Set pNS = $ZConvert(pNS, "U")
	Quit ($Extract(pNS) = "%") || ("^HSLIB^HSSYS^ENSLIB^IRISLIB^IRISSYS^IRISAUDIT^IRISMETRICS^" [ ("^"_pNS_"^"))
}

ClassMethod AllowedFile(pName As %String) As %Boolean [ Internal, Private ]
{
	Quit (pName '= "") && ($ListFind($ListFromString(..#NativeFiles), pName) > 0)
}

ClassMethod IsCrypto(pName As %String) As %Boolean [ Internal, Private ]
{
	Quit $ListFind($ListFromString(..#CryptoFiles), pName) > 0
}

/// The connector library's file name on this server's platform.
ClassMethod LibraryFile() As %String [ Internal, Private ]
{
	Quit $Select($System.Version.GetOS() = "Windows":"IrisOPCUA.dll", 1:"irisopcua.so")
}

ClassMethod StagingPath(pName As %String) As %String [ Internal, Private ]
{
	Quit $System.Util.BinaryDirectory()_".opcua-setup-"_pName_".part"
}

ClassMethod FileSha(pPath As %String) As %String [ Internal, Private ]
{
	Set s = ##class(%Stream.FileBinary).%New()
	$$$ThrowOnError(s.LinkToFile(pPath))
	Quit $ZConvert(##class(%xsd.hexBinary).LogicalToXSD($System.Encryption.SHAHashStream(256, s)), "L")
}

/// Whether the IRIS process can create a file in its bin directory. The probe file is removed at once.
ClassMethod BinWritable() As %Boolean [ Internal, Private ]
{
	Set path = $System.Util.BinaryDirectory()_".opcua-setup-probe"
	Set f = ##class(%File).%New(path)
	If $$$ISERR(f.Open("WN")) Quit 0
	Do f.Close()
	Do ##class(%File).Delete(path)
	Quit 1
}

/// state: missing | owned | backend | empty | conflict. Only conflict blocks installation.
ClassMethod DescribeNamespace(pNS As %String) As %DynamicObject [ Internal, Private ]
{
	Set d = {"name":(pNS), "state":"missing", "reason":""}
	Do d.%Set("interoperability", 0, "boolean")
	Quit:'##class(Config.Namespaces).Exists(pNS) d
	Try {
		Do ..ClassifyNamespace(pNS, d)
	} Catch e {
		// Typically <PROTECT>: this account cannot read the namespace's databases.
		Set d.state = "conflict", d.reason = "this account cannot inspect it ("_$Piece(e.DisplayString(), " ")_")"
	}
	Quit d
}

ClassMethod ClassifyNamespace(pNS As %String, d As %DynamicObject) [ Internal, Private ]
{
	Do d.%Set("interoperability", ##class(%EnsembleMgr).IsEnsembleNamespace(pNS), "boolean")
	Do d.%Set("backend", $Data(^|pNS|oddCOM("OPCUA.Utils")) > 0, "boolean")
	Do d.%Set("owned", $Data(^IRISConfig.ClientInstaller("ns", pNS)) > 0, "boolean")
	// Classes stored in the namespace's own routine database, not mapped from a library.
	Set foreign = [], dir = ..RoutineDir(pNS)
	If dir '= "" {
		Set cls = ""
		For {
			Set cls = $Order(^|"^^"_dir|oddDEF(cls))
			Quit:cls=""
			Continue:$Extract(cls, 1, 6)="OPCUA."
			Do foreign.%Push(cls)
			Quit:foreign.%Size()>=5
		}
	}
	Set d.foreignClasses = foreign
	Set prod = ""
	Set:d.interoperability prod = $Get(^|pNS|Ens.Configuration("csp","LastProduction"))
	Set d.production = prod
	Set reasons = ""
	Set:'d.interoperability reasons = reasons_$ListBuild("interoperability is not enabled")
	Set:(prod'="")&&(prod'="OPCUA.Pipeline.Production") reasons = reasons_$ListBuild("it hosts production "_prod)
	Set:foreign.%Size()&&'d.backend&&'d.owned reasons = reasons_$ListBuild("it contains other classes (e.g. "_foreign.%Get(0)_")")
	If reasons '= "" { Set d.state = "conflict", d.reason = $ListToString(reasons, "; ") }
	ElseIf d.owned { Set d.state = "owned" }
	ElseIf d.backend { Set d.state = "backend" }
	Else { Set d.state = "empty" }
}

ClassMethod RoutineDir(pNS As %String) As %String [ Internal, Private ]
{
	Quit:$$$ISERR(##class(Config.Namespaces).Get(pNS, .n)) ""
	Quit:$$$ISERR(##class(Config.Databases).Get($Get(n("Routines")), .db)) ""
	Quit ##class(%File).NormalizeDirectory($Get(db("Directory")))
}

ClassMethod DatabaseResource(pNS As %String) As %String [ Internal, Private ]
{
	Quit:$$$ISERR(##class(Config.Namespaces).Get(pNS, .n)) ""
	Quit:$$$ISERR(##class(Config.Databases).Get($Get(n("Globals")), .db)) ""
	Set o = ##class(SYS.Database).%OpenId($Get(db("Directory")))
	Quit $Select($IsObject(o):o.ResourceName, 1:"")
}

/// state: missing | reuse | conflict.
ClassMethod DescribeApp(pPath As %String, pNS As %String) As %DynamicObject [ Internal, Private ]
{
	Set d = {"path":(pPath), "state":"missing", "reason":""}
	Quit:'##class(Security.Applications).Exists(pPath) d
	$$$ThrowOnError(##class(Security.Applications).Get(pPath, .p))
	Set d.namespace = $Get(p("NameSpace")), d.dispatchClass = $Get(p("DispatchClass")), d.resource = $Get(p("Resource"))
	Do d.%Set("enabled", +$Get(p("Enabled")), "boolean")
	Do d.%Set("passwordAuth", $ZBoolean(+$Get(p("AutheEnabled")), 32, 1) = 32, "boolean")
	Do d.%Set("unauthenticated", $ZBoolean(+$Get(p("AutheEnabled")), 64, 1) = 64, "boolean")
	Do d.%Set("owned", $Data(^IRISConfig.ClientInstaller("app", pPath)) > 0, "boolean")
	If ($ZConvert(d.namespace, "U") '= pNS) || (d.dispatchClass '= ..#DispatchClass) {
		Set d.state = "conflict"
		Set d.reason = "Web application "_pPath_" already exists for "_d.namespace_$Select(d.dispatchClass'="":" ("_d.dispatchClass_")", 1:"")_". It was not changed; choose another path."
	} ElseIf 'd.enabled {
		Set d.state = "conflict", d.reason = "Web application "_pPath_" exists but is disabled. Enable it in the Management Portal, then retry."
	} Else { Set d.state = "reuse" }
	Quit d
}

ClassMethod NamespaceReady(pNS As %String, r As %DynamicObject) As %Boolean [ Internal, Private ]
{
	If '..ValidNamespace(pNS) || '##class(Config.Namespaces).Exists(pNS) { Set r.message = "Namespace "_pNS_" does not exist." Quit 0 }
	Quit 1
}

/// Load the library into this process and read its version. On failure, report the loader's own words
/// from messages.log: $ZF(-4) itself only says the load failed.
ClassMethod LoadInto(r As %DynamicObject, pPath As %String, pNS As %String) [ Internal, Private ]
{
	Set r.path = pPath, home = $Namespace, loaded = 0, sc = $$$OK
	Try {
		Set $Namespace = pNS
		Set %ZUtilsIrisOpcuaLibraryId = $ZF(-4, 1, pPath), loaded = 1
		Set sc = ##class(OPCUA.Utils).Initialize()
		If $$$ISOK(sc) Set sc = ##class(OPCUA.Utils).GetVersion(.v)
	} Catch e {
		Set err = e.DisplayString()
	}
	Set $Namespace = home
	If 'loaded {
		Set r.message = "Native connector could not load: "_$Get(err)
		Set hint = ..LogTail(pPath)
		Set:hint'="" r.message = r.message_". IRIS reported: "_hint
		Do r.%Set("ok", 0, "boolean")
		Quit
	}
	Set:$Data(err) sc = $$$ERROR($$$GeneralError, err)
	If $$$ISERR(sc) {
		Set r.message = "Native connector loaded but did not initialize: "_$System.Status.GetErrorText(sc)
		Do r.%Set("ok", 0, "boolean")
		Quit
	}
	Set r.version = $ListGet(v, 2)
	Set r.message = "Native connector loaded, version "_r.version
	Do r.%Set("ok", 1, "boolean")
}

/// The most recent messages.log line about loading <var>pPath</var>, if any.
ClassMethod LogTail(pPath As %String) As %String [ Internal, Private ]
{
	Set hint = ""
	Try {
		Set s = ##class(%Stream.FileCharacter).%New()
		Quit:$$$ISERR(s.LinkToFile($System.Util.ManagerDirectory()_"messages.log"))
		Do:s.Size>65536 s.MoveTo(s.Size-65536)
		Set name = ##class(%File).GetFilename(pPath)
		While 's.AtEnd {
			Set line = s.ReadLine()
			Set:(line[name)||(line["cannot open shared object")||(line["dlopen")||(line["LoadLibrary") hint = $ZStrip(line, "<>W")
		}
	} Catch {}
	Quit $Extract(hint, 1, 500)
}

ClassMethod DatabaseDir(pNS As %String) As %String [ Internal, Private ]
{
	Quit ##class(%File).NormalizeDirectory($System.Util.ManagerDirectory()_$ZConvert(pNS, "L"))
}

/// A database directory this class started creating (so an interrupted creation may resume).
ClassMethod DatabaseOwned(pNS As %String) As %Boolean [ Internal, Private ]
{
	Quit $Get(^IRISConfig.ClientInstaller("db", pNS)) = ..DatabaseDir(pNS)
}

}
