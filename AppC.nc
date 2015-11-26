configuration AppC {
}
implementation {
	components AppP;
	components MainC;
	components SlotTimerC as SlotTimer;
	components SerialPrintfC, SerialStartC;

	AppP.Boot -> MainC;
	AppP.SlotTimer -> SlotTimer;
}
