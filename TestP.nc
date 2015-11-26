#include <printf.h>

module TestP {
	uses interface Boot;
	uses interface SplitControl as MasterCtrl;
	uses interface Receive as MasterRcv;
}
implementation
{
	
	event void Boot.booted() {
		call MasterCtrl.start();
	}

	event message_t* MasterRcv.receive(message_t *msg, void *payload, uint8_t len) {

	}

	event void MasterCtrl.startDone(error_t error) {

	}

	event void MasterCtrl.stopDone(error_t error) {

	}
}
