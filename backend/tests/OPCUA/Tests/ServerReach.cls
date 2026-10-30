/// Tells "the server could not be reached" apart from every other connect failure,
/// for live tests that skip when their server is down. Only the first may skip: a
/// bad certificate, wrong credentials or a library that fails to load are errors in
/// the setup, and must fail. Lives outside Unit and Live, so it is never collected.
Class OPCUA.Tests.ServerReach
{

/// The native error codes a down or unreachable server gives, as measured on the
/// compose stack: a closed port gives BadDisconnect, an unknown host or a server
/// that drops the handshake gives BadConnectionClosed. The others are the
/// connection-level codes the same situations can produce on other networks.
Parameter UnreachableCodes = "80AD0000,80AE0000,80050000,800A0000,800D0000,808A0000,80AC0000";

/// 1 if <var>pSC</var> is a connect failure that means the server was not reached.
ClassMethod IsUnreachable(pSC As %Status) As %Boolean
{
	Quit:$$$ISOK(pSC) 0
	set tText = $System.Status.GetErrorText(pSC)
	set tAt = $Find(tText, "OPC UA Error 0x")
	Quit:tAt=0 0
	Quit ($ListFind($ListFromString(..#UnreachableCodes), $ZConvert($Extract(tText, tAt, tAt + 7), "U")) > 0)
}

}
