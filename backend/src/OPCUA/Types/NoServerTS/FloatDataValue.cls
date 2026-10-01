/// <class>OPCUA.Types.FloatDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.FloatDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Value As %Float(OPCUAVALUETYPE = "Float");

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
