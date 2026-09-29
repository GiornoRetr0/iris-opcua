Class OPCUA.Types.LocalizedTextDataValue Extends OPCUA.Types.AbstractDataValue
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
<Value>ServerTimeStamp</Value>
</Value>
<Value name="3">
<Value>Status</Value>
</Value>
<Value name="4">
<Value>Text</Value>
</Value>
<Value name="5">
<Value>Locale</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
