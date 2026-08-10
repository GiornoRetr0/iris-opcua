/// IRIS local OPC UA subscription demo node id and data type specifications
Class Examples.OPCUADS.SecureExample Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 1;

Property CurrentTime As OPCUA.Types.TimeStampDataValue(OPCUANODENAME = "2345");

Property TheAnswer As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "the.answer");

}
