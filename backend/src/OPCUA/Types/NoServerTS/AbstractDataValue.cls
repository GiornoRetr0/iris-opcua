/// A measurement without its ServerTimeStamp: source timestamp, status and the
/// typed payload. Device schemas created with includeServerTimestamp = false type
/// their columns with the classes in this package, so their tables have no
/// *_ServerTimeStamp column at all.
///
/// This deliberately does not extend <class>OPCUA.Types.AbstractDataValue</class>,
/// which would bring the property back. Each concrete class mirrors its
/// OPCUA.Types counterpart (OPCUA.Types.X is OPCUA.Types.NoServerTS.X here) with
/// the payload starting at storage position 3 instead of 4.
///
/// The native layer always returns the full DataValue, so only
/// <class>OPCUA.DataSource.RowWriter</class>, which drops the server timestamp,
/// may store these. Hand-authored DataSources under TCPPollingService store the
/// native list unchanged and must keep using the OPCUA.Types classes.
Class OPCUA.Types.NoServerTS.AbstractDataValue Extends %SerialObject [ PropertyClass = OPCUA.Types.PropertyClass ]
{

Property SourceTimeStamp As %TimeStamp [ SqlFieldName = "SourceTS" ];

Property Status As %Integer;

Storage Default
{
<Data name="AbstractDataValueState">
<Value name="1">
<Value>SourceTimeStamp</Value>
</Value>
<Value name="2">
<Value>Status</Value>
</Value>
</Data>
<State>AbstractDataValueState</State>
<StreamLocation>^OPCUA.Types.NoServerTS.AbstractDataValueS</StreamLocation>
<Type>%Storage.Serial</Type>
}

}
