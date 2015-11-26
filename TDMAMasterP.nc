#include <Timer.h>
#include <printf.h>

#include "messages.h"

module TDMAMasterP {
	provides interface SplitControl as Control;
	provides interface Receive;

	uses {
		interface SplitControl as AMControl;

		interface TimeSyncAMSend<T32khz, uint32_t> as SyncSnd;
        interface TimeSyncPacket<T32khz, uint32_t> as TSPacket;

		interface AMSend as JoinSnd;
		interface Receive as JoinRcv;

		interface SlotTimer;
	}
}

implementation {

	// Sync beacon packet
	message_t syncBuf;
	bool syncSending = FALSE;

	// Join request packet
	message_t joinReqBuf;
	JoinReqMsg* joinReqMsg;

	// Join answer packet
	message_t joinAnsBuf;
	JoinAnsMsg* joinAnsMsg;
	bool joinSending = FALSE;

	command error_t Control.start() {
		joinAnsMsg = call JoinSnd.getPayload(&joinAnsBuf, sizeof(JoinAnsMsg));

		// turn on the radio
		call AMControl.start();
	}

	event void AMControl.startDone(error_t err) {
		//Start epoch timer that slaves will be syncronized with
		call SlotTimer.setEpochTime(0);
		//Schedule first sync beacon
		call SlotTimer.scheduleSlot(SYNC_SLOT);
	}

	command error_t Control.stop() {

	}

	event void AMControl.stopDone(error_t err) {

	}

	void sendSyncBeacon() {
		error_t status;
		if (!syncSending) {
			uint32_t epoch_time = call SlotTimer.getEpochTime();
			printf("Sending sync beacon with reference time %d\n", epoch_time);
			status = call SyncSnd.send(AM_BROADCAST_ADDR, &syncBuf, sizeof(SyncMsg), epoch_time);
			if (status == SUCCESS) {
				syncSending = TRUE;
			} else {
				printf("Sync beacon sending failed\n");
			}
		}
	}

	event void SyncSnd.sendDone(message_t* msg, error_t error) {
		syncSending = FALSE;
		if (error != SUCCESS) {
			printf("Sync beacon transmission failed\n");
		}
	}

	event message_t* JoinRcv.receive(message_t* msg, void* payload, uint8_t length) {

		if (length != sizeof(JoinReqMsg))
			return msg;

		joinReqMsg = (JoinReqMsg*) payload;

		return msg;
	}

	event void JoinSnd.sendDone(message_t* msg, error_t error) {
		joinSending = FALSE;
		if (error != SUCCESS) {
			printf("Join answer transmission failed\n");
		}
	}

	event void SlotTimer.slotStarted(uint8_t slot) {
		sendSyncBeacon();
	}

	event void SlotTimer.slotEnded(uint8_t slot) {
		call SlotTimer.scheduleSlot(SYNC_SLOT);

		//TODO: turn off radio when data not expected
		//call SlotTimer.scheduleSlot(getNextActiveSlot(slot));
	}
}
