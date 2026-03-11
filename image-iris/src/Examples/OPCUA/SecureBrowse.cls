Include (OPCUA.Constants, Ensemble)

/// IRIS OPC UA Secure Browse Example
Class Examples.OPCUA.SecureBrowse
{

ClassMethod Run()
{
	#dim tSC As %Status = $$$OK
	#dim e As %Exception.AbstractException
	
	Try {

		set tSC = ##class(OPCUA.Utils).Initialize()
		Quit:$$$ISERR(tSC)
		
		set tClient = ##class(OPCUA.Client).%New()

		set tSC = tClient.Initialize()
		Quit:$$$ISERR(tSC)

		set tClientURI = "urn:secuac"
		set tCertificatePathname = "/usr/irissys/uac/certs/secuac.crt.der"
		set tPrivateKeyPathname = "/usr/irissys/uac/certs/secuac.key.der"
		set tTrustListDir = "/usr/irissys/uac/certs/trustdir"
		set tRevocationListDir = "/usr/irissys/uac/certs/crldir"
		set tSC = tClient.SetupClient(,$$$OpcuaMessageSecurityModeSignAndEncrypt,tClientURI,tCertificatePathname,tPrivateKeyPathname,tTrustListDir,tRevocationListDir)
		Quit:$$$ISERR(tSC)

		set tSC = tClient.Connect("opc.tcp://certified-server","user1","password")
		Quit:$$$ISERR(tSC)

		// Start with Root Node (0,84)
		set tNode = $LB(0,84,0,6)

		#dim tResults as %List
		set tSC = tClient.Browse(.tResults, $LB($LI(tNode,3)), $LB($LI(tNode,1)), $LB($LI(tNode,2)))

		w !! 
		if $$$ISERR(tSC) {
			set ERROR=tSC zw ERROR
			Quit
		} else {
			w "Displaying results starting with those for the root node (DEPTH=0)",!
			set RESULTS=tResults zw ROOTNODE
		}
		w !

		set tDepth = 1
		set tPrevDepth = tDepth
		set tNodeList = $LB(tNode)

		while 1 {

			set NODE=$LI(tNodeList,tDepth) zw NODE
			set DEPTH=tDepth-1 zw DEPTH

			set tRefList = $LI($LI($LI(tResults,4),1),4)

			for i=1:1:$LL(tRefList) {
				set tRef = $LI(tRefList,i)
				if $LI($LI(tRef,3),3) = 0 {
					w i_" :  "_$LI($LI(tRef,4),1)_" ("_$LI($LI(tRef,3),1)_","_$LI($LI(tRef,3),2)_")",!
				} else {
					w i_" :  "_$LI($LI(tRef,4),1)_" ("_$LI($LI(tRef,3),1)_",'"_$LI($LI(tRef,3),2)_"')",!
				}
			}

			if $LL(tRefList) = 0 {
				READ "LEAF / END OF LIST (u=up,q=quit): ",c
			} elseif tDepth = 1 {
				READ "SELECT (1-n,q=quit): ",c
			} else {
				READ "SELECT (1-n,u=up,q=quit): ",c
			}

			set tPrevDepth = tDepth

			if c = "q" {
				Quit
			} elseif c = "u" {
				if tDepth = 1 {
					w !!, "Root Node (DEPTH=0)",!!
					continue
				} else {
					if tDepth > 1 set tDepth = tDepth - 1
					set tNode = $LI(tNodeList,tDepth)
				}
			} elseif $ISVALIDNUM(c,1,1,$LL(tRefList)) {
				set tNode = $LI($LI(tRefList,c),3)
				set tDepth = tDepth + 1
				set $LI(tNodeList,tDepth) = tNode
			} else {
				w !!, "Invalid entry: "_c,!!
				continue
			}

			set tSC = tClient.Browse(.tResults, $LB($LI(tNode,3)), $LB($LI(tNode,1)), $LB($LI(tNode,2)))

			w !!
			if $$$ISERR(tSC) {
				set ERROR=tSC zw ERROR
				set tDepth = tPrevDepth
				set tNode = $LI(tNodeList,tDepth)
			} else {
				set RESULTS=tResults zw RESULTS
			}
			w !

		}

		W !!!

		set tSC = tClient.Disconnect()

	} Catch (e) {
		Set tSC=e.AsStatus()
	}
	
	Quit tSC
}

}
