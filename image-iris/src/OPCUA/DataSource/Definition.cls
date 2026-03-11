/// User-specified "DataSource" classes intended for use
/// with each of <class>TCPPollingService</class> and
/// <class>TCPSubscriptionService</class>, and indicating the 
/// data types and node ids for data requested from an
/// OPC UA server, should extend this class.
Class OPCUA.DataSource.Definition Extends %Persistent [ Abstract, NoExtent, PropertyClass = OPCUA.DataSource.PropertyClass ]
{

Projection OPCUADataSource As OPCUA.DataSource.Projection;

Parameter OPCUADATASOURCE;

Parameter OPCUDEFAULTANAMESPACE;

ClassMethod SaveSourcedData(ByRef pSourceData As %List, Output pAssignedID As %String) [ CodeMode = objectgenerator ]
{
    Quit:%class.Name="OPCUA.DataSource.Definition" $$$OK

    // %class is an instance of %Dictionary.ClassDefinition
    Set tStorageGlobal = %class.Storages.GetAt(1).DataLocation

    Do %code.WriteLine("#dim tSC as %Status = $$$OK")

    Do %code.WriteLine(" try {")

    Do %code.WriteLine(" Set pAssignedID = $Increment("_tStorageGlobal_")")
    Do %code.WriteLine(" Set "_tStorageGlobal_"(pAssignedID) = pSourceData")

    Do %code.WriteLine(" } catch (e) {")
    Do %code.WriteLine(" Set tSC = e.AsStatus()")
    Do %code.WriteLine(" }")

    Do %code.WriteLine(" Quit tSC")

    Quit $$$OK
}

ClassMethod CreateObjectFromSourceData(ByRef pSourceData As %List) As OPCUA.DataSource.Definition
{
    Do ..SaveSourcedData(pSourceData, .assignedId)
    Quit ..%OpenId(assignedId)
}

}
