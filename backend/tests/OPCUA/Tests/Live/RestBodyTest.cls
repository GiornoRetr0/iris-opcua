Include %occInclude

/// Live tests for REST API request body handling
Class OPCUA.Tests.Live.RestBodyTest Extends %UnitTest.TestCase
{

/// Test that large POST bodies (>1MB) are handled correctly
Method TestLargeBody()
{
    // Build a large JSON payload (~1.5 MB) with many comment lines in the devices field
    Set tDevices = ""
    For i=1:1:50000 {
        Set tDevices = tDevices _ "# Comment line number " _ i _ " with some padding text to increase size" _ $Char(10)
    }
    Set tDevices = tDevices _ "ns=2;s=Device1" _ $Char(10)

    // Build the JSON request for the test endpoint
    Set tRequest = {}
    Set tRequest.url = "opc.tcp://plc:4840"
    Set tRequest.devices = tDevices

    // POST to /test via %Net.HttpRequest (simpler endpoint that just needs URL)
    Set tHttpRequest = ##class(%Net.HttpRequest).%New()
    Set tHttpRequest.Server = "localhost"
    Set tHttpRequest.Port = 52773
    Set tHttpRequest.Username = "SuperUser"
    Set tHttpRequest.Password = "SYS"
    Set tHttpRequest.ContentType = "application/json"

    // Write the JSON to the entity body stream
    Do tRequest.%ToJSON(tHttpRequest.EntityBody)

    // POST the request
    Set tSC = tHttpRequest.Post("/csp/opcua/api/test")
    Do $$$AssertStatusOK(tSC, "HTTP POST should succeed")

    // Read the response
    If $$$ISOK(tSC) {
        Set tResponseBody = ""
        While 'tHttpRequest.HttpResponse.Data.AtEnd {
            Set tResponseBody = tResponseBody _ tHttpRequest.HttpResponse.Data.Read()
        }

        // Parse the response as JSON
        Set tResponse = {}.%FromJSON(tResponseBody)

        // The response should not be an error about "Invalid request"
        If tResponse.status = "error" {
            Do $$$LogMessage("Error response: " _ tResponse.error)
            Do $$$AssertTrue(tResponse.error '[ "Invalid request", "Should not get 'Invalid request' error with large body")
        } Else {
            // Success case - response was parsed
            Do $$$AssertEquals(tResponse.status, "ok", "Response status should be 'ok'")
        }
    }
}

}
