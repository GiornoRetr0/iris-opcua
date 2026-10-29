/// Smoke test for the offline test suite (no server, no native library required)
Class OPCUA.Tests.Unit.SmokeTest Extends %UnitTest.TestCase
{

/// Verify the test harness works for passing tests
Method TestTruth()
{
    Do $$$AssertEquals(1, 1, "One should equal one")
}

}
