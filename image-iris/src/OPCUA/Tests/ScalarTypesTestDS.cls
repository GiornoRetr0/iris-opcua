Class OPCUA.Tests.ScalarTypesTestDS Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 2;

Property Boolean As OPCUA.Types.BooleanDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Boolean");

Property SByte As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.SByte");

Property Byte As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Byte");

Property Int16 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Int16");

Property UInt16 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.UInt16");

Property Int32 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Int32");

Property UInt32 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.UInt32");

Property Int64 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Int64");

Property UInt64 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.UInt64");

Property Float As OPCUA.Types.FloatDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Float");

Property Double As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.Double");

Property String As OPCUA.Types.StringDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.String");

Property TimeStamp As OPCUA.Types.TimeStampDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.DateTime");

// GUID

// ByteString

Property XMLElement As OPCUA.Types.StringDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.XmlElement");

Property NodeId As OPCUA.Types.NodeIdDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.NodeId");

// ExpandedNodeId

Property StatusCode As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.StatusCode");

Property QualifiedName As OPCUA.Types.QualifiedNameDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.QualifiedName");

Property LocalizedText As OPCUA.Types.LocalizedTextDataValue(OPCUANODENAME = "Demo.Dynamic.Scalar.LocalizedText");

// ExtensionObject

}
