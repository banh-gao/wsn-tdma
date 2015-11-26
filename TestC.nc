configuration TestC {
}
implementation {
	components TestP;
	components MainC;
	components TDMAMasterC;
	components SerialPrintfC, SerialStartC;

	TestP.Boot -> MainC;
	TestP.MasterCtrl -> TDMAMasterC.Control;
	TestP.MasterRcv -> TDMAMasterC.Receive;
}
