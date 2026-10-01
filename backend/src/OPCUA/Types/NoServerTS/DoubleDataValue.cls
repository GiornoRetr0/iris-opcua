/// <class>OPCUA.Types.DoubleDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.DoubleDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Value As %Double(OPCUAVALUETYPE = "Double");

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
<Value>Value</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
