Class Examples.OPCUADS.ArrayExample Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 2;

Property BooleanArr As OPCUA.Types.ArrayDataValue.Boolean(OPCUANODENAME = "Demo.Dynamic.Arrays.Boolean");

Property Int32Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Dynamic.Arrays.Int32");

Property DoubleArr As OPCUA.Types.ArrayDataValue.Double(OPCUANODENAME = "Demo.Dynamic.Arrays.Double");

Property StringArr As OPCUA.Types.ArrayDataValue.String(OPCUANODENAME = "Demo.Dynamic.Arrays.String");

}
