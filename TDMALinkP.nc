#include <Timer.h>
#include <printf.h>

#include "messages.h"

#define SYNC_SLOT 0
#define JOIN_SLOT 1
#define RESYNC_SLOT N_SLOTS //Slots numbers >= N_SLOTS causes the scheduler to stop, it needs to be restarted

#define RESYNC_THRESHOLD 5

module TDMALinkP {
	provides interface SplitControl as Control;
	provides interface AMSend;
	provides interface Receive;

	uses {
		interface AMPacket;
		interface SplitControl as AMControl;
		interface PacketLink;

		interface TimeSyncAMSend<T32khz, uint32_t> as SyncSnd;
		interface Receive as SyncRcv;
        interface TimeSyncPacket<T32khz, uint32_t> as TSPacket;

		interface AMSend as JoinReqSnd;
		interface Receive as JoinReqRcv;

		interface AMSend as JoinAnsSnd;
		interface Receive as JoinAnsRcv;

		interface AMSend as DataSnd;

		interface SlotScheduler;
	}
}

implementation {

	bool isMaster;

	//Master
	am_addr_t allocatedSlots[N_SLOTS];
	int nextFreeSlot = 2;
	int nextListenDataSlot = 2;

	//Slave
	am_addr_t masterAddr;
	bool syncReceived = FALSE;
	uint8_t missedSyncCount = RESYNC_THRESHOLD; //Start node in resync mode
	bool hasJoined = FALSE;
	uint8_t assignedSlot;

	// Sync beacon packet
	SyncMsg* syncMsg;
	message_t syncBuf;
	bool syncSending = FALSE;

	// Join request packet
	message_t joinReqBuf;
	JoinReqMsg* joinReqMsg;
	bool joinReqSending = FALSE;

	// Join answer packet
	message_t joinAnsBuf;
	JoinAnsMsg* joinAnsMsg;
	bool joinAnsSending = FALSE;

	// Data packet
	message_t *dataMsg;
	uint8_t dataLen;
	bool dataReady = FALSE;

	// MASTER
	uint8_t allocateSlot(am_addr_t slave);
	void sendSyncBeacon();
	void sendJoinAnswer(am_addr_t slave, uint8_t slot);
	uint8_t getNextMasterSlot(uint8_t slot);

	// SLAVE
	void sendJoinRequest();
	void sendData();
	uint8_t getNextSlaveSlot(uint8_t slot);

	command error_t Control.start() {
		isMaster = (TOS_NODE_ID == 1);

		syncMsg = call SyncSnd.getPayload(&joinAnsBuf, sizeof(SyncMsg));
		joinReqMsg = call JoinReqSnd.getPayload(&joinAnsBuf, sizeof(JoinReqMsg));
		joinAnsMsg = call JoinAnsSnd.getPayload(&joinAnsBuf, sizeof(JoinAnsMsg));


		//Start slot scheduler and schedule first slot
		//TODO: turn on in specific time slots
		call AMControl.start();
		call SlotScheduler.start(5000, SYNC_SLOT);
		//call SlotScheduler.start(0, SYNC_SLOT);

		//TODO: signal per interfaccia splitcontrol
		return SUCCESS;
	}

	command error_t Control.stop() {
		//TODO: signal per interfaccia splitcontrol
		return SUCCESS;
	}

	event void SlotScheduler.slotStarted(uint8_t slot) {
		printf("Slot %d started\n", slot);

		//TODO: turn on radio if needed

		//TODO: move to radio startDone
		if(isMaster) {
			if(slot == SYNC_SLOT)
				sendSyncBeacon();
			return;
		}

		if(slot == SYNC_SLOT)
			syncReceived = FALSE;
			//TODO: Listen for sync
		else if (slot == JOIN_SLOT)
			sendJoinRequest();
		else
			sendData();
	}

	event void AMControl.startDone(error_t err) {
		printf("Radio ON\n");
	}

	event uint8_t SlotScheduler.slotEnded(uint8_t slot) {
		uint8_t nextSlot;
		printf("Slot %d ended\n", slot);

		nextSlot = (isMaster) ? getNextMasterSlot(slot) : getNextSlaveSlot(slot);

		//TODO: turn off radio if needed

		if(nextSlot == RESYNC_SLOT) {
				missedSyncCount = 0;
				printf("Going in RESYNC MODE\n");
				//TODO: go to resync mode
		}

		return nextSlot;
	}

	uint8_t getNextMasterSlot(uint8_t slot) {
		//Listen for join requests
		if(slot == SYNC_SLOT)
			return JOIN_SLOT;

		//Schedule for next allocated data slot and increment
		if(nextListenDataSlot < nextFreeSlot)
			return nextListenDataSlot++;

		nextListenDataSlot = 2;

		//No more data slots to listen to, schedule for sync beaconing
		return SYNC_SLOT;
	}

	uint8_t getNextSlaveSlot(uint8_t slot) {
		//Sync beacon missed, decide if to go to resync mode
		if(slot == SYNC_SLOT && syncReceived == FALSE) {
			missedSyncCount++;

			//Go to resync mode, RESYNC_SLOT stops the scheduler
			if(missedSyncCount > RESYNC_THRESHOLD)
				//FIMXE: set to RESYNC_SLOT
				return SYNC_SLOT;
		}

		//If node needs to join try to join in next slot
		if(slot == SYNC_SLOT && hasJoined == FALSE)
			return JOIN_SLOT;

		//If join failed, retry in the next epoch
		if(slot == JOIN_SLOT && hasJoined == FALSE)
			return SYNC_SLOT;

		//Transmit data (if any) in the assigned slot
		return assignedSlot;
	}

	event void AMControl.stopDone(error_t err) {
		printf("Radio OFF\n");
	}

	void sendSyncBeacon() {
		error_t status;
		if (!syncSending) {
			uint32_t epoch_time = call SlotScheduler.getEpochTime();
			printf("Sending sync beacon with reference time %lu\n", epoch_time);
			call PacketLink.setRetries(&syncBuf, 0);
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

	event message_t* SyncRcv.receive(message_t* msg, void* payload, uint8_t length) {
		if (length != sizeof(SyncMsg))
			return msg;

		//Remember master address to send unicast messages
		masterAddr = call AMPacket.source(msg);

		if (call TSPacket.isValid(msg) && length == sizeof(SyncMsg)) {
			uint32_t ref_time = call TSPacket.eventTime(msg);
			// synchronize the epoch start time (converted to our local time reference frame)
			call SlotScheduler.syncEpochTime(ref_time);
			printf("Local scheduler synchronized with master scheduler\n");
			syncReceived = TRUE;
		}

		return msg;
	}

	void sendJoinRequest() {
		error_t status;
		if (!joinReqSending) {
			printf("Sending join request to master %d\n", masterAddr);
			status = call JoinReqSnd.send(masterAddr, &joinReqBuf, sizeof(JoinReqMsg));
			if (status == SUCCESS) {
				joinReqSending = TRUE;
			} else {
				printf("Join request sending failed\n");
			}
		}
	}

	event void JoinReqSnd.sendDone(message_t* msg, error_t error) {
		joinReqSending = FALSE;
		if (error != SUCCESS) {
			printf("Join request transmission failed\n");
		}
	}

	event message_t* JoinReqRcv.receive(message_t* msg, void* payload, uint8_t length) {
		am_addr_t from;		
		uint8_t slot;
		if (length != sizeof(JoinReqMsg))
			return msg;

		joinReqMsg = (JoinReqMsg*) payload;

		from = call AMPacket.source(msg);

		printf("Join request received from %d\n", from);

		//FIXME: Allocate slot only after receiving answer ACK
		slot = allocateSlot(from);
		
		//Only slots greater than 1 can be allocated to slaves
		if(slot > 1)
			sendJoinAnswer(from, slot);
		else
			printf("No slots available");

		return msg;
	}

	uint8_t allocateSlot(am_addr_t slave) {
		uint8_t allocated;
		if(nextFreeSlot > N_SLOTS)
			return 0;

		allocated = nextFreeSlot;
		allocatedSlots[nextFreeSlot++] = slave;
		return allocated;
	}

	void sendJoinAnswer(am_addr_t slave, uint8_t slot) {
		error_t status;
		if (!joinReqSending) {
			joinAnsMsg->slot = slot;
			printf("Sending join answer to %d\n", slave);
			status = call JoinAnsSnd.send(slave, &joinAnsBuf, sizeof(JoinAnsMsg));
			if (status == SUCCESS) {
				joinAnsSending = TRUE;
			} else {
				printf("Join answer sending failed\n");
			}
		}
	}

	event void JoinAnsSnd.sendDone(message_t* msg, error_t error) {
		joinAnsSending = FALSE;
		if (error != SUCCESS) {
			printf("Join answer transmission failed\n");
		}
	}

	event message_t* JoinAnsRcv.receive(message_t* msg, void* payload, uint8_t length) {
		if (length != sizeof(JoinAnsMsg))
			return msg;

		joinAnsMsg = (JoinAnsMsg*) payload;

		assignedSlot = joinAnsMsg->slot;

		printf("Join completed to slot %d\n", assignedSlot);
		
		hasJoined = TRUE;

		return msg;
	}

	///////////////////// SLAVE DATA TRANSMISSION INTERFACE ////////////////////

	void sendData() {
		if(dataReady) {
			printf("Sending data\n");
			call DataSnd.send(masterAddr, dataMsg, dataLen);
		} else {
			printf("No data to transmit\n");
		}
	}

	command error_t AMSend.cancel(message_t *msg) {
		return call AMSend.cancel(msg);
	}

	command void* AMSend.getPayload(message_t *msg, uint8_t len) {
		return call AMSend.getPayload(msg, len);
	}

	command uint8_t AMSend.maxPayloadLength() {
		return call AMSend.maxPayloadLength();
	}

	command error_t AMSend.send(am_addr_t addr, message_t *msg, uint8_t len) {
		if(dataReady)
			return BUSY;

		dataMsg = msg;
		dataLen = len;

		dataReady = TRUE;

		return SUCCESS;
	}

	event void DataSnd.sendDone(message_t *msg, error_t error) {
		dataReady = FALSE;
		signal AMSend.sendDone(msg, error);
	}
}
