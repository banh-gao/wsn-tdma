configuration TDMASlaveC {
	provides interface SplitControl as Control;
	provides interface AMSend;
}
implementation {
	components SerialPrintfC, SerialStartC;
	components SlotTimerC;

	components TDMASlaveP;

	TDMASlaveP.SlotTimer -> SlotTimerC;

	Control = SlaveC;
	AMSend = SlaveC;
}
