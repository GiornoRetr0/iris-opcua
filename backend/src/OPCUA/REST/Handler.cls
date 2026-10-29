Include %occInclude

/// REST dispatch handler for OPC UA adapter endpoints.
/// Routes requests to service classes and formats consistent JSON responses.
Class OPCUA.REST.Handler Extends %CSP.REST
{

/// Enable CORS. The Angular console is served from a different origin than IRIS
/// (localhost:4200 in development, and any static host in production), so every
/// call it makes is cross-origin. Required, not vestigial.
Parameter HandleCorsRequest = 1;

/// Stateless REST — no CSP session.
Parameter UseSession = 0;

/// Content type for all responses.
Parameter CONTENTTYPE = "application/json";

/// Called by CSP when the request's IRIS sign-in failed (audit #16): answer 401
/// with the usual JSON envelope.
///
/// This follows <method>%CSP.REST.Login</method> (CORS, and OPTIONS preflight
/// allowed without sign-in) except that it sends no <tt>WWW-Authenticate</tt>
/// header: a Basic challenge makes the browser open its own login dialog over the
/// console, which has its own sign-in.
///
/// <b>Under the default setup this does not run.</b> CSP calls it in the pre-login
/// context (user CSPSystem, no roles), which cannot read the namespace's code
/// database (<tt>%DB_OPCUA</tt> has no public permission). Loading this class then
/// fails with &lt;PROTECT&gt;, and CSP answers a bare text/html 404 itself. That is
/// IRIS's response, not ours; the console recognises it as a failed sign-in (see
/// <tt>apiErrorMessage</tt> in the webapp). We deliberately do not grant that context
/// read access (audit #16). The override stays because it is correct wherever the
/// security context lets it run, and harmless otherwise.
ClassMethod Login(skipRights As %Boolean = 1) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set %response.OutputSessionToken = 0
		if %response.Language = "" set %response.Language = "en"
		set %response.ContentType = ..#CONTENTTYPE
		set:%request.Method'="OPTIONS" %response.Status = ..#HTTP401UNAUTHORIZED

		set tMatchURL = $Extract(%request.URL, $Length(%request.Application), *)
		set tRoute = ..DispatchMap(tMatchURL, %request.Method, .tVerbs, .tArgs)
		set tClass = $ListGet(tRoute, 3, $ClassName())
		set tSC = $ClassMethod(tClass, "ProcessCorsRequest", $ListGet(tRoute, 5, ""), $ListGet(tRoute, 4, ""))
		Quit:$$$ISERR(tSC)

		if %request.Method = "OPTIONS" {
			set tSC = ..OnHandleOptionsRequest(tMatchURL)
		}
	} Catch (e) {
		set %response.Status = ..#HTTP401UNAUTHORIZED
		set tSC = $$$OK
	}
	// Login runs instead of Page, so the headers are not written yet.
	do %response.WriteHTTPHeader()
	if %request.Method '= "OPTIONS" {
		write {"status": "error", "error": "Sign-in failed"}.%ToJSON()
	}
	// As in the base method: an error status here would lose the 401.
	Quit $$$OK
}

/// Route map — endpoints accept both GET and POST.
/// POST with a JSON body is what the webapp uses, and the only practical way to
/// pass a nested payload such as a schema's column list. GET with query
/// parameters is kept because it makes an endpoint testable from a browser or
/// curl without composing a body.
/// `/schemas` is the exception: it uses real verbs, GET/POST/DELETE meaning
/// list/create/delete on the same URL.
XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/ping" Method="GET" Call="Ping" />
  <Route Url="/browse" Method="GET" Call="Browse" />
  <Route Url="/browse" Method="POST" Call="Browse" />
  <Route Url="/read" Method="GET" Call="Read" />
  <Route Url="/read" Method="POST" Call="Read" />
  <Route Url="/test" Method="GET" Call="Test" />
  <Route Url="/test" Method="POST" Call="Test" />
  <Route Url="/deploy" Method="POST" Call="Deploy" />
  <Route Url="/pipelines" Method="GET" Call="Pipelines" />
  <Route Url="/pipelines" Method="POST" Call="Pipelines" />
  <Route Url="/pipelines/toggle" Method="POST" Call="PipelinesToggle" />
  <Route Url="/pipelines/delete" Method="POST" Call="PipelinesDelete" />
  <Route Url="/pipelines/rebind" Method="POST" Call="PipelinesRebind" />
  <Route Url="/schemas" Method="GET" Call="SchemasList" />
  <Route Url="/schemas" Method="POST" Call="SchemasCreate" />
  <Route Url="/schemas/:name/validate" Method="POST" Call="SchemasValidate" />
  <Route Url="/schemas/:name" Method="GET" Call="SchemasGet" />
  <Route Url="/schemas/:name" Method="DELETE" Call="SchemasDelete" />
</Routes>
}

/// Health check endpoint.
ClassMethod Ping() As %Status
{
	set tResult = {}
	set tResult.timestamp = $ZDateTime($Horolog, 3)
	set tResult.version = "1.0"
	Quit ..Respond($$$OK, tResult)
}

