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

/// Allow all logins (authentication handled by CSP web application config).
ClassMethod Login(skipRights As %Boolean = 1) As %Status
{
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
	set tSC = ..SendOK(tResult)
	Quit tSC
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
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
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
}

/// Build a %DynamicObject from either JSON body or query parameters.
/// Tries body first; if empty, reads query params into a JSON object.
ClassMethod GetRequestParams(Output pBody As %DynamicObject) As %Status [ Private ]
{
	#dim tSC As %Status = $$$OK
	Try {
		// Try to parse JSON body first
		set tContent = ""
		if %request.Content '= "" {
			if $IsObject(%request.Content) {
				set tContent = %request.Content.Read()
			} else {
				set tContent = %request.Content
			}
		}
		if tContent '= "" {
			set pBody = {}.%FromJSON(tContent)
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
		set tSC = $$$ERROR($$$GeneralError, "Invalid request: "_e.DisplayString())
	}
	Quit tSC
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

/// Send an error response envelope and set HTTP 400 status.
ClassMethod SendError(pMessage As %String) As %Status
{
	set %response.Status = "400 Bad Request"
	set tResponse = {}
	set tResponse.status = "error"
	set tResponse.error = pMessage
	write tResponse.%ToJSON()
	Quit $$$OK
}

}
