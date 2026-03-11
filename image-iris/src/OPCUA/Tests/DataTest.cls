Include (OPCUA.Constants, Ensemble)

Class OPCUA.Tests.DataTest
{

ClassMethod Run()
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {		

		/*

		set tStmt = ##class(%SQL.Statement).%New()
		set tSC = tStmt.%Prepare("DELETE FROM Examples_OCPUADS.DataTest")
		Quit:$$$ISERR(tSC)

		set tRet = tStmt.%Execute()
		Quit:tRet'=0

 		&sql(DELETE FROM Examples_OPCUADS.DataTest)
		if SQLCODE<0 {
			w "Error deleting from DataTest table"
			Quit
		}

		*/

		set tStmt = ##class(%SQL.Statement).%New()
		set tSC = tStmt.%Prepare("DELETE FROM OPCUA_Tests.DataTestDS")
		zw tSC
		//Quit:$$$ISERR(tSC)
		if '$$$ISERR(tSC) {
			set tRet = tStmt.%Execute()
			if tRet '= 0 {
				//w "Error deleting from DataTest table"
				//zw tRet
				//Quit
			}
		}

		if ##class(Ens.Director).IsProductionRunning() {
			set tSC = ##class(Ens.Director).StopProduction()
			Quit:$$$ISERR(tSC)
		}

		set tSC = ##class(Ens.Director).StartProduction("OPCUA.Tests.Production")
		Quit:$$$ISERR(tSC)

		if '##class(Ens.Director).IsItemEnabled("DataTest",) {
			set tSC = ##class(Ens.Director).EnableConfigItem("DataTest")
			Quit:$$$ISERR(tSC)
		}

		w !!,"Gathering data..."
		hang 2
		w " Done.",!

		do ##class(Ens.Director).StopProduction()

		w !

		set RecId = $GET(^OPCUA.Tests.DataTestDSD)
		w !,"Using record #"_RecId

		set TestData = ##class(OPCUA.Tests.DataTestDS).%OpenId(RecId)

		set BooleanCD = 0
		set SByteCD = 31
		set ByteCD = 0
		set Int16CD = 0
		set UInt16CD = 600
		set Int32CD = 50
		set UInt32CD = 448
		set Int64CD = 0
		set UInt64CD = 700
		set FloatCD = $double(77)
		set DoubleCD = $double(4.5569875151026986159)
		set StringCD = "Hello World!"
		set TimeStampCD = "2021-02-22 01:02:58.5540300"
		// Guid
		// ByteString
		set XMLElementCD = "<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0)
		//set NodeIdCD = ##class(OPCUA.Types.NodeId).%New()
		//set NodeIdCD.NamespaceIndex = 1
		//set NodeIdCD.IdentifierType = 3
		//set NodeIdCD.Identifier = "MyStringNodeId"
		// ExpandedNodeId
		set StatusCodeCD = 0
		// QualifiedName
		//set LocalizedTextCD = ##class(OPCUA.Types.LocalizedText).%New()
		//set LocalizedTextCD.Text = "LocalizedText"
		//set LocalizedText.Locale = "en"
		// ExtensionObject

		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Boolean",TestData.Boolean.Value,BooleanCD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("SByte",TestData.SByte.Value,SByteCD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Byte",TestData.Byte.Value,ByteCD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Int16",TestData.Int16.Value,Int16CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("UInt16",TestData.UInt16.Value,UInt16CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Int32",TestData.Int32.Value,Int32CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("UInt32",TestData.UInt32.Value,UInt32CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Int64",TestData.Int64.Value,Int64CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("UInt64",TestData.UInt64.Value,UInt64CD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Float",TestData.Float.Value,FloatCD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("Double",TestData.Double.Value,DoubleCD)
		//Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("String",TestData.String.Value,StringCD)
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("TimeStamp",TestData.TimeStamp.Value,TimeStampCD)
		// Guid
		// ByteString
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("XMLElement",TestData.XMLElement.Value,XMLElementCD)
		// NodeId
		// ExpandedNodeId
		Quit:'##class(OPCUA.Tests.DataTest).TestDataValue("StatusCode",TestData.StatusCode.Value,StatusCodeCD)
		// QualifiedName
		// LocalizedText
		// ExtensionObject

		/*
		// Boolean
		if TestData.Boolean '= BooleanCD {
			w !,"Inconsistency encountered while testing Boolean ["_TestData.Boolean_","_BooleanCD_"]"
			Quit
		}
		*/


		// *** ARRAYS ***

		set BooleanArrCD = $LB(1,1,1,1,1,1,1,1,1,1)
		set SByteArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
		set ByteArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
		//set Int16ArrCD = $LB(-7,-4,-3,-2,-1,0,1,2,3,4)
		set Int16ArrCD = $LB(6,1,1,1,1,0,1,2,3,4)
		set UInt16ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
		set Int32ArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
		set UInt32ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
		set Int64ArrCD = $LB(-5,-4,-3,-2,-1,0,1,2,3,4)
		set UInt64ArrCD = $LB(0,1,2,3,4,5,6,7,8,9)
		set FloatArrCD = $LB($double(6.1167511940002441406),$double(20.100000381469726562),$double(20.200000762939453125),$double(20.299999237060546875),$double(20.399999618530273437),20.5,$double(20.600000381469726562),$double(20.700000762939453125),$double(20.799999237060546875),$double(20.899999618530273437))
		set DoubleArrCD = $LB($double(10),$double(10.2),$double(10.4),$double(10.6),$double(10.8),$double(11),$double(11.2),$double(11.4),$double(11.6),$double(11.8))
		// String array data omitted due to server issue
		set TimeStampArrCD = $LB("2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300","2021-02-22 01:02:58.5540300")
		// Guid
		// ByteString
		set XmlElementArrCD = $LB("<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0),"<?xml version=""1.0"" encoding=""UTF-8""?>"_$c(0))
		// NodeId
		// ExpandedNodeId
		set StatusCodeArrCD = $LB(0,$ZHEX("80310000"),$ZHEX("80330000"),$ZHEX("80360000"),$ZHEX("803A0000"),$ZHEX("80400000"),0,$ZHEX("80310000"),$ZHEX("80330000"),$ZHEX("80360000"))
		// QualifiedName
		//set LocalizedTextArrCD = $LB(1,1,1,1,1,1,1,1,1,1)
		// ExtensionObject


		// BooleanArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.BooleanArr.Values, BooleanArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing BooleanArr ["_tAns_"]"
			Quit
		}

		// SByteArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.SByteArr.Values, SByteArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing SByteArr ["_tAns_"]"
			Quit
		}

		// ByteArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.ByteArr.Values, ByteArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing ByteArr ["_tAns_"]"
			Quit
		}

		// Int16
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.Int16Arr.Values, Int16ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int16Arr ["_tAns_"]"
			Quit
		}

		// UInt16
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.UInt16Arr.Values, UInt16ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt16Arr ["_tAns_"]"
			Quit
		}

		// Int32
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.Int32Arr.Values, Int32ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int32Arr ["_tAns_"]"
			Quit
		}

		// UInt32
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.UInt32Arr.Values, UInt32ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt32Arr ["_tAns_"]"
			Quit
		}

		// Int64
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.Int64Arr.Values, Int64ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int64Arr ["_tAns_"]"
			Quit
		}

		// UInt64
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.UInt64Arr.Values, UInt64ArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt64Arr ["_tAns_"]"
			Quit
		}

		// FloatArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.FloatArr.Values, FloatArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing FloatArr ["_tAns_"]"
			Quit
		}

		// DoubleArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.DoubleArr.Values, DoubleArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing DoubleArr ["_tAns_"]"
			Quit
		}
	
		// String array data omitted due to server issue

		// TimeStampArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.TimeStampArr.Values, TimeStampArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing TimeStampArr ["_tAns_"]"
			Quit
		}
	
		// XmlElementArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.XMLElementArr.Values, XmlElementArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing XMLElementArr ["_tAns_"]"
			Quit
		}
	
		// StatusCodeArr
		set tAns = ##class(OPCUA.Tests.DataTest).TestElements(TestData.StatusCodeArr.Values, StatusCodeArrCD)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing StatusCodeArr ["_tAns_"]"
			Quit
		}
	
		// LocalizedTextArr
		//set tAns = ##class(OPCUA.Tests.DataTest).TestObjects(TestData.LocalizedTextArr.Values, LocalizedTextArrCD)
		//if tAns >= 0 {
		//	w !,"Inconsistency encountered while testing LocalizedTextArr ["_tAns_"]"
		//	Quit
		//}
	

		// *** MATRICES ***

		set BooleanMatrixCD = $lb($lb($lb(0,1,0),$lb(1,0,1),$lb(0,1,0),$lb(1,0,1)),$lb($lb(0,1,0),$lb(1,0,1),$lb(0,1,0),$lb(1,0,1)))
		set SByteMatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set Int16MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set UInt16MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set Int32MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set UInt32MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set Int64MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set UInt64MatrixCD = $lb($lb($lb(0,1,2),$lb(3,4,5),$lb(6,7,8),$lb(9,10,11)),$lb($lb(12,13,14),$lb(15,16,17),$lb(18,19,20),$lb(21,22,23)))
		set FloatMatrixCD = $lb($lb($lb($double(0),$double(3.1415927410125732421),$double(6.2831854820251464843)),$lb($double(9.424777984619140625),$double(12.566370964050292968),$double(15.707963943481445312)),$lb($double(18.84955596923828125),$double(21.99114990234375),$double(25.132741928100585937)),$lb($double(28.274333953857421875),$double(31.415927886962890625),$double(34.557521820068359375))),$lb($lb($double(37.6991119384765625),$double(40.84070587158203125),$double(43.9822998046875)),$lb($double(47.123889923095703125),$double(50.265483856201171875),$double(53.407077789306640625)),$lb($double(56.54866790771484375),$double(59.6902618408203125),$double(62.83185577392578125)),$lb($double(65.97344970703125),$double(69.11504364013671875),$double(72.25662994384765625))))
		set DoubleMatrixCD = $lb($lb($lb($double(0),$double(3.1415926500000002086),$double(6.2831853000000004172)),$lb($double(9.4247779500000010699),$double(12.566370600000000834),$double(15.707963250000000599)),$lb($double(18.849555900000002139),$double(21.991148550000001904),$double(25.132741200000001668)),$lb($double(28.274333850000001433),$double(31.415926500000001198),$double(34.557519150000004516))),$lb($lb($double(37.699111800000004279),$double(40.840704450000004044),$double(43.982297100000003808)),$lb($double(47.123889750000003573),$double(50.265482400000003337),$double(53.407075050000003102)),$lb($double(56.548667700000002867),$double(59.690260350000002631),$double(62.831853000000002396)),$lb($double(65.973445650000002161),$double(69.115038300000009031),$double(72.256630950000001689))))
		// String
		// TimeStamp
		// Guid
		// ByteString (not present on server)
		// XmlElement (not present on server)
		// NodeId
		// ExpandedNodeId
		// StatusCode
		// QualifiedName
		// LocalizedText
		// ExtensionObject


		// BooleanMatrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.BooleanMatrix.Values, BooleanMatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing BooleanMatrix ["_tAns_"]"
			Quit
		}

		// SByteMatrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.SByteMatrix.Values, SByteMatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing SByteMatrix ["_tAns_"]"
			Quit
		}

		// Int16Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.Int16Matrix.Values, Int16MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int16Matrix ["_tAns_"]"
			Quit
		}

		// UInt16Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.UInt16Matrix.Values, UInt16MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt16Matrix ["_tAns_"]"
			Quit
		}

		// Int32Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.Int32Matrix.Values, Int32MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int32Matrix ["_tAns_"]"
			Quit
		}

		// UInt32Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.UInt32Matrix.Values, UInt32MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt32Matrix ["_tAns_"]"
			Quit
		}

		// Int64Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.Int64Matrix.Values, Int64MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing Int64Matrix ["_tAns_"]"
			Quit
		}

		// UInt64Matrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.UInt64Matrix.Values, UInt64MatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing UInt64Matrix ["_tAns_"]"
			Quit
		}

		// FloatMatrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.FloatMatrix.Values, FloatMatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing FloatMatrix ["_tAns_"]"
			Quit
		}

		// DoubleMatrix
		set tAns = ##class(OPCUA.Tests.DataTest).TestLists(TestData.DoubleMatrix.Values, DoubleMatrixCD, 3)
		if tAns >= 0 {
			w !,"Inconsistency encountered while testing DoubleMatrix ["_tAns_"]"
			Quit
		}


		w !,"PASSES"

	} Catch (e) {
		Set tSC=e.AsStatus()
		w !
		zw tSC
	}
	
	w !!

	Quit tSC
}

