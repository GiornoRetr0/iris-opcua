/// Smoke test for the live test suite (requires plc server)
Class OPCUA.Tests.Live.SmokeTest Extends %UnitTest.TestCase
{

/// Verify the test harness works for passing tests
Method TestTruth()
{
    Do $$$AssertEquals(1, 1, "One should equal one")
}

}
