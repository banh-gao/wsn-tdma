#include <Timer.h>
#include <printf.h>
#include "messages.h"

//Sync beacons lost before entering in sync mode
#define RESYNC_THRESHOLD 5

//Minimum inactive slots to enter power saving
#define SLEEP_SLOTS_THRESHOLD 1

//Data ACK
#define DATA_RETRY 1
#define DATA_RETRY_DELAY SLOT_DURATION/4


#define SYNC_SLOT 0
#define JOIN_SLOT 1
#define TOTAL_SLOTS (MAX_SLAVES+2)
#define LAST_SLOT (TOTAL_SLOTS-1)
#define SLOTS_UNAVAILABLE 0

module TDMALinkP {
	provides interface TDMALinkControl as Control;
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
	am_addr_t allocatedSlots[MAX_SLAVES];
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
	message_t syncBuf;

	// Join request packet
	message_t joinReqBuf;
	JoinReqMsg* joinReqMsg;

	// Join answer packet
	message_t joinAnsBuf;
	JoinAnsMsg* joinAnsMsg;

	void startSlotTask();

	command error_t Control.startMaster() {
		isMaster = TRUE;
		joinReqMsg = call JoinReqSnd.getPayload(&joinAnsBuf, sizeof(JoinReqMsg));
		joinAnsMsg = call JoinAnsSnd.getPayload(&joinAnsBuf, sizeof(JoinAnsMsg));

		//Start master in SLOTTED MODE (radio managed by scheduler)
		call SlotScheduler.start(0, SYNC_SLOT);

		#ifdef DEBUG
		printf("DEBUG: Master node %u started [SLAVE SLOTS:%u | SLOT DURATION:%ums | EPOCH DURATION:%ums]\n", TOS_NODE_ID, MAX_SLAVES, SLOT_DURATION, (MAX_SLAVES + 2) * SLOT_DURATION);
		#endif

		return SUCCESS;
	}

	command error_t Control.startSlave() {
		isMaster = FALSE;

		#ifdef DEBUG
		printf("DEBUG: Slave node %u started\n", TOS_NODE_ID);
		printf("DEBUG: Entering SYNC MODE\n");
		#endif

		//Start slave in SYNC MODE (radio always on)
		syncMode = TRUE;
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
		#ifdef DEBUG
		printf("DEBUG: Slot %d started\n", slot);
		#endif

		//Turn radio on, if it's already on execute slot task immediately
		if(call AMControl.start() == EALREADY)
			startSlotTask();
	}

	event void AMControl.startDone(error_t err) {
		#ifdef DEBUG		
		printf("DEBUG: Radio ON\n");
		#endif

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
		
		#ifdef DEBUG
		printf("DEBUG: Slot %d ended\n", slot);
		#endif

		nextSlot = (isMaster) ? getNextMasterSlot(slot) : getNextSlaveSlot(slot);

		//In sync mode the radio is always on and scheduler is not running
		if(syncMode) {
			#ifdef DEBUG
			printf("DEBUG: Entering SYNC MODE\n");
			#endif
			call SlotScheduler.stop();
			return SYNC_SLOT;
		}

		//Count inactive slots
		if(slot < nextSlot) //next slot in same epoch
			inactivePeriod = nextSlot - slot - 1;
		else //next slot in next epoch
			inactivePeriod = TOTAL_SLOTS - (slot - nextSlot) - 1;

		//Special case with last slot immediately followed by first slot of next epoch
		if(slot == LAST_SLOT && nextSlot == SYNC_SLOT)
			inactivePeriod = 0;

		//Radio is turned off only if the number of inactive slots between this and the next slot is >= of a threshold
		if(inactivePeriod >= SLEEP_SLOTS_THRESHOLD) {
			#ifdef DEBUG
			printf("DEBUG: Keeping radio off for the next %u inactive slots\n", inactivePeriod);
			#endif
			call AMControl.stop();
		}

		return nextSlot;
	}

	uint8_t getNextMasterSlot(uint8_t slot) {
		//Listen for join requests
		if(slot == SYNC_SLOT)
			return JOIN_SLOT;

		//Schedule for next allocated data slot
		if(slot < nextFreeSlotPos + 1)
			return slot+1;

		//No more allocated data slots to listen to, schedule for next epoch sync beaconing
		return SYNC_SLOT;
	}

	uint8_t getNextSlaveSlot(uint8_t slot) {
		if(slot == SYNC_SLOT && syncReceived == FALSE) {
			missedSyncCount++;
			#ifdef DEBUG
			printf("DEBUG: Missed synchronization beacon %d/%d\n", missedSyncCount, RESYNC_THRESHOLD);
			#endif

			//Go to resync mode
			if(missedSyncCount >= RESYNC_THRESHOLD) {
				syncMode = TRUE;
				return SYNC_SLOT;
			}
		}

		//If node needs to join try to join in next slot
		if(slot == SYNC_SLOT && hasJoined == FALSE)
			return JOIN_SLOT;

		//If join failed, retry in the next epoch
		if(slot == JOIN_SLOT && hasJoined == FALSE) {
			#ifdef DEBUG
			printf("DEBUG: Missing join answer\n");
			#endif
			return SYNC_SLOT;
		}

		//Reschedule for sync in next epoch
		if(slot == assignedSlot)
			return SYNC_SLOT;

		//Transmit data (if any) in the assigned slot
		if(dataReady == TRUE)
			return assignedSlot;
		else
			return SYNC_SLOT;
	}

