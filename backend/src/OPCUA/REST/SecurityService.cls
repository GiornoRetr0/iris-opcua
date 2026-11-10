Include %occInclude

/// REST face of the managed Sign &amp; Encrypt setup (<tt>/security/*</tt>): the IRIS
/// client identity (<class>OPCUA.Security.Identity</class>) and the trusted OPC UA
/// servers (<class>OPCUA.Security.Trust</class>). Thin on purpose; the rules live in
/// those classes.
///
/// Every method first needs <tt>%Admin_Secure:USE</tt> (a SuperUser account), else 403.
/// No response carries key material: the identity is described by its public facts and
/// the certificate download is the public certificate only.
Class OPCUA.REST.SecurityService
{

Parameter Resource = "%Admin_Secure";

Parameter Forbidden = "Managing OPC UA certificates needs the %Admin_Secure:USE privilege (a SuperUser account).";

/// Whether the signed-in account may manage certificates. Tests set
/// <tt>^||OPCUA.Tests("securityPrivilege")</tt> to 0 or 1 to stand in for the account.
ClassMethod HasPrivilege() As %Boolean
{
	Quit:$Data(^||OPCUA.Tests("securityPrivilege")) ''^||OPCUA.Tests("securityPrivilege")
	Quit ''$System.Security.Check(..#Resource, "USE")
}

/// The 403 status, or OK when the account may manage certificates.
ClassMethod Guard() As %Status
{
	Quit:..HasPrivilege() $$$OK
	Quit ##class(OPCUA.REST.Error).Forbidden(..#Forbidden)
}

/// A request flag in any of the forms JSON or a query string gives it.
ClassMethod Flag(pBody As %DynamicObject, pName As %String) As %Boolean
{
	set tVal = pBody.%Get(pName)
	Quit $Case($ZConvert(tVal, "L"), 1: 1, "true": 1, "yes": 1, : 0)
}

/// Discovery and network failures come back from Trust as raw statuses (an
/// <tt>Other error</tt> from the native layer). Make them a 502 with a message the user
/// can act on; statuses that already carry an HTTP code pass through.
ClassMethod MapFailure(pSC As %Status) As %Status
{
	Quit:$$$ISOK(pSC) pSC
	Quit:##class(OPCUA.REST.Error).Carried(pSC) pSC
	set tDetail = ##class(OPCUA.Security.Trust).Cut(pSC)
	set tNet = ##class(OPCUA.Security.Diagnose).Classify("", {"reachable": 0}, "", "").message
	Quit ##class(OPCUA.REST.Error).Make(502, tNet_" ("_tDetail_")")
}

/// Status of the IRIS client identity: <tt>GET /security/identity</tt>.
ClassMethod Identity(Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ##class(OPCUA.Security.Identity).Status(.pResult)
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/identity</tt> <tt>{clientURI?, replace?, currentFingerprint?}</tt>.
ClassMethod CreateIdentity(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ##class(OPCUA.Security.Identity).Create(pBody.%Get("clientURI"), ..Flag(pBody, "replace"), pBody.%Get("currentFingerprint"), .pResult)
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/identity/import</tt>
/// <tt>{certificate?, key?, pkcs12?, password?, replace?, currentFingerprint?}</tt>, hex.
/// Either a certificate with its key, or one PKCS#12 file; not both.
ClassMethod ImportIdentity(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tP12 = pBody.%Get("pkcs12")
		if (tP12 '= "") && ((pBody.%Get("certificate") '= "") || (pBody.%Get("key") '= "")) {
			set tSC = ##class(OPCUA.REST.Error).BadRequest("Send either a certificate and key, or one PKCS#12 file, not both.")
			Quit
		}
		set tSC = ##class(OPCUA.Security.Identity).Import(pBody.%Get("certificate"), pBody.%Get("key"), tP12, pBody.%Get("password"), ..Flag(pBody, "replace"), pBody.%Get("currentFingerprint"), .pResult)
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/identity/files</tt> <tt>{certPath, keyPath, replace?, currentFingerprint?}</tt>.
ClassMethod UseFiles(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ##class(OPCUA.Security.Identity).UseFiles(pBody.%Get("certPath"), pBody.%Get("keyPath"), ..Flag(pBody, "replace"), pBody.%Get("currentFingerprint"), .pResult)
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// The public client certificate for download: <var>pData</var> the raw bytes,
/// <var>pFilename</var> and <var>pContentType</var> for the response headers.
/// <var>pFormat</var> is <tt>der</tt> (default) or <tt>pem</tt>.
ClassMethod Certificate(pFormat As %String, Output pData As %String, Output pFilename As %String, Output pContentType As %String) As %Status
{
	set (pData, pFilename, pContentType) = ""
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	set tFormat = $ZConvert($Select(pFormat="":"der", 1:pFormat), "L")
	if (tFormat '= "der") && (tFormat '= "pem") {
		Quit ##class(OPCUA.REST.Error).BadRequest("Format must be der or pem.")
	}
	Try {
		set tSC = ##class(OPCUA.Security.Identity).CertificateBytes(tFormat, .pData, .pFilename)
		set pContentType = $Select(tFormat="pem":"application/x-pem-file", 1:"application/pkix-cert")
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>GET /security/servers</tt>: the trusted servers.
ClassMethod Servers(Output pResult As %DynamicArray) As %Status
{
	set pResult = []
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ##class(OPCUA.Security.Trust).List(.pResult)
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/servers/inspect</tt> <tt>{url}</tt>.
ClassMethod Inspect(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ..RequireURL(pBody, .tURL)
		Quit:$$$ISERR(tSC)
		set tSC = ..MapFailure(##class(OPCUA.Security.Trust).Inspect(tURL, .pResult))
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/servers/trust</tt> <tt>{url, fingerprint, label?}</tt>.
ClassMethod Trust(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ..RequireURL(pBody, .tURL)
		Quit:$$$ISERR(tSC)
		if pBody.%Get("fingerprint") = "" {
			set tSC = ##class(OPCUA.REST.Error).BadRequest("Missing required parameter: fingerprint")
			Quit
		}
		set tSC = ..MapFailure(##class(OPCUA.Security.Trust).Trust(tURL, pBody.%Get("fingerprint"), pBody.%Get("label"), .pResult))
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>POST /security/servers/issuer</tt> <tt>{url, caCertificate, crl}</tt>, hex.
ClassMethod Issuer(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ..RequireURL(pBody, .tURL)
		Quit:$$$ISERR(tSC)
		set tSC = ..MapFailure(##class(OPCUA.Security.Trust).AddIssuer(tURL, pBody.%Get("caCertificate"), pBody.%Get("crl"), .pResult))
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// <tt>DELETE /security/servers/:key</tt>. A key of the wrong shape is a 400, an
/// unknown one a 404.
ClassMethod RemoveServer(pKey As %String, Output pResult As %DynamicObject) As %Status
{
	set pResult = {}
	set tSC = ..Guard()
	Quit:$$$ISERR(tSC) tSC
	Try {
		set tSC = ##class(OPCUA.Security.Trust).Remove(pKey)
		set:$$$ISOK(tSC) pResult.removed = 1
	} Catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

ClassMethod RequireURL(pBody As %DynamicObject, Output pURL As %String) As %Status [ Private ]
{
	set pURL = pBody.%Get("url")
	Quit:pURL="" ##class(OPCUA.REST.Error).BadRequest("Missing required parameter: url")
	// An old connector is its own clear message, not a network failure.
	Quit ##class(OPCUA.Security.Native).Gate()
}

}
