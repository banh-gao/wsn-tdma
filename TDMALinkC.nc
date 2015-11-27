#ifndef SLOT_DURATION
#error SLOT_DURATION not set
#endif

#ifndef N_SLOTS
#error N_SLOTS not set
#endif

configuration TDMALinkC {
	provides interface SplitControl as Control;
	provides interface Receive;
	provides interface AMSend;
} implementation {
	components TDMALinkP as Impl;
	components SerialPrintfC, SerialStartC;

	//Radio link control
	components ActiveMessageC, PacketLinkC;
	Impl.AMPacket -> ActiveMessageC;
	Impl.AMControl -> ActiveMessageC.SplitControl;
	Impl.PacketLink -> PacketLinkC;

	//Sync beacon
	components CC2420TimeSyncMessageC as TSAM;
	Impl.TSPacket -> TSAM.TimeSyncPacket32khz;
	Impl.SyncSnd -> TSAM.TimeSyncAMSend32khz[AM_SYNCMSG];
	Impl.SyncRcv -> TSAM.Receive[AM_SYNCMSG];

	//Join messages
	components new AMSenderC(AM_JOINREQMSG) as JoinReqSndC;
	components new AMReceiverC(AM_JOINREQMSG) as JoinReqRcvC;
	Impl.JoinReqSnd -> JoinReqSndC;
	Impl.JoinReqRcv -> JoinReqRcvC;

	components new AMSenderC(AM_JOINANSMSG) as JoinAnsSndC;
	components new AMReceiverC(AM_JOINANSMSG) as JoinAnsRcvC;
	Impl.JoinAnsSnd -> JoinAnsSndC;
	Impl.JoinAnsRcv -> JoinAnsRcvC;

	//Outgoing data messages
	components new AMSenderC(AM_DATAMSG) as DataSndC;
	Impl.DataSnd -> DataSndC;

	//Slot scheduler
	components new SlotSchedulerC(SLOT_DURATION, N_SLOTS);
	Impl.SlotScheduler -> SlotSchedulerC;

	//Export interface for incoming data messages
	components new AMReceiverC(AM_DATAMSG) as DataRcvC;
	Receive = DataRcvC;

	//Export interface for outgoing data messages
	AMSend = Impl;

	//Export control interface
	Control = Impl;
}
