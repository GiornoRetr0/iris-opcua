Include %occInclude

/// Unit tests for OPCUA.Utils and OPCUA.DateTimeUtils
Class OPCUA.Tests.Unit.UtilsTest Extends %UnitTest.TestCase
{

/// Test that DateTimeUtils methods compile without tRetVal variable
Method TestDateConvVariables()
{
    // Check OPCUA2UNIX method
    Set tSC = ..CheckMethodForVariable("OPCUA.DateTimeUtils", "OPCUA2UNIX", "tRetVal", .tCount)
    Do $$$AssertStatusOK(tSC, "OPCUA2UNIX should compile clean")
    Do $$$AssertEquals(tCount, 0, "OPCUA2UNIX should not contain 'tRetVal' (capital V)")

    // Check UNIX2OPCUA method
    Set tSC = ..CheckMethodForVariable("OPCUA.DateTimeUtils", "UNIX2OPCUA", "tRetVal", .tCount)
    Do $$$AssertStatusOK(tSC, "UNIX2OPCUA should compile clean")
    Do $$$AssertEquals(tCount, 0, "UNIX2OPCUA should not contain 'tRetVal' (capital V)")
}

/// Test that missing library error preserves the reason
Method TestMissingLibraryReason()
{
    // Point at a non-existent library file
    Set ^||OPCUA.LibPathOverride = "/tmp/nonexistent_opcua_lib_test.so"

    // Try to initialize
    Set tSC = ##class(OPCUA.Utils).Initialize()

    // Should fail
    Do $$$AssertNotTrue($$$ISOK(tSC), "Initialize should fail with missing library")

    // Error text should contain the missing path
    Set tErrorText = $System.Status.GetErrorText(tSC)
    Do $$$AssertTrue(tErrorText [ "/tmp/nonexistent_opcua_lib_test.so", "Error should contain the missing library path")

    // Error should NOT contain the old misleading message
    Do $$$AssertTrue(tErrorText '[ "Invalid status code structure", "Error should not contain 'Invalid status code structure'")

    // Clean up
    Kill ^||OPCUA.LibPathOverride
}

/// Helper: Search compiled method implementation for a variable name (case-sensitive)
ClassMethod CheckMethodForVariable(pClassName As %String, pMethodName As %String, pVarName As %String, Output pCount As %Integer) As %Status
{
    Set pCount = 0
    Set tSC = $$$OK
    Try {
        Set tMethodDef = ##class(%Dictionary.MethodDefinition).%OpenId(pClassName_"||"_pMethodName)
        If '$IsObject(tMethodDef) {
            Set tSC = $$$ERROR($$$GeneralError, "Method "_pMethodName_" not found in "_pClassName)
            Quit
        }

        Set tImpl = tMethodDef.Implementation
        If '$IsObject(tImpl) {
            Set tSC = $$$ERROR($$$GeneralError, "No implementation for "_pMethodName)
            Quit
        }

        // Search implementation line by line for the variable (case-sensitive)
        While 'tImpl.AtEnd {
            Set tLine = tImpl.ReadLine()
            Set tPos = 1
            While 1 {
                Set tPos = $Find(tLine, pVarName, tPos)
                If tPos = 0 Quit
                Set pCount = pCount + 1
            }
        }
    } Catch (e) {
        Set tSC = e.AsStatus()
    }
    Quit tSC
}

}