ClassMethod TestDataValue(Name As %String, TestDatum, Comparison) As %Boolean
{
	if TestDatum '= Comparison {
		w !,"Inconsistency encountered while testing "_Name
		w !!,"Test Data:",!
		zzdump TestDatum
		w !!,"Comparison Data:",!
		zzdump Comparison
		w !
		return 0
	} else {
		return 1
	}
}

ClassMethod TestLists(TestData As %List, Comparison As %List, QtyDims As %Integer = 1) As %Integer
{
	
	set CurErr = ""

	try {

		set DimLens = $LB(0)
		set CurItem = $LB(0)
		set working = TestData
		for i=1:1:QtyDims {
			set $LI(DimLens,i) = $LL(working)
			set $LI(CurItem,i) = 1
			set working = $LI(working,1)
		}

		do {

			set CurErr = ""
			for i=1:1:QtyDims {
				set CurErr = CurErr_"["_$LI(CurItem,i)_"]"
			}

			set working = TestData
			for i=1:1:QtyDims {
				set working = $LI(working,$LI(CurItem,i))
			}
			set TestDat = working

			set working = Comparison
			for i=1:1:QtyDims {
				set working = $LI(working,$LI(CurItem,i))
			}
			set CompareDat = working

			if (TestDat '= CompareDat) {

				w !!,"Error Location: "_CurErr

				w !!,"Test Data:",!
				zzdump TestDat

				w !!,"Comparison Data:",!
				zzdump CompareDat

				w !
				return 0
			}
			
			set i = QtyDims
			do {
				set $LI(CurItem,i) = $LI(CurItem,i) + 1
				if $LI(CurItem,i) <= $LI(DimLens,i) {
					Quit
				}
				if i = 1 {
					// The job is done
					return -1
				}
				set $LI(CurItem,i) = 1
				set i = i - 1
			} while i > 0

		} while 1

	} catch (e) {
		w !!,"Unexpected error encountered while testing array elements "_CurErr

		return 0
	}
}

