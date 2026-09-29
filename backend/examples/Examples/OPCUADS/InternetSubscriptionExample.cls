/// IRIS Internet OPC UA subscription demo node id and data type specifications
Class Examples.OPCUADS.InternetSubscriptionExample Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 3;

Property Temperature As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "AirConditioner_1.Temperature");

Property Humidity As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "AirConditioner_1.Humidity");

}
