#include <printf.h>
#include "test.h"

module TestP {
	uses interface Boot;
	uses interface SplitControl as LinkCtrl;
	uses interface AMPacket;
	uses interface AMSend as LinkSnd;
	uses interface Receive as LinkRcv;
	uses interface Timer<T32khz> as DataTimer;
}
implementation {
	DataMsg* dataMsg;
	message_t dataBuf;
	uint8_t seqn = 1;

	event void Boot.booted() {
		call LinkCtrl.start();
	}

	event void DataTimer.fired() {
		dataMsg = call LinkSnd.getPayload(&dataBuf, sizeof(DataMsg));
		dataMsg->seqn = seqn++;
		printf("APP:Sending data %u\n", dataMsg->seqn);
		call LinkSnd.send(0, &dataBuf, sizeof(DataMsg));
	}

	event message_t* LinkRcv.receive(message_t *msg, void *payload, uint8_t len) {
		am_addr_t slaveAddr;
		if (len != sizeof(DataMsg))
			return msg;

		slaveAddr = call AMPacket.source(msg);

		dataMsg = (DataMsg*) payload;
		printf("APP:Arrived data %u from node %d\n", dataMsg->seqn, slaveAddr);

		return msg;
	}

	event void LinkCtrl.startDone(error_t error) {
		if(TOS_NODE_ID != 1) {
			call DataTimer.startOneShot(500);
		}
	}

	event void LinkCtrl.stopDone(error_t error) {

	}

	event void LinkSnd.sendDone(message_t* msg, error_t error) {
		call DataTimer.startOneShot(500);
	}
}
