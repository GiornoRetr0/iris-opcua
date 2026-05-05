Include %occInclude

/// Proxy + parser for the IRIS built-in /api/monitor/metrics endpoint.
/// Fetches the Prometheus exposition text over localhost, parses it into JSON,
/// and returns it wrapped in the adapter's standard {status,data} envelope.
Class OPCUA.REST.MetricsService
{

/// Hostname for the internal HTTP call. localhost works inside the IRIS container.
Parameter MonitorHost = "localhost";

/// Internal web-server port (docker-compose maps 52783 → 52773).
Parameter MonitorPort = 52773;

Parameter MonitorPath = "/api/monitor/metrics";

/// Fetch, parse, and return the metrics snapshot.
ClassMethod Get(pBody As %DynamicObject, Output pResult As %DynamicObject) As %Status
{
	#dim tSC As %Status = $$$OK
	set pResult = {}
	Try {
		set tReq = ##class(%Net.HttpRequest).%New()
		set tReq.Server = ..#MonitorHost
		set tReq.Port = ..#MonitorPort
		set tReq.Timeout = 10
		set tReq.Username = "SuperUser"
		set tReq.Password = "SYS"

		set tSC = tReq.Get(..#MonitorPath)
		$$$ThrowOnError(tSC)

		if (tReq.HttpResponse.StatusCode '= 200) {
			set tSC = $$$ERROR($$$GeneralError, "Monitor endpoint returned HTTP "_tReq.HttpResponse.StatusCode)
			Quit
		}

		set tBody = ..ReadResponseBody(tReq.HttpResponse)

		set tMetrics = ..ParseExposition(tBody)

		set pResult.scrapedAt = $ZDateTime($Horolog, 3)
		set pResult.metrics = tMetrics

	} Catch (e) {
		set tSC = e.AsStatus()
	}
	Quit tSC
}

/// Read full response body regardless of whether it came back as a stream or a string.
ClassMethod ReadResponseBody(pResponse As %Net.HttpResponse) As %String [ Private ]
{
	set tText = ""
	set tData = pResponse.Data
	if '$IsObject(tData) {
		Quit tData
	}
	do tData.Rewind()
	while 'tData.AtEnd {
		set tText = tText _ tData.Read(32000)
	}
	Quit tText
}

/// Parse Prometheus exposition text into a %DynamicArray of metric objects.
/// Each item: { name, labels:{…}, value, help?, type?, unit? }.
ClassMethod ParseExposition(pText As %String) As %DynamicArray [ Private ]
{
	set tResult = []
	kill tHelp, tType, tUnit

	set tLineCount = $Length(pText, $Char(10))
	for i=1:1:tLineCount {
		set tLine = $Piece(pText, $Char(10), i)
		// Strip trailing CR if present
		if $Length(tLine) && ($Ascii($Extract(tLine, *)) = 13) {
			set tLine = $Extract(tLine, 1, *-1)
		}
		if tLine = "" continue

		if $Extract(tLine, 1) = "#" {
			// Comment line. Formats: "# HELP <name> <text>", "# TYPE <name> <type>", "# UNIT <name> <unit>"
			set tRest = $ZStrip($Extract(tLine, 2, *), "<W")
			set tKind = $Piece(tRest, " ", 1)
			set tName = $Piece(tRest, " ", 2)
			set tVal = $Piece(tRest, " ", 3, $Length(tRest, " "))
			if tName = "" continue
			if tKind = "HELP" {
				set tHelp(tName) = tVal
			} elseif tKind = "TYPE" {
				set tType(tName) = tVal
			} elseif tKind = "UNIT" {
				set tUnit(tName) = tVal
			}
			continue
		}

		// Data line: name{labels} value   OR   name value
		set tBraceStart = $Find(tLine, "{")
		if tBraceStart {
			set tName = $Extract(tLine, 1, tBraceStart - 2)
			set tBraceEnd = $Find(tLine, "}", tBraceStart)
			if 'tBraceEnd continue
			set tLabelsRaw = $Extract(tLine, tBraceStart, tBraceEnd - 2)
			set tAfter = $ZStrip($Extract(tLine, tBraceEnd, *), "<W")
			set tValueStr = $Piece(tAfter, " ", 1)
		} else {
			set tName = $Piece(tLine, " ", 1)
			set tValueStr = $Piece(tLine, " ", 2)
			set tLabelsRaw = ""
		}

		if tName = "" continue
		if tValueStr = "" continue

		set tMetric = {}
		set tMetric.name = tName
		set tMetric.labels = ..ParseLabels(tLabelsRaw)
		set tMetric.value = ..ParseNumber(tValueStr)
		if $Data(tHelp(tName)) set tMetric.help = tHelp(tName)
		if $Data(tType(tName)) set tMetric.type = tType(tName)
		if $Data(tUnit(tName)) set tMetric.unit = tUnit(tName)

		do tResult.%Push(tMetric)
	}

	Quit tResult
}

/// Parse the inside of {…}: key="value",key2="value2" (values may contain escaped quotes).
ClassMethod ParseLabels(pRaw As %String) As %DynamicObject [ Private ]
{
	set tObj = {}
	if pRaw = "" Quit tObj

	set tPos = 1
	set tLen = $Length(pRaw)
	while tPos <= tLen {
		// Find key (up to =)
		set tEq = $Find(pRaw, "=", tPos)
		if 'tEq Quit
		set tKey = $ZStrip($Extract(pRaw, tPos, tEq - 2), "<>W")
		set tPos = tEq

		// Expect opening quote
		if $Extract(pRaw, tPos) '= """" {
			// Unquoted — consume until comma or end
			set tComma = $Find(pRaw, ",", tPos)
			if tComma {
				set tVal = $Extract(pRaw, tPos, tComma - 2)
				set tPos = tComma
			} else {
				set tVal = $Extract(pRaw, tPos, tLen)
				set tPos = tLen + 1
			}
		} else {
			// Quoted — skip opening quote, consume with backslash escapes until closing quote
			set tPos = tPos + 1
			set tVal = ""
			while tPos <= tLen {
				set tCh = $Extract(pRaw, tPos)
				if tCh = "\" {
					set tNext = $Extract(pRaw, tPos + 1)
					if tNext = "n" { set tVal = tVal _ $Char(10) }
					elseif tNext = "\" { set tVal = tVal _ "\" }
					elseif tNext = """" { set tVal = tVal _ """" }
					else { set tVal = tVal _ tNext }
					set tPos = tPos + 2
					continue
				}
				if tCh = """" {
					set tPos = tPos + 1
					Quit
				}
				set tVal = tVal _ tCh
				set tPos = tPos + 1
			}
			// Skip trailing whitespace + comma
			while (tPos <= tLen) && ($Extract(pRaw, tPos) = " ") {
				set tPos = tPos + 1
			}
			if (tPos <= tLen) && ($Extract(pRaw, tPos) = ",") {
				set tPos = tPos + 1
			}
			while (tPos <= tLen) && ($Extract(pRaw, tPos) = " ") {
				set tPos = tPos + 1
			}
		}

		if tKey '= "" do tObj.%Set(tKey, tVal)
	}

	Quit tObj
}

/// Convert a string to a number for JSON output.
/// Handles "NaN", "+Inf", "-Inf" by emitting null.
ClassMethod ParseNumber(pStr As %String) As %Numeric [ Private ]
{
	if pStr = "" Quit ""
	set tLower = $ZConvert(pStr, "L")
	if (tLower = "nan") || (tLower = "+inf") || (tLower = "-inf") || (tLower = "inf") Quit ""
	Quit +pStr
}

}
