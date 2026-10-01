/// <class>OPCUA.Types.StringDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.StringDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Value As %String(OPCUAVALUETYPE = "String");

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
