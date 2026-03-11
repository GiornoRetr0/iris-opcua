ROUTINE OPCUA.Constants [Type=INC]


#; *** zf Function Ordinals ***

#define zfTest								1
#define zfTestGetInt						2
#define zfTestStatusCodeName				3
#define zfReadLog							4
#define zfGetStatusCodeNameB				5
#define zfGetClientStateNameB				6
#define zfGetSimpleErrorCodeNameB			7
#define zfCreateClientB						8
#define zfGetClientStateB					9
#define zfGetClientStateC					10
#define zfSetupClientB						11
#define zfDestroyClientB					12
#define zfConnectB							13
#define zfDisconnectB						14
#define zfReadBulkSetup						15
#define zfReadBulkSetupB					16
#define zfReadBulkSetupC					17
#define zfReadBulkPoll						18
#define zfReadBulkPollB						19
#define zfReadBulkPollC						20
#define zfReadBulkClear						21
#define zfCreateSubscription				22
#define zfCreateSubscriptionB				23
#define zfPollSubscription					24
#define zfDeleteSubscription				25
#define zfReadAttribute						26
#define zfReadValueAttribute				27
#define zfWriteAttribute					28
#define zfWriteValueAttributeIntB			29
#define zfWriteValueAttributeStrB			30
#define zfDateConvOPCUA2HOROLOG				31
#define zfDateConvHOROLOG2OPCUA				32
#define zfDateConvOPCUA2ODBC				33
#define zfDateConvODBC2OPCUA				34
#define zfDateConvOPCUA2UNIX				35
#define zfDateConvUNIX2OPCUA				36

#define zfGetClientStateD					37
#define zfConnectUser                       38
#define zfSetupClientC						39
#define zfGetChannelStateName				40
#define zfGetSessionStateName				41
#define zfBrowse            				42
#define zfBrowseNext        				43
#define zfVersion           				44
#define zfGetUStr           				45
#define zfSetLogFile                        46



#; *** OPC UA Constants ***

#define OpcuaDateTimeFormatHOROLOG				0
#define OpcuaDateTimeFormatOPCUA				1
#define OpcuaDateTimeFormatODBC					2
#define OpcuaDateTimeFormatUNIX					3

#define OpcuaNodeIdTypeNumeric					0
#define OpcuaNodeIdTypeString					3
#define OpcuaNodeIdTypeGUID						4
#define OpcuaNodeIdTypeByteString				5

#define OpcuaVariantIsScalar					0
#define OpcuaVariantIsEmptyScalar				1
#define OpcuaVariantIsEmptyArray				2
#define OpcuaVariantIsArray						3

#define OpcuaDataTypeBoolean					0
#define OpcuaDataTypeSByte						1
#define OpcuaDataTypeByte						2
#define OpcuaDataTypeInt16						3
#define OpcuaDataTypeUInt16						4
#define OpcuaDataTypeInt32						5
#define OpcuaDataTypeUInt32						6
#define OpcuaDataTypeInt64						7
#define OpcuaDataTypeUInt64						8
#define OpcuaDataTypeFloat						9
#define OpcuaDataTypeDouble						10
#define OpcuaDataTypeString						11
#define OpcuaDataTypeDateTime					12
#define OpcuaDataTypeGUID						13
#define OpcuaDataTypeByteString					14
#define OpcuaDataTypeXMLElement					15
#define OpcuaDataTypeNodeId						16
#define OpcuaDataTypeExpandedNodeId				17
#define OpcuaDataTypeStatusCode					18
#define OpcuaDataTypeQualifiedName				19
#define OpcuaDataTypeLocalizedText				20
#define OpcuaDataTypeExtensionObject			21
#define OpcuaDataTypeDataValue					22
#define OpcuaDataTypeVariant					23
#define OpcuaDataTypeDiagnosticInfo				24
#;#define OpcuaDataTypeDecimal					25
#;#define OpcuaDataTypeEnum						26
#;#define OpcuaDataTypeStructure				27
#;#define OpcuaDataTypeOptStruct				28
#;#define OpcuaDataTypeUnion					29
#;#define OpcuaDataTypeBitFieldCluster			30

#define OpcuaAttributeNodeId					1
#define OpcuaAttributeNodeClass					2
#define OpcuaAttributeBrowseName				3
#define OpcuaAttributeDisplayName				4
#define OpcuaAttributeDescription				5
#define OpcuaAttributeWriteMask					6
#define OpcuaAttributeUserWriteMask				7
#define OpcuaAttributeIsAbstract				8
#define OpcuaAttributeSymmetric					9
#define OpcuaAttributeInverseName				10
#define OpcuaAttributeContainsNoLoops			11
#define OpcuaAttributeEventNotifier				12
#define OpcuaAttributeValue						13
#define OpcuaAttributeDataType					14
#define OpcuaAttributeValueRank					15
#define OpcuaAttributeArrayDimensions			16
#define OpcuaAttributeAccessLevel				17
#define OpcuaAttributeUserAccessLevel			18
#define OpcuaAttributeMinimumSamplingInterval	19
#define OpcuaAttributeHistorizing				20
#define OpcuaAttributeExecutable				21
#define OpcuaAttributeUserExecutable			22
#define OpcuaAttributeDataTypeDefinition		23

#define OpcuaMessageSecurityModeNone            1
#define OpcuaMessageSecurityModeSignAndEncrypt  3



#; *** Client Codes ***

#define UAClientStateDisconnected			0
#define UAClientStateWaitingForAck			1
#define UAClientStateConnected				2
#define UAClientStateSecureChannel			3
#define UAClientStateSession				4
#define UAClientStateSessionDisconnected	5
#define UAClientStateSessionRenewed			6



#; *** From %Net.MQTT.inc (not including zf function ordinals) ***

#; Error Types (UACERR_TYPE)
#define ErrorTypeNone		0
#define ErrorTypeInfo		1
#define ErrorTypeApp		2
#define ErrorTypeCallin		3
#define ErrorTypeOPCUA		4
#define ErrorTypeClient		5
#define ErrorTypeServer		6
#define ErrorTypeUnknown	7

#; Miscellaneous
#define utf8			    $$$Text("utf-8 encoded string")



#; *** From %occErrors.inc ***

#;#define MQTTCLIENT                               27000
#;#define MQTTParameterMustBe                      27001
#;#define MQTTParameterMaxLength                   27002
#;#define MQTTParameterIllegalValue                27003
#;#define MQTTNoCAConfigured                       27004
#;#define MQTTIllegalQOS                           27005
#;#define MQTTSendTimedOut                         27006
#define OPCUACLIENT                              29000
#define OPCUAParameterMustBe                     29001



#; *** From %callout.inc ***

#;#define IrisMQTTLibrary                           1037
#;#define IrisOPCUALibrary                          1038
#define IrisOPCUALibrary                          1039



