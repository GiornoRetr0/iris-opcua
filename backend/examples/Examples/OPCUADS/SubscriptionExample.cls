/// IRIS local OPC UA subscription demo node id and data type specifications
Class Examples.OPCUADS.SubscriptionExample Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 1;

Property SA1 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "SA1");

Property SA2 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "SA2");

Property VT5 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "VT5");

Property PRNO As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "PRNO");

Property PROG As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "PROG");

}
