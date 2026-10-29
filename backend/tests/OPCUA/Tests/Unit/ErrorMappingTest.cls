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
/// full error goes to the application error log under the same reference.
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
	do $$$AssertTrue(tLogged '= "", "an application error log entry names reference "_tRef)
	do $$$AssertTrue(tLogged [ "<UNDEFINED>", "the logged entry has the full error: "_tLogged)
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

/// Run Handler.Respond against a fresh %response and capture what it writes.
ClassMethod Capture(pSC As %Status, Output pBody As %String, Output pStatus As %String, pData = "")
{
	new %response
	set %response = ##class(%CSP.Response).%New()
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

/// The text of the newest application error log entry naming <var>pRef</var>.
ClassMethod FindLogged(pRef As %String) As %String
{
	Quit:pRef="" ""
	set tDay = ""
	for tDays=1:1:2 {
		set tDay = $Order(^ERRORS(tDay), -1)
		Quit:tDay=""
		set tN = ""
		for tTries=1:1:50 {
			set tN = $Order(^ERRORS(tDay, tN), -1)
			Quit:tN=""
			set tText = $Get(^ERRORS(tDay, tN, "*STACK", 0, "V", "$ZE"))
			Return:tText[pRef tText
		}
	}
	Quit ""
}

}
