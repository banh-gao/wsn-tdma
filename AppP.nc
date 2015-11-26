#include <printf.h>

module AppP {
	uses interface Boot;
	uses interface SlotTimer;
}
implementation
{
	
	event void Boot.booted() {
		call SlotTimer.setReferenceEpoch(0);
		call SlotTimer.scheduleSlot(0);
	}

	event void SlotTimer.slotStarted(uint8_t slotId) {
		printf("Slot %d available\n", slotId);
	}

	event void SlotTimer.slotEnded(uint8_t slotId) {
		printf("Slot %d ended\n", slotId);
		call SlotTimer.scheduleSlot((slotId + 1) % 11);
	}
}
