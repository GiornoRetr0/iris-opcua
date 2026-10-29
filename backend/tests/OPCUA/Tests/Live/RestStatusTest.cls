Include (%occInclude, Ensemble)

/// Live tests for the REST API's HTTP statuses (audit #16 and "every error returns
/// HTTP 400"). Calls the real web application over HTTP, like RestBodyTest.
Class OPCUA.Tests.Live.RestStatusTest Extends %UnitTest.TestCase
{

Parameter SchemaClass = "OPCUA.Tests.TmpStatusSchema";

Parameter PipelineName = "TmpRestStatus";

Method OnBeforeAllTests() As %Status
{
	do ..DoCleanup()
	set tSC = ..BuildSchema()
	Quit:$$$ISERR(tSC) tSC
	Quit ##class(OPCUA.REST.DeployService).Deploy({
		"dataSourceName": (..#PipelineName),
		"schemaClass": (..#SchemaClass),
		"mode": "polling",
		"url": (..URL()),
		"deviceNodePaths": "i=85|Objects",
		"callInterval": 2
	}, .tResult)
}

Method OnAfterAllTests() As %Status
{
	kill ^IRIS.Temp.OPCUATests("status")
	do ..DoCleanup()
	Quit $$$OK
}

Method TestSchemaNotFound()
{
	set tSC = ..Call("GET", "/schemas/NoSuchSchemaXyz", "", .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 404, "unknown schema is 404")
	do $$$AssertEquals(tJSON.status, "error", "error envelope")
	do $$$AssertTrue(tJSON.error [ "does not exist", "message: "_tJSON.error)
	do $$$AssertTrue(tJSON.error '[ "ERROR #", "no ERROR # prefix: "_tJSON.error)
}

Method TestSchemaInUse()
{
	set tSC = ..Call("DELETE", "/schemas/"_..#SchemaClass, "", .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 409, "deleting a schema in use is 409")
	do $$$AssertTrue(tJSON.error [ "still used by", "message: "_tJSON.error)
	do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass), "schema kept")
}

Method TestRebindLockBusy()
{
	kill ^IRIS.Temp.OPCUATests("status")
	set ^IRIS.Temp.OPCUATests("status", "hold") = 1
	job ##class(OPCUA.Tests.Live.RestStatusTest).HoldLock()::5
	do $$$AssertTrue($Test, "lock-holding job started")
	for i=1:1:50 { quit:$Get(^IRIS.Temp.OPCUATests("status", "held"))  hang 0.1 }
	do $$$AssertTrue($Get(^IRIS.Temp.OPCUATests("status", "held")), "job holds the edit lock")

	set tSC = ..Call("POST", "/pipelines/rebind", {"name": (..#PipelineName), "devices": "i=85|Objects"}, .tHttp, .tJSON)
	kill ^IRIS.Temp.OPCUATests("status", "hold")
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 409, "rebind while the edit lock is held is 409")
	do $$$AssertTrue(tJSON.error [ "in progress", "message: "_tJSON.error)
}

Method TestPipelineNotFound()
{
	set tSC = ..Call("POST", "/pipelines/toggle", {"name": "NoSuchPipelineXyz"}, .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 404, "unknown pipeline is 404")
}

Method TestBadRequest()
{
	set tSC = ..Call("POST", "/pipelines/rebind", {"name": ""}, .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 400, "missing name is 400")
	do $$$AssertEquals(tJSON.error, "Missing pipeline name", "bare message")
}

/// A schema name that is not a valid class name is the caller's mistake: 400 with
/// a message saying so, not an opaque 500 from %Dictionary.
Method TestBadSchemaName()
{
	set tBody = {"name": "Bad-Name Rvw", "columns": [{"displayName": "SA1", "inferredType": "%Integer", "relativePath": ["SA1"], "nodeNs": 1}]}
	set tSC = ..Call("POST", "/schemas", tBody, .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 400, "bad schema name is 400")
	do $$$AssertTrue(tJSON.error [ "not a valid schema name", "message: "_tJSON.error)
	do $$$AssertTrue(tJSON.error [ "Bad-Name Rvw", "names the value: "_tJSON.error)
}

/// A pipeline name Ens.Config.Item would refuse is a 400 with a readable message.
Method TestBadPipelineName()
{
	for tName = "Bad|Name", "Bad;Name", $Translate($Justify("", 129), " ", "p") {
		set tSC = ..Call("POST", "/deploy", {"dataSourceName": (tName), "schemaClass": (..#SchemaClass), "url": (..URL()), "devices": "i=85|Objects"}, .tHttp, .tJSON)
		do $$$AssertStatusOK(tSC, "request sent")
		do $$$AssertEquals(tHttp, 400, "pipeline name '"_$Extract(tName, 1, 20)_"' is 400")
		do $$$AssertTrue(tJSON.error [ "Pipeline name", "message: "_tJSON.error)
	}
}

/// /test reports a failed connect in a 200 body; its text has no "ERROR #" prefix.
Method TestConnectErrorText()
{
	set tSC = ..Call("POST", "/test", {"url": "opc.tcp://nosuchhost.invalid:4840"}, .tHttp, .tJSON)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertEquals(tHttp, 200, "a failed connect is a result, not an error")
	do $$$AssertEquals(tJSON.data.connected, 0, "not connected")
	do $$$AssertTrue(tJSON.data.error '= "", "says why: "_tJSON.data.error)
	do $$$AssertTrue(tJSON.data.error '[ "ERROR #", "no ERROR # prefix: "_tJSON.data.error)
}

/// Audit #16, as decided: a wrong password gets no Basic challenge (so no browser
/// pop-up over the console) and no envelope. Under the default security setup the
/// status is IRIS's own 404: CSP runs the dispatch class's Login as CSPSystem, which
/// cannot read the code database, and answers a bare text/html 404 itself. Where
/// that context can read it, our Login answers 401 (still with no challenge). The
/// console treats both, without our envelope, as "Sign-in failed".
Method TestWrongPasswordIsIRIS404OrOur401()
{
	set tSC = ..Call("GET", "/schemas", "", .tHttp, .tJSON, "SuperUser", "not-the-password", .tRequest)
	do $$$AssertStatusOK(tSC, "request sent")
	do $$$AssertTrue((tHttp = 401) || (tHttp = 404), "wrong password is 401 or IRIS's 404: "_tHttp)
	set tChallenge = tRequest.HttpResponse.GetHeader("WWW-Authenticate")
	do $$$AssertTrue($ZConvert(tChallenge, "U") '[ "BASIC", "no Basic challenge (no browser pop-up): '"_tChallenge_"'")
	if tHttp = 404 {
		do $$$AssertTrue(tJSON.status '= "error", "IRIS's 404 is not our envelope, so the console can tell it from a real 404")
	} else {
		do $$$AssertEquals(tJSON.error, "Sign-in failed", "our 401 envelope")
	}
	// A good sign-in right after resets the account's failed-login count.
	set tSC = ..Call("GET", "/ping", "", .tHttp, .tJSON)
	do $$$AssertEquals(tHttp, 200, "the right password still works")
}

/// One HTTP call. <var>pJSON</var> is the parsed body, or {} when it is not JSON.
ClassMethod Call(pMethod As %String, pPath As %String, pBody, Output pHttp As %Integer, Output pJSON As %DynamicObject, pUser As %String = "SuperUser", pPassword As %String = "SYS", Output pRequest As %Net.HttpRequest) As %Status
{
	set pHttp = "", pJSON = {}
	set pRequest = ##class(%Net.HttpRequest).%New()
	set pRequest.Server = "localhost"
	set pRequest.Port = 52773
	set pRequest.Username = pUser
	set pRequest.Password = pPassword
	set pRequest.ContentType = "application/json"
	do:$IsObject(pBody) pBody.%ToJSON(pRequest.EntityBody)
	set tSC = pRequest.Send(pMethod, "/csp/opcua/api"_pPath)
	Quit:$$$ISERR(tSC) tSC
	set pHttp = pRequest.HttpResponse.StatusCode
	set tText = ""
	if $IsObject(pRequest.HttpResponse.Data) {
		while 'pRequest.HttpResponse.Data.AtEnd { set tText = tText_pRequest.HttpResponse.Data.Read() }
	} else {
		set tText = pRequest.HttpResponse.Data
	}
	try { set pJSON = {}.%FromJSON(tText) } catch e { set pJSON = {"raw": (tText)} }
	Quit $$$OK
}

/// JOB entry: hold the edit lock until the test kills the flag.
ClassMethod HoldLock()
{
	lock +^OPCUA.ProductionEdit
	set ^IRIS.Temp.OPCUATests("status", "held") = 1
	for i=1:1:600 { quit:'$Get(^IRIS.Temp.OPCUATests("status", "hold"))  hang 0.1 }
	lock -^OPCUA.ProductionEdit
}

ClassMethod URL() As %String
{
	Quit $Get(^||OPCUA.Tests("url"), "opc.tcp://plc")
}

ClassMethod DoCleanup()
{
	set tName = ..#PipelineName
	try {
		do ##class(OPCUA.REST.PipelineService).Delete({"name": (tName)}, .tResult)
	} catch e {}
	&sql(DELETE FROM Ens_Config.Item WHERE Name = :tName)
	try {
		do:##class(%Dictionary.CompiledClass).%ExistsId(..#SchemaClass) $classmethod(..#SchemaClass, "%KillExtent")
	} catch e {}
	do:##class(%Dictionary.ClassDefinition).%ExistsId(..#SchemaClass) $System.OBJ.Delete(..#SchemaClass, "-d")
	kill ^OPCUA.DataSource(..#SchemaClass)
}

/// A one-column schema that the plc's Objects folder resolves (SA1).
ClassMethod BuildSchema() As %Status
{
	set tDef = ##class(%Dictionary.ClassDefinition).%New(..#SchemaClass)
	set tDef.Description = "Throwaway schema for RestStatusTest"
	set tDef.Super = "%Persistent,OPCUA.DataSource.DeviceSchema"

	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUADATASOURCE", tParam.Default = "TmpRestStatus"
	do tDef.Parameters.Insert(tParam)
	set tParam = ##class(%Dictionary.ParameterDefinition).%New()
	set tParam.Name = "OPCUDEFAULTANAMESPACE", tParam.Default = 1
	do tDef.Parameters.Insert(tParam)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "NodePath", tProp.Type = "%String"
	do tProp.Parameters.SetAt(500, "MAXLEN")
	do tDef.Properties.Insert(tProp)

	set tProp = ##class(%Dictionary.PropertyDefinition).%New()
	set tProp.Name = "SA1", tProp.Type = "OPCUA.Types.IntegerDataValue"
	do tProp.Parameters.SetAt("SA1", "OPCUANODENAME")
	do tDef.Properties.Insert(tProp)

	set tSC = tDef.%Save()
	Quit:$$$ISERR(tSC) tSC
	Quit $System.OBJ.Compile(..#SchemaClass, "ck-d")
}

}
