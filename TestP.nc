#include <printf.h>

module TestP {
	uses interface Boot;
	uses interface SplitControl as LinkCtrl;
	uses interface AMSend as LinkSnd;
	uses interface Receive as LinkRcv;
}
implementation
{
	
	event void Boot.booted() {
			call LinkCtrl.start();
	}

	event message_t* LinkRcv.receive(message_t *msg, void *payload, uint8_t len) {
		return msg;
	}

	event void LinkCtrl.startDone(error_t error) {

	}

	event void LinkCtrl.stopDone(error_t error) {

	}

	event void LinkSnd.sendDone(message_t* msg, error_t error) {

	}
}