/// Browse OPC UA node children.
ClassMethod Browse() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.BrowseService).Browse(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Read a single node value.
ClassMethod Read() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.ReadService).Read(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Test OPC UA server connectivity.
ClassMethod Test() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.ConnectionService).Test(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Deploy a data pipeline (DataSource + Production).
ClassMethod Deploy() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.DeployService).Deploy(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// List all pipelines.
ClassMethod Pipelines() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).List(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Toggle a pipeline on/off.
ClassMethod PipelinesToggle() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).Toggle(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Delete a pipeline.
ClassMethod PipelinesDelete() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).Delete(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Rebind an existing pipeline's device list, without regenerating its schema.
ClassMethod PipelinesRebind() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.PipelineService).Rebind(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Create a device schema, with no production side effects.
ClassMethod SchemasCreate() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.SchemaService).Create(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// List all device schemas.
ClassMethod SchemasList() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		set tSC = ##class(OPCUA.REST.SchemaService).List(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Column detail for one schema.
ClassMethod SchemasGet(pName As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		// The URL path is authoritative for these routes — clear any body
		// className that would otherwise shadow it.
		do tBody.%Set("className", "")
		do tBody.%Set("name", $ZConvert(pName, "I", "URL"))
		set tSC = ##class(OPCUA.REST.SchemaService).Get(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Delete a schema. Refused while a pipeline still references it.
ClassMethod SchemasDelete(pName As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		// The URL path is authoritative for these routes — clear any body
		// className that would otherwise shadow it.
		do tBody.%Set("className", "")
		do tBody.%Set("name", $ZConvert(pName, "I", "URL"))
		set tSC = ##class(OPCUA.REST.SchemaService).Delete(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Dry run a device binding: report which columns resolve per device.
ClassMethod SchemasValidate(pName As %String) As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)
		// The URL path is authoritative for these routes — clear any body
		// className that would otherwise shadow it.
		do tBody.%Set("className", "")
		do tBody.%Set("name", $ZConvert(pName, "I", "URL"))
		set tSC = ##class(OPCUA.REST.SchemaService).Validate(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit ..Respond(tSC, $Get(tResult))
}

/// Build a %DynamicObject from either JSON body or query parameters.
/// Tries body first; if empty, reads query params into a JSON object.
ClassMethod GetRequestParams(Output pBody As %DynamicObject) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		// Try to parse JSON body first
		if %request.Content '= "" {
			// Parse directly from Content (handles both streams and strings)
			set pBody = {}.%FromJSON(%request.Content)
			Quit
		}

		// Fall back to query parameters
		set pBody = {}
		set tParam = ""
		for {
			set tParam = $Order(%request.Data(tParam))
			if tParam = "" Quit
			set tVal = $Get(%request.Data(tParam, 1))
			do pBody.%Set(tParam, tVal)
		}
	} Catch (e) {
		// The exception names a %FromJSON routine offset; the caller only needs
		// to know the body is not JSON.
		set tSC = ##class(OPCUA.REST.Error).BadRequest("Invalid request: the body is not valid JSON")
	}
	Quit tSC
}

/// Send the response for a route: the data envelope on success, otherwise the
/// error envelope with the HTTP status from <class>OPCUA.REST.Error</class>.
///
/// Mapping: bad input 400 (plain <tt>$$$GeneralError</tt>s and
/// <method>OPCUA.REST.Error.BadRequest</method>), unknown schema or pipeline 404,
/// conflict 409 (schema in use, name taken, another production running, edit lock
/// busy, stale save), failed sign-in 401 (<method>Login</method>), anything else
/// 500. 4xx responses carry our own message without the "ERROR #5001: " prefix.
///
/// A 500 never carries internal detail. The full error goes to the application
/// error log (System Operation &gt; System Logs &gt; Application Error Log) under a
/// reference that the response quotes. An unexpected error answers
/// "Internal error. Reference &lt;ref&gt;". A change that was saved but whose
/// follow-up failed (the "... saved, but ..." errors from Rebind, Toggle and
/// Delete) is a 500 built with <method>OPCUA.REST.Error.Make</method>: it shows
/// its own message, so the console can say what was saved, plus the reference.
ClassMethod Respond(pSC As %Status, pData = "") As %Status
{
	Quit:$$$ISOK(pSC) ..SendOK(pData)
	set tHttp = ##class(OPCUA.REST.Error).HttpCode(pSC)
	if tHttp '= 500 {
		Quit ..SendError(tHttp, ##class(OPCUA.REST.Error).Message(pSC))
	}

	set tRef = $ZDateTime($Horolog, 8)_"-"_$Job
	set tWhere = ""
	if $IsObject($Get(%request)) {
		set tWhere = " ("_%request.Method_" "_%request.URL_")"
	}
	set tLog = $$$ERROR($$$GeneralError, "OPC UA REST error, reference "_tRef_tWhere_": "_$System.Status.GetErrorText(pSC))
	do ##class(%Exception.StatusException).CreateFromStatus(tLog).Log()

	if ##class(OPCUA.REST.Error).Carried(pSC) {
		set tMsg = ##class(OPCUA.REST.Error).Message(pSC)_" (Reference "_tRef_")"
	} else {
		set tMsg = "Internal error. Reference "_tRef
	}
	Quit ..SendError(500, tMsg, tRef)
}

/// Send a success response envelope.
ClassMethod SendOK(pData) As %Status
{
	set tResponse = {}
	set tResponse.status = "ok"
	set tResponse.data = pData
	write tResponse.%ToJSON()
	Quit $$$OK
}

/// Send an error response envelope with HTTP status <var>pHttp</var>.
/// <var>pRef</var>, for a 500, is the application error log reference.
ClassMethod SendError(pHttp As %Integer, pMessage As %String, pRef As %String = "") As %Status [ Private ]
{
	set %response.Status = $Case(pHttp,
		400: ..#HTTP400BADREQUEST,
		401: ..#HTTP401UNAUTHORIZED,
		404: ..#HTTP404NOTFOUND,
		409: ..#HTTP409CONFLICT,
		: ..#HTTP500INTERNALSERVERERROR)
	set tResponse = {}
	set tResponse.status = "error"
	set tResponse.error = pMessage
	set:pRef'="" tResponse.ref = pRef
	write tResponse.%ToJSON()
	Quit $$$OK
}

}
