Class OPCUA.Types.NodeIdDataValue Extends OPCUA.Types.AbstractDataValue
{

Property Namespace As %Integer;

Property Identifier;

Property IdentifierType As %Integer;

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
<Value>Namespace</Value>
</Value>
<Value name="5">
<Value>Identifier</Value>
</Value>
<Value name="6">
<Value>IdentifierType</Value>
</Value>
</Data>
<Type>%Storage.Serial</Type>
}

}
