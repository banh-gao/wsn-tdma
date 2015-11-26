#include <Timer.h>
#include "messages.h"
configuration ExampleC {
}
implementation {
	components ExampleP as AppP, MainC, LedsC;
	components new Timer32C() as TimerBeaconTx;
	components new Timer32C() as TimerOff;
	components new Timer32C() as TimerOn;
	
	components CC2420TimeSyncMessageC as TSAM;
	components CC2420ActiveMessageC;
	components ActiveMessageC;

	AppP.TSPacket -> TSAM.TimeSyncPacket32khz;
	AppP.SendBeacon -> TSAM.TimeSyncAMSend32khz[AM_BEACONMSG]; // wire to the beacon AM type
	AppP.ReceiveBeacon -> TSAM.Receive[AM_BEACONMSG];
	
	AppP.Leds -> LedsC;
	AppP.Boot -> MainC;
	AppP.TimerBeaconTx -> TimerBeaconTx;
	AppP.TimerOff -> TimerOff;
	AppP.TimerOn -> TimerOn;
	AppP.AMControl -> ActiveMessageC;
}
