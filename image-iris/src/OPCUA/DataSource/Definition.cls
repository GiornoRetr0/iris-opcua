/// Base class for hand-authored "DataSource" classes: declare one typed
/// property per OPC UA node (using the OPCUA.Types.* value classes plus
/// OPCUANODENAME) and extend this class to map a node graph to an IRIS table.
/// These declarative DataSources run under <class>TCPPollingService</class> /
/// <class>TCPSubscriptionService</class> and are used by the Examples and the
/// OPCUA.Tests harness (which validate the C++ type marshalling end-to-end).
///
/// NOTE: The pipeline wizard / REST /deploy endpoint does NOT use this path —
/// it generates flat row-source classes consumed by the *RowSourceService
/// runtime instead. See OPCUA.REST.DeployService and ARCHITECTURE.md.
Class OPCUA.DataSource.Definition Extends %Persistent [ Abstract, NoExtent, PropertyClass = OPCUA.DataSource.PropertyClass ]
{

Projection OPCUADataSource As OPCUA.DataSource.Projection;

Parameter OPCUADATASOURCE;

Parameter OPCUDEFAULTANAMESPACE;

Parameter OPCUAPIPELINEVERSION;

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
