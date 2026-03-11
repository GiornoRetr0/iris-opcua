Class OPCUA.Service.TCPPollingSendService Extends (OPCUA.Service.TCPPollingService, EnsLib.EDI.EDIFACT.Service.Standard)
{

Property TargetConfigNames As %String(MAXLEN = 1000);

Parameter SETTINGS = "TargetConfigNames:Basic:selector?multiSelect=1&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

Method OnProcessInput(ByRef pInputAsList As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
        #dim tSC as %Status = $$$OK
        try{
    
            set $LI(pInputAsList,1) = ""

            set tSC = $CLASSMETHOD(..Adapter.DataSourceClass,"SaveSourcedData", .pInputAsList, .pAssignedID)

            for iTarget=1:1:$L(..TargetConfigNames, ",") { 
                Set tOneTarget=$ZStrip($P(..TargetConfigNames,",",iTarget),"<>W")  Continue:""=tOneTarget
				//$$$sysTRACE("Sending EDIFACT document "_pDocIn_"/"_pDocIn.%Id()_" from "_pDocIn.Source_" to '"_tOneTarget_"'")
				
                Set tMsg = $CLASSMETHOD(..Adapter.DataSourceClass,"%OpenId",pAssignedID)
                Set tSC1= ..SendRequestAsync(tOneTarget,tMsg)

				Set:$$$ISERR(tSC1) tSC=$$$ADDSC(tSC,tSC1)
			}

        } catch (e) {
            set tSC = e.AsStatus()
        }

        return tSC
}

/// Return an array of connections for drawing lines on the config diagram
ClassMethod OnGetConnections(Output pArray As %String, pItem As Ens.Config.Item)
{
	Do ##super(.pArray,pItem)
	If pItem.GetModifiedSetting("TargetConfigNames",.tValue) {
		For i=1:1:$L(tValue,",") { Set tOne=$ZStrip($P(tValue,",",i),"<>W")  Continue:""=tOne  Set pArray(tOne)="" }
	}
}

}
