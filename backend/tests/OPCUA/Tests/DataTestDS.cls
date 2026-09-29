Class OPCUA.Tests.DataTestDS Extends (%Persistent, OPCUA.DataSource.Definition)
{

Parameter OPCUADATASOURCE = "MyDataSource2";

Parameter OPCUDEFAULTANAMESPACE = 2;

Property Boolean As OPCUA.Types.BooleanDataValue(OPCUANODENAME = "Demo.Static.Scalar.Boolean");

Property SByte As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.SByte");

Property Byte As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.Byte");

Property Int16 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.Int16");

Property UInt16 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.UInt16");

Property Int32 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.Int32");

Property UInt32 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.UInt32");

Property Int64 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.Int64");

Property UInt64 As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.UInt64");

Property Float As OPCUA.Types.FloatDataValue(OPCUANODENAME = "Demo.Static.Scalar.Float");

Property Double As OPCUA.Types.DoubleDataValue(OPCUANODENAME = "Demo.Static.Scalar.Double");

Property String As OPCUA.Types.StringDataValue(OPCUANODENAME = "Demo.Static.Scalar.String");

Property TimeStamp As OPCUA.Types.TimeStampDataValue(OPCUANODENAME = "Demo.Static.Scalar.DateTime");

// GUID 

// ByteString

Property XMLElement As OPCUA.Types.StringDataValue(OPCUANODENAME = "Demo.Static.Scalar.XmlElement");

Property NodeId As OPCUA.Types.NodeIdDataValue(OPCUANODENAME = "Demo.Static.Scalar.NodeId");

// ExpandedNodeId

Property StatusCode As OPCUA.Types.IntegerDataValue(OPCUANODENAME = "Demo.Static.Scalar.StatusCode");

Property QualifiedName As OPCUA.Types.QualifiedNameDataValue(OPCUANODENAME = "Demo.Static.Scalar.QualifiedName");

Property LocalizedText As OPCUA.Types.LocalizedTextDataValue(OPCUANODENAME = "Demo.Static.Scalar.LocalizedText");

// ExtensionObject

// *** ARRAYS ***

Property BooleanArr As OPCUA.Types.ArrayDataValue.Boolean(OPCUANODENAME = "Demo.Static.Arrays.Boolean");

Property SByteArr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.SByte");

Property ByteArr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.Byte");

Property Int16Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.Int16");

Property UInt16Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.UInt16");

Property Int32Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.Int32");

Property UInt32Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.UInt32");

Property Int64Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.Int64");

Property UInt64Arr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.UInt64");

Property FloatArr As OPCUA.Types.ArrayDataValue.Float(OPCUANODENAME = "Demo.Static.Arrays.Float");

Property DoubleArr As OPCUA.Types.ArrayDataValue.Double(OPCUANODENAME = "Demo.Static.Arrays.Double");

// Property StringArr As OPCUA.Types.ArrayDataValue.String(OPCUANODENAME = "Demo.Static.Arrays.String");

Property TimeStampArr As OPCUA.Types.ArrayDataValue.TimeStamp(OPCUANODENAME = "Demo.Static.Arrays.DateTime");

// GUID 

// ByteString

Property XMLElementArr As OPCUA.Types.ArrayDataValue.String(OPCUANODENAME = "Demo.Static.Arrays.XmlElement");

// NodeId

// ExpandedNodeId

Property StatusCodeArr As OPCUA.Types.ArrayDataValue.Integer(OPCUANODENAME = "Demo.Static.Arrays.StatusCode");

// QualifiedName

// LocalizedText

// ExtensionObject

// *** MATRICES ***

Property BooleanMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Boolean");

Property SByteMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.SByte");

// Byte (not present on server)

Property Int16Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Int16");

Property UInt16Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.UInt16");

Property Int32Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Int32");

Property UInt32Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.UInt32");

Property Int64Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Int64");

Property UInt64Matrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.UInt64");

Property FloatMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Float");

Property DoubleMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.Double");

Property StringMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.String");

Property TimeStampMatrix As OPCUA.Types.Multidimensional(OPCUANODENAME = "Demo.Static.Matrix.DateTime");

// Guid

// ByteString (not present on server)

// XmlElement (not present on server)

// NodeId

// ExpandedNodeId

// StatusCode

// QualifiedName

// LocalizedText

// ExtensionObject

}
