Include %occInclude

/// Offline tests for the REST error-to-HTTP-status mapping (OPCUA.REST.Error) and
/// for what <method>OPCUA.REST.Handler.Respond</method> writes: real statuses, our
/// own messages without the "ERROR #5001" prefix, and no internal detail for a 500.
Class OPCUA.Tests.Unit.ErrorMappingTest Extends %UnitTest.TestCase
{

Method TestHttpCode()
{
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(##class(OPCUA.REST.Error).Make(409, "x")), 409, "carried code")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode($$$ERROR($$$GeneralError, "x")), 400, "plain GeneralError is 400")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(..UndefinedStatus()), 500, "caught <UNDEFINED> is 500")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(##class(OPCUA.REST.Error).NotFound("x")), 404, "NotFound")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(##class(OPCUA.REST.Error).Conflict("x")), 409, "Conflict")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(##class(OPCUA.REST.Error).BadRequest("x")), 400, "BadRequest")
	set tMixed = $$$ADDSC($$$ERROR($$$GeneralError, "x"), ..UndefinedStatus())
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tMixed), 500, "a plain GeneralError with an internal error behind it is 500")
	do $$$AssertEquals($System.Status.GetOneStatusText(##class(OPCUA.REST.Error).Make(409, "x")), "x", "the carried code does not change the text")
}

/// A datatype validation failure is the caller's input, so 400 with its text.
Method TestValidationIs400()
{
	set tSC = ##class(%Dictionary.Classname).IsValid("OPCUA.DS.Bad-Name Rvw")
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "#5794 is 400")
	set tText = ##class(OPCUA.REST.Error).Message(tSC)
	do $$$AssertTrue(tText [ "Bad-Name Rvw", "the text names the value: "_tText)
	do $$$AssertTrue(tText '[ "ERROR #", "no ERROR # prefix: "_tText)
	set tSC = $$$ADDSC($System.Status.Error(5802, "Ens.Config.Item:Name", "x"), $System.Status.Error(7201, "x", 128))
	do $$$AssertEquals(##class(OPCUA.REST.Error).HttpCode(tSC), 400, "#5802 + #7201 is 400")
}

/// Text strips the "ERROR #5001" prefix and never repeats an ObjectScript error.
Method TestText()
{
	do $$$AssertEquals(##class(OPCUA.REST.Error).Text($$$ERROR($$$GeneralError, "plain words")), "plain words", "bare message")
	set tText = ##class(OPCUA.REST.Error).Text(..UndefinedStatus())
	do $$$AssertTrue(tText '[ "<UNDEFINED>", "no <UNDEFINED> in the text: "_tText)
}

/// A 409 sends our own message, bare, with HTTP 409.
Method TestRespondConflict()
{
	do ..Capture(##class(OPCUA.REST.Error).Conflict("Schema 'X' is still used by: P"), .tBody, .tStatus)
	do $$$AssertEquals(+tStatus, 409, "HTTP status: "_tStatus)
	set tJSON = {}.%FromJSON(tBody)
	do $$$AssertEquals(tJSON.status, "error", "envelope status")
	do $$$AssertEquals(tJSON.error, "Schema 'X' is still used by: P", "bare message")
}

/// A plain GeneralError is a 400 with the bare message.
Method TestRespondBadRequest()
{
	do ..Capture($$$ERROR($$$GeneralError, "Missing pipeline name"), .tBody, .tStatus)
	do $$$AssertEquals(+tStatus, 400, "HTTP status: "_tStatus)
	do $$$AssertEquals({}.%FromJSON(tBody).error, "Missing pipeline name", "bare message, no ERROR #5001 prefix")
}

/// OK sends the data envelope with the default 200.
Method TestRespondOK()
{
	do ..Capture($$$OK, .tBody, .tStatus, {"a": 1})
	do $$$AssertEquals(+tStatus, 200, "HTTP status: "_tStatus)
	set tJSON = {}.%FromJSON(tBody)
	do $$$AssertEquals(tJSON.status, "ok", "envelope status")
	do $$$AssertEquals(tJSON.data.a, 1, "data passed through")
}

/// An unexpected error is a 500 whose body has a reference and no detail, and the
/// full error goes to the Interoperability event log under the same reference.
Method TestRespondInternalError()
{
	do ..Capture(..UndefinedStatus(), .tBody, .tStatus)
	do $$$AssertEquals(+tStatus, 500, "HTTP status: "_tStatus)
	do $$$AssertTrue(tBody [ "Reference", "body has a reference: "_tBody)
	do $$$AssertTrue(tBody '[ "<UNDEFINED>", "body hides the <UNDEFINED>: "_tBody)
	do $$$AssertTrue(tBody '[ "zUndefinedStatus", "body hides the routine offset: "_tBody)
	set tJSON = {}.%FromJSON(tBody)
	set tRef = tJSON.ref
	do $$$AssertTrue(tRef '= "", "ref field: "_tRef)
	do $$$AssertEquals(tJSON.error, "Internal error. Reference "_tRef, "generic message")

	set tLogged = ..FindLogged(tRef)
	do $$$AssertTrue(tLogged '= "", "an event log entry names reference "_tRef)
	do $$$AssertTrue(tLogged [ "<UNDEFINED>", "the logged entry has the full error: "_tLogged)
	do ..ForgetLogged(tRef)
}

/// A 500 must not copy request secrets into any log. LOG^%ETN (the application
/// error log) saves every stack frame's locals, the request body among them, so
/// it is not used; the event log entry holds only the error text, with any
/// password from the request body masked.
Method TestRespondLogsNoPassword()
{
	set tPassword = "s3cretErrMapTest"
	set tBefore = ..LastErrorsEntry()
	set tRequest = ##class(%CSP.Request).%New()
	set tRequest.Content = ##class(%Stream.TmpCharacter).%New()
	do tRequest.Content.Write({"url": "opc.tcp://plc", "password": (tPassword), "server": {"apiPassword": (tPassword_"2")}}.%ToJSON())
	// An internal error whose text happens to contain the secret.
	set tSC = $System.Status.Error(5002, "<UNDEFINED>x *"_tPassword_" "_tPassword_"2")

	do ..Capture(tSC, .tBody, .tStatus, , tRequest)
	do $$$AssertEquals(+tStatus, 500, "HTTP status: "_tStatus)
	set tRef = {}.%FromJSON(tBody).ref
	do $$$AssertTrue(tBody '[ tPassword, "the response has no password")
	set tLogged = ..FindLogged(tRef)
	do $$$AssertTrue(tLogged '= "", "logged under reference "_tRef)
	do $$$AssertTrue(tLogged '[ tPassword, "the event log entry has no password: "_tLogged)
	do $$$AssertTrue(tLogged [ "<UNDEFINED>", "but it has the error: "_tLogged)
	set tLeak = ..ErrorsContaining(tBefore, tPassword)
	do $$$AssertEquals(tLeak, "", "no ^ERRORS entry created during the test holds the password: "_tLeak)
	do ..ForgetLogged(tRef)
}

/// A 500 built with our own message (a saved change whose follow-up failed) shows
/// that message, plus the reference, and logs the cause.
Method TestRespondCarried500()
{
	set tSC = ##class(OPCUA.REST.Error).Make(500, "Device list saved, but the running pipeline could not be restarted: x", ..UndefinedStatus())
	do ..Capture(tSC, .tBody, .tStatus)
	do $$$AssertEquals(+tStatus, 500, "HTTP status: "_tStatus)
	set tJSON = {}.%FromJSON(tBody)
	do $$$AssertTrue(tJSON.error [ "Device list saved, but", "our message is shown: "_tJSON.error)
	do $$$AssertTrue(tJSON.error [ tJSON.ref, "and the reference")
	do $$$AssertTrue(tBody '[ "<UNDEFINED>", "the cause is not shown")
	do $$$AssertTrue(..FindLogged(tJSON.ref) [ "<UNDEFINED>", "the cause is logged")
	do ..ForgetLogged(tJSON.ref)
}

/// The status a caught &lt;UNDEFINED&gt; becomes.
ClassMethod UndefinedStatus() As %Status
{
	try {
		kill tNoSuch
		set tX = tNoSuch
		set tSC = $$$OK
	} catch e {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Run Handler.Respond against a fresh %response, and <var>pRequest</var> as
/// %request (none by default), and capture what it writes.
ClassMethod Capture(pSC As %Status, Output pBody As %String, Output pStatus As %String, pData = "", pRequest = "")
{
	new %response, %request
	set %response = ##class(%CSP.Response).%New()
	set:$IsObject(pRequest) %request = pRequest
	set tFile = ##class(%File).TempFilename("json")
	set tIO = $IO
	open tFile:"WNS":5
	if '$Test {
		set pBody = "", pStatus = "cannot open "_tFile
		Quit
	}
	try {
		use tFile
		do ##class(OPCUA.REST.Handler).Respond(pSC, pData)
	} catch e {
		use tIO
		set pStatus = "Respond threw "_e.DisplayString()
	}
	use tIO
	close tFile
	set pStatus = $Get(pStatus, %response.Status)
	set tStream = ##class(%Stream.FileCharacter).%New()
	do tStream.LinkToFile(tFile)
	set pBody = tStream.Read(1000000)
	kill tStream
	do ##class(%File).Delete(tFile)
}

/// The text of the event log entry naming <var>pRef</var>.
ClassMethod FindLogged(pRef As %String) As %String
{
	Quit:pRef="" ""
	set tLike = "%"_pRef_"%", tText = ""
	&sql(SELECT TOP 1 Text INTO :tText FROM Ens_Util.Log WHERE Text LIKE :tLike ORDER BY ID DESC)
	Quit $Select(SQLCODE=0:tText, 1:"")
}

/// Delete the event log entries this test wrote under <var>pRef</var>.
ClassMethod ForgetLogged(pRef As %String)
{
	Quit:pRef=""
	set tLike = "%"_pRef_"%"
	&sql(DELETE FROM Ens_Util.Log WHERE Text LIKE :tLike)
}

/// $LB(day, entry) of the newest application error log entry, or "".
ClassMethod LastErrorsEntry() As %List
{
	set tDay = $Order(^ERRORS(""), -1)
	Quit:tDay="" ""
	Quit $ListBuild(tDay, $Order(^ERRORS(tDay, ""), -1))
}

/// The first ^ERRORS node created after <var>pBefore</var> whose subscripts or
/// value contain <var>pText</var>, or "".
ClassMethod ErrorsContaining(pBefore As %List, pText As %String) As %String
{
	set tDay = $ListGet(pBefore, 1), tEntry = $ListGet(pBefore, 2)
	set tDay = $Select(tDay="":$Order(^ERRORS("")), 1:tDay)
	while tDay '= "" {
		set tN = $Select(tDay=$ListGet(pBefore, 1):tEntry, 1:"")
		for {
			set tN = $Order(^ERRORS(tDay, tN))
			Quit:tN=""
			set tRoot = $Name(^ERRORS(tDay, tN)), tNode = tRoot
			for {
				set tNode = $Query(@tNode)
				Quit:tNode=""
				Quit:($QSubscript(tNode, 1)'=tDay)||($QSubscript(tNode, 2)'=tN)
				if (tNode [ pText) || ($Get(@tNode) [ pText) {
					Return tNode
				}
			}
		}
		set tDay = $Order(^ERRORS(tDay))
	}
	Quit ""
}

}
