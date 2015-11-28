#include <Timer.h>
#include <printf.h>

#include "messages.h"

#define SYNC_SLOT 0
#define JOIN_SLOT 1

#define RESYNC_THRESHOLD 5

#define DATA_RETRY 1
#define DATA_RETRY_DELAY SLOT_DURATION/2

#define SLEEP_SLOTS_THRESHOLD 1

module TDMALinkP {
	provides interface TDMALink as Control;
	provides interface AMSend;
	provides interface Receive;

	uses {
		interface AMPacket;
		interface SplitControl as AMControl;
		interface PacketLink;

		interface TimeSyncAMSend<T32khz, uint32_t> as SyncSnd;
		interface Receive as SyncRcv;
        interface TimeSyncPacket<T32khz, uint32_t> as TSPacket;

		interface Random as JoinReqRandom;
		interface Timer<T32khz> as JoinReqDelayTimer;

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
	am_addr_t allocatedSlots[DATA_SLOTS];
	uint8_t nextFreeSlotPos = 0;
	uint8_t allocateSlot(am_addr_t slave);
	void sendSyncBeacon();
	void sendJoinAnswer(am_addr_t slave, uint8_t slot);
	uint8_t getNextMasterSlot(uint8_t slot);
	bool getMasterRadioOff(uint8_t current, uint8_t next);

	//Slave
	am_addr_t masterAddr;
	bool syncMode = FALSE;
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

	void startSlotTask();
	uint8_t udiff(uint8_t n1, uint8_t n2);

	command error_t Control.startMaster() {
		isMaster = TRUE;

		syncMsg = call SyncSnd.getPayload(&joinAnsBuf, sizeof(SyncMsg));
		joinReqMsg = call JoinReqSnd.getPayload(&joinAnsBuf, sizeof(JoinReqMsg));
		joinAnsMsg = call JoinAnsSnd.getPayload(&joinAnsBuf, sizeof(JoinAnsMsg));

		//Start master in SLOTTED MODE (radio managed by scheduler)
		call SlotScheduler.start(0, SYNC_SLOT);

		return SUCCESS;
	}

	command error_t Control.startSlave() {
		isMaster = FALSE;

		//Start slave in SYNC MODE (radio always on)
		syncMode = TRUE;
		printf("DEBUG: Entering SYNC MODE\n");
		call AMControl.start();

		return SUCCESS;
	}

	command bool Control.isMaster() {
		return isMaster;
	}

	command error_t Control.stop() {
		call SlotScheduler.stop();
		call AMControl.stop();
		isStarted = FALSE;
		return SUCCESS;
	}

	event void SlotScheduler.slotStarted(uint8_t slot) {
		printf("DEBUG: Slot %d started\n", slot);

		//Turn radio on, if it's already on execute slot task immediately
		if(call AMControl.start() == EALREADY)
			startSlotTask();
	}

	event void AMControl.startDone(error_t err) {
		printf("DEBUG: Radio ON\n");

		//Check if radio was turned on by slot scheduler
		if(call SlotScheduler.isRunning())
			startSlotTask();

		//FOR CONTROL INTERFACE: Signal that master is ready only when radio is on for the first time
		if(isMaster && isStarted == FALSE) {
				isStarted = TRUE;
				signal Control.startDone(SUCCESS);
		}
	}

	void startSlotTask() {
		//At this point it is guaranteed that the radio is already on

		uint8_t slot = call SlotScheduler.getScheduledSlot();
		if(isMaster) {
			if(slot == SYNC_SLOT)
				sendSyncBeacon();
			return;
		}

		if(slot == SYNC_SLOT)
			syncReceived = FALSE;
		else if (slot == JOIN_SLOT)
			sendJoinRequest();
		else
			sendData();
	}

	event uint8_t SlotScheduler.slotEnded(uint8_t slot) {
		uint8_t nextSlot;
		uint8_t inactivePeriod;
		printf("DEBUG: Slot %d ended\n", slot);

		nextSlot = (isMaster) ? getNextMasterSlot(slot) : getNextSlaveSlot(slot);

		//In sync mode the radio is always on and scheduler is not running
		if(syncMode) {
			printf("DEBUG: Entering SYNC MODE\n");
			call SlotScheduler.stop();
			return SYNC_SLOT;
		}

		//Count inactive slots (if reschedule the same slot, the inactive interval is DATA_SLOTS + SYNC_SLOT + JOIN_SLOT - 1)
		inactivePeriod = (slot == nextSlot) ? (DATA_SLOTS + 1) : udiff(slot, nextSlot) - 1;

		//Radio is turned off only if there is at least SLEEP_INACTIVE_SLOTS inactive slots between this and the next slot
		if(inactivePeriod >= SLEEP_SLOTS_THRESHOLD) {
			printf("DEBUG: Keeping radio off for the next %d inactive slots\n", inactivePeriod);
			call AMControl.stop();
		}

		return nextSlot;
	}

	//Compute difference between unsigned 8 bytes integers
	uint8_t udiff(uint8_t n1, uint8_t n2) {
		uint8_t diff = n1 - n2;
		if (diff & 0x80) {
			diff = ~diff + 1;
		}
		return diff;
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
		if(slot == JOIN_SLOT && hasJoined == FALSE) {
			printf("DEBUG: Join failed\n");
			return SYNC_SLOT;
		}

		//Reschedule for sync in next epoch
		if(slot == assignedSlot)
			return SYNC_SLOT;

		//Transmit data (if any) in the assigned slot
		return assignedSlot;
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
		uint32_t delay = call JoinReqRandom.rand16() % (SLOT_DURATION / 2);
		printf("DELAY: %lu\n", delay);
		call JoinReqDelayTimer.startOneShot(delay);
	}

	event void JoinReqDelayTimer.fired() {
		error_t status;
		if (!joinReqSending) {
			printf("DEBUG: Sending join request to master %d\n", masterAddr);
			call PacketLink.setRetries(&joinReqBuf, 0);
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
		am_addr_t slave;
		if (length != sizeof(JoinReqMsg))
			return msg;

		slave = call AMPacket.source(msg);

		printf("DEBUG: Join request received from %d\n", slave);
		
		//Send answer only if there are slots available
		if(nextFreeSlotPos < DATA_SLOTS) {
			sendJoinAnswer(slave, allocateSlot(slave));
		} else
			printf("WARNING: No slots available\n");

		return msg;
	}

	uint8_t allocateSlot(am_addr_t slave) {
		int slot;
		//Check if slot was already allocated to the node
		for(slot=0;slot<DATA_SLOTS;slot++) {
			if(allocatedSlots[slot] == slave)
				return slot+2;
		}

		allocatedSlots[nextFreeSlotPos] = slave;
		return (nextFreeSlotPos++)+2;
	}

	void sendJoinAnswer(am_addr_t slave, uint8_t slot) {
		error_t status;
		if (!joinReqSending) {
			joinAnsMsg->slot = slot;
			printf("DEBUG: Sending join answer to %d\n", slave);
			call PacketLink.setRetries(&joinAnsBuf, 0);
			status = call JoinAnsSnd.send(slave, &joinAnsBuf, sizeof(JoinAnsMsg));
			if (status == SUCCESS) {
				joinAnsSending = TRUE;
			} else {
				printf("DEBUG: Join answer to %d sending failed\n", slave);
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

		printf("DEBUG: Join completed to slot %u\n", assignedSlot);
		
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
			call PacketLink.setRetries(dataMsg, DATA_RETRY);
			call PacketLink.setRetryDelay(dataMsg, DATA_RETRY_DELAY);
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
