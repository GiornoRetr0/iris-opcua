/// <class>OPCUA.Types.LocalizedTextDataValue</class> without a server timestamp. See
/// <class>OPCUA.Types.NoServerTS.AbstractDataValue</class>.
Class OPCUA.Types.NoServerTS.LocalizedTextDataValue Extends OPCUA.Types.NoServerTS.AbstractDataValue
{

Property Text As %String(MAXLEN = "");

Property Locale As %String;

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
<Value>Text</Value>
</Value>
<Value name="4">
<Value>Locale</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
