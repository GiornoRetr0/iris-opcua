/// Stands in for a business service when <class>MeasurementMetadataTest</class>
/// drives <method>OPCUA.Adapter.TCPSubscriptionInboundAdapter.ProcessBatch</method>
/// offline. A notification "bad<n>" returns an error naming it, "throw" throws,
/// anything else succeeds.
Class OPCUA.Tests.FakeBatchHost Extends %RegisteredObject
{

Property %WaitForNextCallInterval As %Boolean [ InitialExpression = 0 ];

/// Every notification handed in, in order.
Property Received As %List;

Method ProcessInput(pInput As %RegisteredObject) As %Status
{
    set ..Received = ..Received _ $LB(pInput)
    if pInput = "throw" {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "thrown by "_pInput))
    }
    if $Extract(pInput, 1, 3) = "bad" {
        quit $$$ERROR($$$GeneralError, "failed "_pInput)
    }
    quit $$$OK
}

}
