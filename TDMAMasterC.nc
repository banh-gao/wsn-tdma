#include "messages.h"

configuration TDMAMasterC {
	provides interface SplitControl as Control;
	provides interface Receive;
}
implementation {
	components TDMAMasterP as Impl;
	components SerialPrintfC, SerialStartC;

	//Configure
	components ActiveMessageC;
	Impl.AMControl -> ActiveMessageC;

	components CC2420TimeSyncMessageC as TSAM;
	Impl.TSPacket -> TSAM.TimeSyncPacket32khz;
	Impl.SyncSnd -> TSAM.TimeSyncAMSend32khz[AM_SYNCMSG]; // wire to the beacon AM type

	components new AMReceiverC(AM_JOINREQMSG) as JoinRcvC;
	components new AMSenderC(AM_JOINANSMSG) as JoinSndC;
	Impl.JoinRcv -> JoinRcvC;
	Impl.JoinSnd -> JoinSndC;

	components SlotTimerC;
	Impl.SlotTimer -> SlotTimerC;

	//Set control interface
	Control = Impl;

	//Directly pass incoming data packets to user
	components new AMReceiverC(AM_DATAMSG) as DataRcvC;
	Receive = DataRcvC;
}
