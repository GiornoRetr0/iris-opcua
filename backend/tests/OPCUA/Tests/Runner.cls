/// Test runner for OPCUA test suites
Class OPCUA.Tests.Runner Extends %RegisteredObject
{

/// Run all offline tests (no server, no native library required)
/// Returns 1 if all tests pass, 0 if any fail
ClassMethod Offline() As %Boolean
{
    Write !,"=== Running OPCUA.Tests.Unit ===",!
    Return ..RunSuite("OPCUA.Tests.Unit", "")
}

/// Run all live tests (requires OPC UA server)
/// @param pURL The OPC UA server URL (default: opc.tcp://plc)
/// Returns 1 if all tests pass, 0 if any fail
ClassMethod Live(pURL As %String = "opc.tcp://plc") As %Boolean
{
    Write !,"=== Running OPCUA.Tests.Live === (server: ", pURL, ")",!
    // Store the server URL in a process-private global for tests to access
    Set ^||OPCUA.Tests("url") = pURL
    Return ..RunSuite("OPCUA.Tests.Live", pURL)
}

/// Run a test suite package and collect results
/// @param pPackage The package path (e.g. "OPCUA.Tests.Unit")
/// @param pURL Optional URL to display
/// Returns 1 if all pass, 0 if any fail
ClassMethod RunSuite(pPackage As %String, pURL As %String = "") As %Boolean [ Internal ]
{
    // Ensure ^UnitTestRoot is set
    Set ^UnitTestRoot = "/tmp"

    // Run the test suite
    Set mgr = ##class(%UnitTest.Manager).%New()
    Do mgr.RunTest(pPackage, "/noload/nodelete")

    // Get the most recent test run index
    Set logIndex = $Order(^UnitTest.Result(""),-1)
    If logIndex = "" {
        Write "ERROR: No test results found",!
        Return 0
    }

    // The result structure is: ^UnitTest.Result(logIndex, suitePath, className, testMethod)
    // Convert package to suite path (dots to backslashes)
    Set suitePath = $Replace(pPackage, ".", "\")

    // Count passed/failed by walking the result tree
    Set totalPassed = 0
    Set totalFailed = 0

    // Iterate through test classes in this suite
    Set className = ""
    For {
        Set className = $Order(^UnitTest.Result(logIndex, suitePath, className))
        Quit:className=""

        // Iterate through test methods in this class
        Set testMethod = ""
        For {
            Set testMethod = $Order(^UnitTest.Result(logIndex, suitePath, className, testMethod))
            Quit:testMethod=""

            // Get test result: $LB(status, duration, ..., errorMessage)
            Set testData = ^UnitTest.Result(logIndex, suitePath, className, testMethod)
            Set status = $ListGet(testData, 1)
            Set errorMsg = $ListGet(testData, 4)

            If status = 1 {
                Set totalPassed = totalPassed + 1
            } Else {
                Set totalFailed = totalFailed + 1
                Write "FAILED: ", className, ":", testMethod
                If errorMsg '= "" {
                    Write " - ", errorMsg
                }
                Write !
            }
        }
    }

    // Print summary
    Write !,"Summary: ", totalPassed, " passed"
    If totalFailed > 0 {
        Write ", ", totalFailed, " failed"
    }
    Write !

    // Return 1 only if all passed
    Return (totalFailed = 0)
}

/// Exit the IRIS process
/// Note: IRIS terminal mode does not support setting exit codes directly.
/// The calling script should check the return value of Offline()/Live() and exit accordingly.
/// @param pOK 1 for success, 0 for failure (for documentation/future use)
ClassMethod Exit(pOK As %Boolean)
{
    Halt
}

}
