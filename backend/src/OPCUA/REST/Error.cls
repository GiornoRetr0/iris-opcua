Include %occInclude

/// Errors that carry the HTTP status the REST API answers with.
///
/// <method>Make</method> builds an ordinary <tt>$$$GeneralError</tt> whose second
/// parameter is the HTTP code; the message text is unchanged, so service callers
/// and tests see the same text as before. <method>HttpCode</method> reads it back.
/// A plain <tt>$$$GeneralError</tt> is our own validation message, so it is 400.
/// Anything else (an ObjectScript error, a %Dictionary or Ens error) is
/// unexpected, so it is 500 and its text never goes into a response.
Class OPCUA.REST.Error [ Abstract ]
{

/// An error with the HTTP code <var>pHttp</var> and the readable <var>pMessage</var>.
/// <var>pCause</var>, when given, is appended to the status: it is logged with a
/// 500 but never shown.
ClassMethod Make(pHttp As %Integer, pMessage As %String, pCause As %Status = "") As %Status
{
	set tSC = $$$ERROR($$$GeneralError, pMessage, pHttp)
	if (pCause '= "") && $$$ISERR(pCause) {
		set tSC = $$$ADDSC(tSC, pCause)
	}
	Quit tSC
}

/// 400: the request itself is wrong.
ClassMethod BadRequest(pMessage As %String) As %Status
{
	Quit ..Make(400, pMessage)
}

/// 404: the named schema or pipeline does not exist.
ClassMethod NotFound(pMessage As %String) As %Status
{
	Quit ..Make(404, pMessage)
}

/// 403: the signed-in IRIS account lacks a privilege the request needs (for
/// example %Ens_Credentials). Signing in again does not help, so it is not 401.
ClassMethod Forbidden(pMessage As %String) As %Status
{
	Quit ..Make(403, pMessage)
}

/// 409: the request is fine but clashes with current state (in use, name taken,
/// another production running, edit lock busy, stale save).
ClassMethod Conflict(pMessage As %String) As %Status
{
	Quit ..Make(409, pMessage)
}

/// Error codes that say a value the caller supplied failed datatype validation:
/// #5794 (type), #5802 (property) and #7201 (longer than MAXLEN). Their text names
/// the value and the rule, nothing internal, so they are 400 and shown.
Parameter ValidationCodes = ",5794,5802,7201,";

/// The HTTP code for <var>pSC</var>: the code its first error carries, else 400
/// when every error in it is a plain <tt>$$$GeneralError</tt> or a datatype
/// validation failure (<parameter>ValidationCodes</parameter>), else 500.
ClassMethod HttpCode(pSC As %Status) As %Integer
{
	Quit:$$$ISOK(pSC) 200
	do $System.Status.DecomposeStatus(pSC, .tErr)
	Quit:..Carried(pSC) +$Get(tErr(1, "param", 2))
	for i=1:1:+$Get(tErr) {
		if (tErr(i, "code") '= ..GeneralCode()) && '..IsValidationCode(tErr(i, "code")) {
			Return 500
		}
	}
	Quit 400
}

ClassMethod IsValidationCode(pCode As %String) As %Boolean [ CodeMode = expression, Private ]
{
(..#ValidationCodes [ (","_pCode_","))
}

/// Whether the first error of <var>pSC</var> carries an explicit HTTP code, i.e.
/// was built by <method>Make</method>.
ClassMethod Carried(pSC As %Status) As %Boolean
{
	Quit:$$$ISOK(pSC) 0
	do $System.Status.DecomposeStatus(pSC, .tErr)
	set tHttp = +$Get(tErr(1, "param", 2))
	Quit (tErr(1, "code") = ..GeneralCode()) && (tHttp >= 400) && (tHttp <= 599)
}

/// The message a response shows for <var>pSC</var>: for a status built by
/// <method>Make</method>, its own message (a cause appended to it is only logged);
/// otherwise <method>Text</method>.
ClassMethod Message(pSC As %Status) As %String
{
	Quit:'..Carried(pSC) ..Text(pSC)
	do $System.Status.DecomposeStatus(pSC, .tErr)
	Quit $Get(tErr(1, "param", 1))
}

/// The readable text of <var>pSC</var>, without the "ERROR #5001: " prefix.
/// A <tt>$$$GeneralError</tt> contributes its bare message; an ObjectScript error
/// (with its routine offset) only the words "an unexpected internal error"; a
/// datatype validation failure its text without the "ERROR #n: " prefix; any other
/// error its usual one-line text. Several errors are joined with "; ".
ClassMethod Text(pSC As %Status) As %String
{
	Quit:$$$ISOK(pSC) ""
	do $System.Status.DecomposeStatus(pSC, .tErr)
	set tText = ""
	for i=1:1:+$Get(tErr) {
		set tCode = tErr(i, "code")
		if tCode = ..GeneralCode() {
			set tPart = $Get(tErr(i, "param", 1))
		} elseif tCode = ..ObjectScriptCode() {
			set tPart = "an unexpected internal error"
		} elseif ..IsValidationCode(tCode) {
			// "ERROR #5794: Datatype validation failed ..." without the prefix.
			set tPart = $Piece($System.Status.GetOneErrorText(pSC, i), ": ", 2, *)
		} else {
			set tPart = $System.Status.GetOneErrorText(pSC, i)
		}
		set tText = tText_$Select(tText="":"", 1:"; ")_tPart
	}
	Quit tText
}

/// Numeric code of <tt>$$$GeneralError</tt> as <tt>DecomposeStatus</tt> reports it.
ClassMethod GeneralCode() As %String [ CodeMode = expression, Private ]
{
$System.Status.GetErrorCodes($$$ERROR($$$GeneralError, ""))
}

/// Numeric code of <tt>$$$ObjectScriptError</tt> (what a caught &lt;UNDEFINED&gt; becomes).
ClassMethod ObjectScriptCode() As %String [ CodeMode = expression, Private ]
{
$System.Status.GetErrorCodes($$$ERROR($$$ObjectScriptError, ""))
}

}
