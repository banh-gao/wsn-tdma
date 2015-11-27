configuration TestC {
}
implementation {
	components TestP;
	components MainC;
	components TDMALinkC;
	components SerialPrintfC, SerialStartC;

	TestP.Boot -> MainC;
	TestP.LinkCtrl -> TDMALinkC.Control;
	TestP.LinkSnd -> TDMALinkC.AMSend;
	TestP.LinkRcv -> TDMALinkC.Receive;

	components new Timer32C() as Timer;
	TestP.DataTimer -> Timer;

	components ActiveMessageC;
	TestP.AMPacket -> ActiveMessageC;
}
