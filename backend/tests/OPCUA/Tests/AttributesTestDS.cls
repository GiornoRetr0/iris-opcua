Class OPCUA.Tests.AttributesTestDS Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 2;

Property BrowseName As OPCUA.Types.QualifiedNameDataValue(OPCUAATTRIBUTEID = 3, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property DisplayName As OPCUA.Types.LocalizedTextDataValue(OPCUAATTRIBUTEID = 4, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property Description As OPCUA.Types.LocalizedTextDataValue(OPCUAATTRIBUTEID = 5, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property WriteMask As OPCUA.Types.IntegerDataValue(OPCUAATTRIBUTEID = 6, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property UserWriteMask As OPCUA.Types.IntegerDataValue(OPCUAATTRIBUTEID = 7, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property Value As OPCUA.Types.DoubleDataValue(OPCUAATTRIBUTEID = 13, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property DataType As OPCUA.Types.NodeIdDataValue(OPCUAATTRIBUTEID = 14, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property ValueRank As OPCUA.Types.IntegerDataValue(OPCUAATTRIBUTEID = 15, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property AccessLevel As OPCUA.Types.IntegerDataValue(OPCUAATTRIBUTEID = 17, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property UserAccessLevel As OPCUA.Types.IntegerDataValue(OPCUAATTRIBUTEID = 18, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property Historizing As OPCUA.Types.BooleanDataValue(OPCUAATTRIBUTEID = 20, OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

}