	event void AMControl.stopDone(error_t err) {
		#ifdef DEBUG
		printf("DEBUG: Radio OFF\n");
		#endif

		//FOR CONTROL INTERFACE: Signal that component has stopped
		if(isStarted == FALSE)
			signal Control.stopDone(SUCCESS);
	}

	void sendSyncBeacon() {
			#ifdef DEBUG
			printf("DEBUG: Sending synchronization beacon\n");
			#endif
			call PacketLink.setRetries(&syncBuf, 0);
			call SyncSnd.send(AM_BROADCAST_ADDR, &syncBuf, sizeof(SyncMsg), call SlotScheduler.getEpochTime());
	}

	event void SyncSnd.sendDone(message_t* msg, error_t error) {
		#ifdef DEBUG
		if (error != SUCCESS)
			printf("DEBUG: Synchronization beacon transmission failed\n");
		#endif
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
			#ifdef DEBUG
			printf("DEBUG: Local scheduler started and synchronized with master scheduler\n");
			printf("DEBUG: Entering SLOTTED MODE\n");	
			#endif
		} else {
			//Synchronize the running scheduler
			call SlotScheduler.syncEpochTime(ref_time);
			#ifdef DEBUG
			printf("DEBUG: Local scheduler synchronized with master scheduler\n");
			#endif
		}

		syncReceived = TRUE;
		missedSyncCount = 0;

		return msg;
	}

	void sendJoinRequest() {
		//Introduce a delay to reduce collision likelihood among join requests and answers
		uint32_t delay = call JoinReqRandom.rand16() % (SLOT_DURATION / 2);
		call JoinReqDelayTimer.startOneShot(delay);
	}

	event void JoinReqDelayTimer.fired() {
		#ifdef DEBUG
		printf("DEBUG: Sending join request to master %d\n", masterAddr);
		#endif
		call PacketLink.setRetries(&joinReqBuf, 0);
		call JoinReqSnd.send(masterAddr, &joinReqBuf, sizeof(JoinReqMsg));
	}

	event void JoinReqSnd.sendDone(message_t* msg, error_t error) {
		#ifdef DEBUG
		if (error != SUCCESS)
			printf("DEBUG: Join request transmission failed\n");
		#endif
	}

	event message_t* JoinReqRcv.receive(message_t* msg, void* payload, uint8_t length) {		
		am_addr_t slave;
		uint8_t allocSlot;
		if (length != sizeof(JoinReqMsg))
			return msg;

		slave = call AMPacket.source(msg);
		#ifdef DEBUG
		printf("DEBUG: Received join request from %d\n", slave);
		#endif

		allocSlot = allocateSlot(slave);

		//Send answer only if there are slots available
		if(allocSlot != SLOTS_UNAVAILABLE)
			sendJoinAnswer(slave, allocSlot);
		else
			printf("WARNING: No slots available for slave %u\n", slave);

		return msg;
	}

	uint8_t allocateSlot(am_addr_t slave) {
		int slot;
		//Check if slot was already allocated to the slave
		for(slot=0;slot<MAX_SLAVES;slot++) {
			if(allocatedSlots[slot] == slave)
				return slot+2;
		}

		if(nextFreeSlotPos >= MAX_SLAVES)
			return SLOTS_UNAVAILABLE;

		allocatedSlots[nextFreeSlotPos] = slave;
		return (nextFreeSlotPos++) + 2;
	}

	void sendJoinAnswer(am_addr_t slave, uint8_t slot) {
		joinAnsMsg->slot = slot;
		#ifdef DEBUG
		printf("DEBUG: Sending join answer to %d\n", slave);
		#endif
		call PacketLink.setRetries(&joinAnsBuf, 0);
		call JoinAnsSnd.send(slave, &joinAnsBuf, sizeof(JoinAnsMsg));
	}

	event void JoinAnsSnd.sendDone(message_t* msg, error_t error) {
		#ifdef DEBUG
		if (error != SUCCESS)
			printf("DEBUG: Join answer transmission failed\n");
		#endif
	}

	event message_t* JoinAnsRcv.receive(message_t* msg, void* payload, uint8_t length) {
		if (length != sizeof(JoinAnsMsg))
			return msg;

		joinAnsMsg = (JoinAnsMsg*) payload;

		assignedSlot = joinAnsMsg->slot;

		#ifdef DEBUG
		printf("DEBUG: Join completed to slot %u\n", assignedSlot);
		#endif
		
		hasJoined = TRUE;

		//FOR CONTROL INTERFACE: Signal that slave is ready
		isStarted = TRUE;
		signal Control.startDone(SUCCESS);

		return msg;
	}

	///////////////////////////////////////////////////////////////////////////////////
	////////////////////// DATA TRANSMISSION INTERFACE FOR SLAVES /////////////////////

	void sendData() {
		if(!dataReady)
			return;

		#ifdef DEBUG
		printf("DEBUG: Transmitting data\n");
		#endif
		call PacketLink.setRetries(dataMsg, DATA_RETRY);
		call PacketLink.setRetryDelay(dataMsg, DATA_RETRY_DELAY);
		call DataSnd.send(masterAddr, dataMsg, dataLen);
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
