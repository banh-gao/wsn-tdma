configuration TestC {
}
implementation {
	components TestP;
	components MainC;
	components TDMALinkC;
	components SerialPrintfC, SerialStartC;

	TestP.Boot -> MainC;
	TestP.TDMALinkControl -> TDMALinkC;
	TestP.TDMALinkSnd -> TDMALinkC.AMSend;
	TestP.TDMALinkRcv -> TDMALinkC.Receive;

	components new Timer32C() as Timer;
	TestP.DataTimer -> Timer;

	components ActiveMessageC;
	TestP.AMPacket -> ActiveMessageC;
}
