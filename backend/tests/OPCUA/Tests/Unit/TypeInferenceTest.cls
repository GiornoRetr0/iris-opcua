Include (OPCUA.Constants, %occInclude)

/// Offline half of the type-inference suite: the DataType + ValueRank map
/// (<method>OPCUA.DataSource.Generator.MapDataTypeToIRIS</method>) and that every
/// class it returns survives <method>OPCUA.REST.SchemaService.MapToDataValueType</method>.
Class OPCUA.Tests.Unit.TypeInferenceTest Extends %UnitTest.TestCase
{

// ==================== mapping ====================
Method TestMapping()
{
    set tGen = "OPCUA.DataSource.Generator"
    // $LB(label, dataType, dimensions, expected)
    set tCases = $LB(
        $LB("Boolean", 1, 0, "OPCUA.Types.BooleanDataValue"),
        $LB("SByte", 2, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("UInt64", 9, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("Float", 10, 0, "OPCUA.Types.FloatDataValue"),
        $LB("Double", 11, 0, "OPCUA.Types.DoubleDataValue"),
        $LB("String", 12, 0, "OPCUA.Types.StringDataValue"),
        $LB("DateTime", 13, 0, "OPCUA.Types.TimeStampDataValue"),
        $LB("XmlElement", 16, 0, "OPCUA.Types.StringDataValue"),
        $LB("NodeId", 17, 0, "OPCUA.Types.NodeIdDataValue"),
        $LB("StatusCode", 19, 0, "OPCUA.Types.IntegerDataValue"),
        $LB("QualifiedName", 20, 0, "OPCUA.Types.QualifiedNameDataValue"),
        $LB("LocalizedText", 21, 0, "OPCUA.Types.LocalizedTextDataValue"),
        $LB("Duration (subtype of Double)", 290, 0, "OPCUA.Types.DoubleDataValue"),
        $LB("UtcTime (subtype of DateTime)", 294, 0, "OPCUA.Types.TimeStampDataValue"),
        $LB("Boolean array", 1, 1, "OPCUA.Types.ArrayDataValue.Boolean"),
        $LB("Double array", 11, 1, "OPCUA.Types.ArrayDataValue.Double"),
        $LB("DateTime array", 13, 1, "OPCUA.Types.ArrayDataValue.TimeStamp"),
        $LB("NodeId array (no typed class)", 17, 1, "OPCUA.Types.Multidimensional"),
        $LB("Double matrix", 11, 2, "OPCUA.Types.Multidimensional"),
        $LB("Guid (unknown) falls back", 14, 0, ""),
        $LB("abstract Integer falls back", 27, 0, ""),
        $LB("other-namespace type falls back", "", 0, ""))
    for i=1:1:$LL(tCases) {
        set tCase = $LI(tCases, i)
        do $$$AssertEquals($ClassMethod(tGen, "MapDataTypeToIRIS", $LI(tCase, 2), $LI(tCase, 3)), $LI(tCase, 4), $LI(tCase, 1))
    }

    // Every class the map can return must be a measurement class the schema
    // generator accepts as-is, or the column would silently become text.
    for tClass = "OPCUA.Types.NodeIdDataValue", "OPCUA.Types.QualifiedNameDataValue", "OPCUA.Types.LocalizedTextDataValue", "OPCUA.Types.Multidimensional", "OPCUA.Types.ArrayDataValue.TimeStamp", "OPCUA.Types.ArrayDataValue.Float" {
        do $$$AssertEquals(##class(OPCUA.REST.SchemaService).MapToDataValueType(tClass), tClass, tClass_" kept by MapToDataValueType")
    }
}

}
