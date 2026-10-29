Include %occInclude

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

    // Run the test suite. Remember the last result index, so a run that records
    // nothing is not mistaken for the previous run.
    Set before = $Order(^UnitTest.Result(""), -1)
    Set mgr = ##class(%UnitTest.Manager).%New()
    Set tSC = mgr.RunTest(pPackage, "/noload/nodelete")

    Set logIndex = $Order(^UnitTest.Result(""), -1)
    If (logIndex = "") || (logIndex = before) {
        Write "ERROR: No test results found",!
        Return 0
    }

    // Result tree: ^UnitTest.Result(logIndex, suitePath, className, testMethod, assertionIdx)
    // Every level holds $LB(status, duration, ...), status 0 when something under
    // it failed. Asserts hold $LB(status, action, description, location).
    //
    // A failed assert is one failure. A level that failed with no failed assert
    // beneath it is one more: that is how IRIS records an error thrown in a test
    // method, or a failed OnBefore*/OnAfter*. Counting asserts alone passed those.
    Set suitePath = $Replace(pPackage, ".", "\")
    Set totalPassed = 0
    Set totalFailed = 0

    Write !
    Set suiteFailed = 0
    Set className = ""
    For {
        Set className = $Order(^UnitTest.Result(logIndex, suitePath, className))
        Quit:className=""

        Set caseFailed = 0
        Set testMethod = ""
        For {
            Set testMethod = $Order(^UnitTest.Result(logIndex, suitePath, className, testMethod))
            Quit:testMethod=""

            Set methodFailed = 0
            Set assertIdx = ""
            For {
                Set assertIdx = $Order(^UnitTest.Result(logIndex, suitePath, className, testMethod, assertIdx))
                Quit:assertIdx=""

                Set assertData = ^UnitTest.Result(logIndex, suitePath, className, testMethod, assertIdx)
                Set action = $ListGet(assertData, 2)
                Continue:action="LogMessage"
                If $ListGet(assertData, 1) = 1 {
                    Set totalPassed = totalPassed + 1
                } Else {
                    Set methodFailed = methodFailed + 1
                    Write "FAILED: ", className, ":", testMethod, " - ", $ListGet(assertData, 3), !
                }
            }
            Set methodData = $Get(^UnitTest.Result(logIndex, suitePath, className, testMethod))
            If ('methodFailed) && ($ListGet(methodData, 1) = 0) {
                Set methodFailed = 1
                Write "FAILED: ", className, ":", testMethod, " - ", ..LevelError(methodData), !
            }
            Set caseFailed = caseFailed + methodFailed
        }
        Set caseData = $Get(^UnitTest.Result(logIndex, suitePath, className))
        If ('caseFailed) && ($ListGet(caseData, 1) = 0) {
            Set caseFailed = 1
            Write "FAILED: ", className, " - ", ..LevelError(caseData), !
        }
        Set suiteFailed = suiteFailed + caseFailed
    }
    Set suiteData = $Get(^UnitTest.Result(logIndex, suitePath))
    If ('suiteFailed) && ($ListGet(suiteData, 1) '= 1) {
        Set suiteFailed = 1
        Write "FAILED: suite ", suitePath, " - ", $Select(suiteData="":"no results recorded", 1:..LevelError(suiteData)), !
    }
    If ('suiteFailed) && $$$ISERR(tSC) {
        Set suiteFailed = 1
        Write "FAILED: suite ", suitePath, " - ", $System.Status.GetErrorText(tSC), !
    }
    Set totalFailed = suiteFailed

    // Print summary
    Write !,"Summary: ", totalPassed, " passed"
    If totalFailed > 0 {
        Write ", ", totalFailed, " failed"
    }
    Write !

    // Return 1 only if all passed
    Return (totalFailed = 0)
}

/// The error text a failed result level carries: piece 4 (the error), else piece 3.
ClassMethod LevelError(pData As %List) As %String [ Internal ]
{
    Set tText = $ListGet(pData, 4)
    Quit $Select(tText'="":tText, 1:$ListGet(pData, 3))
}

/// Exit the IRIS process with the appropriate exit code
/// @param pOK 1 for success (exit 0), 0 for failure (exit 1)
ClassMethod Exit(pOK As %Boolean)
{
    Set exitCode = $Select(pOK:0, 1:1)
    Do $SYSTEM.Process.Terminate($JOB, exitCode)
}

}
