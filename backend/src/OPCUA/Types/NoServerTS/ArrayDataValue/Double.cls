/// <class>OPCUA.Types.ArrayDataValue.Double</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.ArrayDataValue.Double Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Values As list Of %Double;

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
</Data>
<Type>%Storage.Serial</Type>
}

}
