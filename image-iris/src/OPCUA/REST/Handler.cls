Include %occInclude

/// REST dispatch handler for OPC UA adapter endpoints.
/// Routes requests to service classes and formats consistent JSON responses.
Class OPCUA.REST.Handler Extends %CSP.REST
{

/// Enable CORS for Chrome extension access.
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
/// GET with query parameters is convenient for simple testing;
/// POST with JSON body is used by the Chrome extension.
XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/ping" Method="GET" Call="Ping" />
  <Route Url="/browse" Method="GET" Call="Browse" />
  <Route Url="/browse" Method="POST" Call="Browse" />
  <Route Url="/read" Method="GET" Call="Read" />
  <Route Url="/read" Method="POST" Call="Read" />
  <Route Url="/read-bulk" Method="GET" Call="ReadBulk" />
  <Route Url="/read-bulk" Method="POST" Call="ReadBulk" />
  <Route Url="/generate" Method="GET" Call="Generate" />
  <Route Url="/generate" Method="POST" Call="Generate" />
  <Route Url="/test" Method="GET" Call="Test" />
  <Route Url="/test" Method="POST" Call="Test" />
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

/// Bulk-read multiple node values in a single connection.
ClassMethod ReadBulk() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.BulkReadService).ReadBulk(tBody, .tResult)
		Quit:$$$ISERR(tSC)
	} Catch (e) {
		set tSC = e.AsStatus()
	}
	if $$$ISERR(tSC) {
		Quit ..SendError($System.Status.GetErrorText(tSC))
	}
	Quit ..SendOK(tResult)
}

/// Generate a DataSource class.
ClassMethod Generate() As %Status
{
	#dim tSC As %Status = $$$OK
	Try {
		set tSC = ..GetRequestParams(.tBody)
		Quit:$$$ISERR(tSC)

		set tSC = ##class(OPCUA.REST.GenerateService).Generate(tBody, .tResult)
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
