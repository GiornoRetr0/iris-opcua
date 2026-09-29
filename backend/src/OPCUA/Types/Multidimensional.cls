/// A multi-dimensional value may have a number of dimensions. If it has just one dimension,
/// consider using the Array types which are typed and can be easily iterated using the normal
/// %Collection methods such as Count() and GetAt().
/// 
/// But if it has more than one dimension, this is the perfect type for it. To keep things simple though,
/// we are not enforcing the data type in the IRIS side. The "Values" property is just a %List (A $listbuild)
/// that is actually a "list of lists". If you have two dimensions, each element of this list is another list like: 
/// Example for getting row 1, column 1: $ListGet($ListGet(obj.Values, 1), 1).
/// If you have three dimensions, this will be $ListGet($ListGet($ListGet(obj.Values, 1) , 1), 1).
Class OPCUA.Types.Multidimensional Extends OPCUA.Types.AbstractDataValue
{

Property Values As %List;

Property NumberOfDimensions As %Integer [ InitialExpression = 2 ];

Storage Default
{
<Data name="AbstractDataValueState">
<Value name="1">
<Value>SourceTimeStamp</Value>
</Value>
<Value name="2">
<Value>ServerTimeStamp</Value>
</Value>
<Value name="3">
<Value>Status</Value>
</Value>
<Value name="4">
<Value>Values</Value>
</Value>
<Value name="5">
<Value>NumberOfDimensions</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
