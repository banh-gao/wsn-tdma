#include <printf.h>

typedef nx_struct {
	nx_uint16_t seqn;
} DataMsg;

module TestP {
	uses interface Boot;
	uses interface TDMALink;
	uses interface AMSend as TDMALinkSnd;
	uses interface Receive as TDMALinkRcv;
	uses interface AMPacket;
	uses interface Timer<T32khz> as DataTimer;
}
implementation {
	DataMsg* dataMsg;
	message_t dataBuf;
	uint8_t seqn = 1;

	event void Boot.booted() {
		if(TOS_NODE_ID == 1)
			call TDMALink.startMaster();
		else
			call TDMALink.startSlave();
	}

	event void TDMALink.startDone(error_t error) {
		if(!call TDMALink.isMaster()) {
			call DataTimer.startOneShot(500);
		}
	}

	event void DataTimer.fired() {
		error_t status;
		dataMsg = call TDMALinkSnd.getPayload(&dataBuf, sizeof(DataMsg));
		dataMsg->seqn = seqn++;
		printf("APP: Preparing data %u from node %d\n", dataMsg->seqn, TOS_NODE_ID);
		status = call TDMALinkSnd.send(0, &dataBuf, sizeof(DataMsg));
		if (status != SUCCESS) {
			printf("APP: Data sending failed\n");
		}
	}

	event message_t* TDMALinkRcv.receive(message_t *msg, void *payload, uint8_t len) {
		am_addr_t slaveAddr;
		if (len != sizeof(DataMsg))
			return msg;

		slaveAddr = call AMPacket.source(msg);

		dataMsg = (DataMsg*) payload;
		printf("APP: Arrived data %u from node %d\n", dataMsg->seqn, slaveAddr);

		return msg;
	}

	event void TDMALinkSnd.sendDone(message_t* msg, error_t error) {
		if (error != SUCCESS) {
			printf("APP: Data transmission failed\n");
		}
		//call DataTimer.startOneShot(500);
	}

	event void TDMALink.stopDone(error_t error) {
	}
}
