/// <class>OPCUA.Types.Multidimensional</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.Multidimensional Extends OPCUA.Types.NoServerTS.AbstractDataValue
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
<Value>Status</Value>
</Value>
<Value name="3">
<Value>Values</Value>
</Value>
<Value name="4">
<Value>NumberOfDimensions</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
