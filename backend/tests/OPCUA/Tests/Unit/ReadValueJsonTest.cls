/// Offline: how <class>OPCUA.REST.ReadService</class> puts a read value into its JSON.
/// Needs no server and no native library.
Class OPCUA.Tests.Unit.ReadValueJsonTest Extends %UnitTest.TestCase
{

/// Returns the JSON of a response holding just <var>pValue</var>.
Method Json(pValue) As %String [ Private ]
{
	Set tResult = {}
	Do ##class(OPCUA.REST.ReadService).SetValue(tResult, pValue)
	Quit tResult.%ToJSON()
}

/// JavaScript keeps 53 bits of a JSON number, so an Int64 sent as a number reaches
/// the console with its last digits changed. Large integers go as strings.
Method TestLargeIntegersAreStrings()
{
	Do $$$AssertEquals(..Json(9223372036854775807), "{""value"":""9223372036854775807""}", "Int64 max is a string")
	Do $$$AssertEquals(..Json(-9223372036854775807), "{""value"":""-9223372036854775807""}", "negative Int64 is a string")
	Do $$$AssertEquals(..Json(1234567890123456), "{""value"":""1234567890123456""}", "16 digits is a string")
}

/// Everything else keeps its JSON type.
Method TestOtherValuesUnchanged()
{
	Do $$$AssertEquals(..Json(255), "{""value"":255}", "small integer stays a number")
	Do $$$AssertEquals(..Json(123456789012345), "{""value"":123456789012345}", "15 digits stays a number")
	Do $$$AssertEquals(..Json(3.25), "{""value"":3.25}", "decimal stays a number")
	Do $$$AssertEquals(..Json(""), "{""value"":""""}", "empty stays empty")
	Do $$$AssertEquals(..Json("2026-11-10 23:52:01.0836140"), "{""value"":""2026-11-10 23:52:01.0836140""}", "timestamp string unchanged")
	Do $$$AssertEquals(..Json([1,2]), "{""value"":[1,2]}", "array unchanged")
}

}