ClassMethod TestElements(TestData As %ListOfDataTypes, Comparison As %List) As %Integer
{
	try {

		if TestData.Count() '= $LL(Comparison) {
			// Different lengths
			w !!,"Test data and comparsion data arrays are of different lengths ["_TestData.Count()_","_$LL(Comparison)_"]",!
			return 0
		}

		for i=1:1:TestData.Count() {
			set TestDat = TestData.GetAt(i)
			set CompareDat = $LI(Comparison,i)
			if (TestDat '= CompareDat) {

				w !!,"Test Data:",!
				zzdump TestDat

				w !!,"Comparison Data:",!
				zzdump CompareDat

				w !
				return i
			}
		}

		return -1

	} catch (e) {
		w !!,"Unexpected error encountered while testing array elements"

		return 0
	}
}

ClassMethod TestObjects(TestData As %ListOfObjects, Comparison As %List) As %Integer
{
	try {

		w " d1 "
		if TestData.Count() '= $LL(Comparison) {
			// Different lengths
			w !!,"Test data and comparsion data arrays are of different lengths",!
			return 0
		}

		w " d2 "
		zw TestData.Count()
		for i=1:1:TestData.Count() {
			w " d3[i="_i_"] "
			zw TestData
			set TestDat = TestData.GetAt(i)
			w " d4 "
			set CompareDat = $LI(Comparison,i)
			w " d5 "
			if (TestDat '= CompareDat) {

				w !!,"Test Data:",!
				zzdump TestDat

				w !!,"Comparison Data:",!
				zzdump CompareDat

				w !
				return i
			}
		}

		return -1

	} catch (e) {
		w !!,"Unexpected error encountered while testing array elements"

		return 0
	}
}

}
