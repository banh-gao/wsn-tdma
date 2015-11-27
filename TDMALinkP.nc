#include <Timer.h>
#include <printf.h>

#include "messages.h"

#define SYNC_SLOT 0
#define JOIN_SLOT 1

#define RESYNC_THRESHOLD 5
#define JOIN_RETRY 3
#define DATA_RETRY 3

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
} implementation {

	//Control
	bool isStarted = FALSE;
	bool isStopped = FALSE;
	bool isMaster;

	//Master
	am_addr_t allocatedSlots[N_SLOTS-2];
	uint8_t nextFreeSlotPos = 0;
	uint8_t allocateSlot(am_addr_t slave);
	void sendSyncBeacon();
	void sendJoinAnswer(am_addr_t slave, uint8_t slot);
	uint8_t getNextMasterSlot(uint8_t slot);
	bool getMasterRadioOff(uint8_t current, uint8_t next);

	//Slave
	am_addr_t masterAddr;
	bool syncMode;
	bool syncReceived = FALSE;
	uint8_t missedSyncCount = 0;
	bool hasJoined = FALSE;
	uint8_t assignedSlot;
	void sendJoinRequest();
	void sendData();
	uint8_t getNextSlaveSlot(uint8_t slot);
	bool getSlaveRadioOff(uint8_t current, uint8_t next);
	bool dataReady = FALSE;
	// Outgoing data packet
	message_t *dataMsg;
	uint8_t dataLen;

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


	command error_t Control.start() {
		isMaster = (TOS_NODE_ID == 1);

		syncMsg = call SyncSnd.getPayload(&joinAnsBuf, sizeof(SyncMsg));
		joinReqMsg = call JoinReqSnd.getPayload(&joinAnsBuf, sizeof(JoinReqMsg));
		joinAnsMsg = call JoinAnsSnd.getPayload(&joinAnsBuf, sizeof(JoinAnsMsg));

		if(isMaster) {
			syncMode = FALSE;
			//Start slot scheduler now
			call SlotScheduler.start(0, SYNC_SLOT);
		} else {
			//Scheduler is activated only after successful synchronization
			syncMode = TRUE;
			printf("DEBUG: Entering SYNC MODE\n");
		}
		
		call AMControl.start();

		return SUCCESS;
	}

	command error_t Control.stop() {
		call SlotScheduler.stop();
		call AMControl.stop();
		isStarted = FALSE;
		return SUCCESS;
	}

	event void SlotScheduler.slotStarted(uint8_t slot) {
		printf("DEBUG: Slot %d started\n", slot);

		//TODO: move all to radio startDone
		if(isMaster) {
			if(slot == SYNC_SLOT)
				sendSyncBeacon();
			return;
			//TODO: turn on radio for join listen and allocate slots (if slot is started radio has always to be turned on)
		}

		if(slot == SYNC_SLOT)
			syncReceived = FALSE;
			//TODO: turn on radio for sync listening
		else if (slot == JOIN_SLOT)
			sendJoinRequest();
		else
			sendData();
	}

	event void AMControl.startDone(error_t err) {
		printf("DEBUG: Radio ON\n");

		//FOR CONTROL INTERFACE: Signal that master is ready only when radio is on for the first time
		if(isMaster && isStarted == FALSE) {
				isStarted = TRUE;
				signal Control.startDone(SUCCESS);
		}
	}

	event uint8_t SlotScheduler.slotEnded(uint8_t slot) {
		uint8_t nextSlot;
		bool radioOff;
		printf("DEBUG: Slot %d ended\n", slot);

		nextSlot = (isMaster) ? getNextMasterSlot(slot) : getNextSlaveSlot(slot);

		//In sync mode the radio is always on and scheduler is not running
		if(syncMode) {
			printf("DEBUG: Entering SYNC MODE\n");
			call SlotScheduler.stop();
			return SYNC_SLOT;
		}

		radioOff = (isMaster) ? getMasterRadioOff(slot, nextSlot) : getSlaveRadioOff(slot, nextSlot);
		if(radioOff)
			call AMControl.stop();

		return nextSlot;
	}

	uint8_t getNextMasterSlot(uint8_t slot) {
		//Listen for join requests
		if(slot == SYNC_SLOT)
			return JOIN_SLOT;

		//Schedule for next allocated data slot
		if(slot < nextFreeSlotPos+2)
			return slot+1;

		//No more allocated data slots to listen to, schedule for next epoch sync beaconing
		return SYNC_SLOT;
	}

	uint8_t getNextSlaveSlot(uint8_t slot) {
		if(slot == SYNC_SLOT && syncReceived == FALSE) {
			missedSyncCount++;
			printf("DEBUG: Missed synchronization beacon %d/%d\n", missedSyncCount, RESYNC_THRESHOLD);

			//Go to resync mode, returning RESYNC_SLOT stops the scheduler
			if(missedSyncCount >= RESYNC_THRESHOLD) {
				syncMode = TRUE;
				return SYNC_SLOT;
			}
		}

		//If node needs to join try to join in next slot (only if synchronization has succeeded)
		if(slot == SYNC_SLOT && syncReceived == TRUE && hasJoined == FALSE)
			return JOIN_SLOT;

		//If join failed, retry in the next epoch
		if(slot == JOIN_SLOT && hasJoined == FALSE)
			return SYNC_SLOT;

		//Reschedule for sync in next epoch
		if(slot == assignedSlot)
			return SYNC_SLOT;

		//Transmit data (if any) in the assigned slot
		return assignedSlot;
	}

	bool getMasterRadioOff(uint8_t current, uint8_t next) {
		return FALSE;
	}

	bool getSlaveRadioOff(uint8_t current, uint8_t next) {
		return FALSE;
	}

	event void AMControl.stopDone(error_t err) {
		printf("DEBUG: Radio OFF\n");

		//FOR CONTROL INTERFACE: Signal that component has stopped
		if(isStarted == FALSE)
			signal Control.stopDone(SUCCESS);
	}

	void sendSyncBeacon() {
		error_t status;
		if (!syncSending) {
			printf("DEBUG: Sending synchronization beacon\n");
			call PacketLink.setRetries(&syncBuf, 0);
			status = call SyncSnd.send(AM_BROADCAST_ADDR, &syncBuf, sizeof(SyncMsg), call SlotScheduler.getEpochTime());
			if (status == SUCCESS) {
				syncSending = TRUE;
			} else {
				printf("DEBUG: Synchronization beacon sending failed\n");
			}
		}
	}

	event void SyncSnd.sendDone(message_t* msg, error_t error) {
		syncSending = FALSE;
		if (error != SUCCESS) {
			printf("DEBUG: Synchronization beacon transmission failed\n");
		}
	}

	event message_t* SyncRcv.receive(message_t* msg, void* payload, uint8_t length) {
		uint32_t ref_time;
		if (length != sizeof(SyncMsg))
			return msg;

		//Remember master address to send unicast messages
		masterAddr = call AMPacket.source(msg);

		//Invalid sync message
		if (call TSPacket.isValid(msg) == FALSE || length != sizeof(SyncMsg))
			return msg;

		ref_time = call TSPacket.eventTime(msg);

		if(syncMode) {
			//If sync mode was active switch to slotted mode
			syncMode = FALSE;		
			if(hasJoined) {
				//Already joined, just desynchronized
				call SlotScheduler.start(ref_time, assignedSlot);
			} else {
				//Join phase never completed
				call SlotScheduler.start(ref_time, JOIN_SLOT);
			}
			printf("DEBUG: Local scheduler started and synchronized with master scheduler\n");
			printf("DEBUG: Entering SLOTTED MODE\n");	
		} else {
			//Synchronize the running scheduler
			call SlotScheduler.syncEpochTime(ref_time);
			printf("DEBUG: Local scheduler synchronized with master scheduler\n");
		}

		syncReceived = TRUE;
		missedSyncCount = 0;

		return msg;
	}

	void sendJoinRequest() {
		error_t status;
		if (!joinReqSending) {
			printf("DEBUG: Sending join request to master %d\n", masterAddr);
			call PacketLink.setRetries(&joinReqBuf, JOIN_RETRY);
			status = call JoinReqSnd.send(masterAddr, &joinReqBuf, sizeof(JoinReqMsg));
			if (status == SUCCESS) {
				joinReqSending = TRUE;
			} else {
				printf("DEBUG: Join request sending failed\n");
			}
		}
	}

	event void JoinReqSnd.sendDone(message_t* msg, error_t error) {
		joinReqSending = FALSE;
		if (error != SUCCESS) {
			printf("DEBUG: Join request transmission failed\n");
		}
	}

	event message_t* JoinReqRcv.receive(message_t* msg, void* payload, uint8_t length) {
		am_addr_t from;		
		if (length != sizeof(JoinReqMsg))
			return msg;

		joinReqMsg = (JoinReqMsg*) payload;

		from = call AMPacket.source(msg);

		printf("DEBUG: Join request received from %d\n", from);
		
		//Send answer only if there are slots available
		if(nextFreeSlotPos < N_SLOTS-2)
			sendJoinAnswer(from, allocateSlot(from));
		else
			printf("WARNING: No slots available\n");

		return msg;
	}

	uint8_t allocateSlot(am_addr_t slave) {
		int slot;
		//Check if slot was already allocated to the node
		for(slot=0;slot<N_SLOTS-2;slot++) {
			if(allocatedSlots[slot] == slave)
				return slot+2;
		}

		allocatedSlots[nextFreeSlotPos] = slave;
		return (nextFreeSlotPos++)-2;
	}

	void sendJoinAnswer(am_addr_t slave, uint8_t slot) {
		error_t status;
		if (!joinReqSending) {
			joinAnsMsg->slot = slot;
			printf("DEBUG: Sending join answer to %d\n", slave);
			call PacketLink.setRetries(&joinAnsBuf, JOIN_RETRY);
			status = call JoinAnsSnd.send(slave, &joinAnsBuf, sizeof(JoinAnsMsg));
			if (status == SUCCESS) {
				joinAnsSending = TRUE;
			} else {
				printf("DEBUG: Join answer sending failed\n");
			}
		}
	}

	event void JoinAnsSnd.sendDone(message_t* msg, error_t error) {
		joinAnsSending = FALSE;
		if (error != SUCCESS) {
			printf("DEBUG: Join answer transmission failed\n");
		}
	}

	event message_t* JoinAnsRcv.receive(message_t* msg, void* payload, uint8_t length) {
		if (length != sizeof(JoinAnsMsg))
			return msg;

		joinAnsMsg = (JoinAnsMsg*) payload;

		assignedSlot = joinAnsMsg->slot;

		printf("DEBUG: Join completed to slot %d\n", assignedSlot);
		
		hasJoined = TRUE;

		//FOR CONTROL INTERFACE: Signal that slave is ready
		isStarted = TRUE;
		signal Control.startDone(SUCCESS);

		return msg;
	}

	///////////////////////////////////////////////////////////////////////////////////
	////////////////////// DATA TRANSMISSION INTERFACE FOR SLAVES /////////////////////

	void sendData() {
		if(dataReady) {
			printf("DEBUG: Sending data\n");
			call PacketLink.setRetries(&joinReqBuf, DATA_RETRY);
			call DataSnd.send(masterAddr, dataMsg, dataLen);
		} else {
			printf("DEBUG: No data to transmit\n");
		}
	}

	command error_t AMSend.cancel(message_t *msg) {
		return call DataSnd.cancel(msg);
	}

	command void* AMSend.getPayload(message_t *msg, uint8_t len) {
		return call DataSnd.getPayload(msg, len);
	}

	command uint8_t AMSend.maxPayloadLength() {
		return call DataSnd.maxPayloadLength();
	}

	command error_t AMSend.send(am_addr_t addr, message_t *msg, uint8_t len) {
		if(dataReady)
			return BUSY;

		dataReady = TRUE;

		dataMsg = msg;
		dataLen = len;

		return SUCCESS;
	}

	event void DataSnd.sendDone(message_t *msg, error_t error) {
		dataReady = FALSE;
		signal AMSend.sendDone(msg, error);
	}
}
