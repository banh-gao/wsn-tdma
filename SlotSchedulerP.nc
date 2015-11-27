#include <Timer.h>

////// TDMA time params ///////
#ifndef SLOT_DURATION
#define SECOND 32768L
#define SLOT_DURATION (SECOND/10)
#endif

#ifndef N_SLOTS
#define N_SLOTS 10
#endif
///////////////////////////////

#define EPOCH_DURATION (SLOT_DURATION * N_SLOTS)

module SlotSchedulerP {
	provides interface SlotScheduler;

	uses {
		interface Timer<T32khz> as EpochTimer;
		interface Timer<T32khz> as StartSlotTimer;
		interface Timer<T32khz> as EndSlotTimer;
	}
}

implementation {

	bool isStarted = FALSE;
	uint32_t epoch_reference_time;
	uint8_t schedSlot;

	command error_t SlotScheduler.start(uint32_t epoch_time, uint8_t firstSlot) {
		if(isStarted == TRUE)
			return EALREADY;
		if(firstSlot >= N_SLOTS)
			return FAIL;

		schedSlot = firstSlot;
		call StartSlotTimer.startOneShotAt(epoch_time, SLOT_DURATION * firstSlot);

		epoch_reference_time = epoch_time;
		call EpochTimer.startPeriodicAt(epoch_time, EPOCH_DURATION);

		isStarted = TRUE;
		return SUCCESS;
	}

	command void SlotScheduler.syncEpochTime(uint32_t reference_time) {
		call EpochTimer.startPeriodicAt(reference_time, EPOCH_DURATION);
		epoch_reference_time = reference_time;
	}

	command uint32_t SlotScheduler.getEpochTime() {
		return epoch_reference_time;
	}

	command uint8_t SlotScheduler.getScheduledSlot() {
		return schedSlot;
	}

	event void EpochTimer.fired() {
		epoch_reference_time += EPOCH_DURATION;
	}

	event void StartSlotTimer.fired() {
		call EndSlotTimer.startOneShot(SLOT_DURATION);
		signal SlotScheduler.slotStarted(schedSlot);
	}

	event void EndSlotTimer.fired() {
		uint8_t nextSlot = signal SlotScheduler.slotEnded(schedSlot);

		if (nextSlot > schedSlot) {
			schedSlot = nextSlot;
			call StartSlotTimer.startOneShotAt(epoch_reference_time, SLOT_DURATION * schedSlot);
		} else {
			schedSlot = nextSlot;
			call StartSlotTimer.startOneShotAt(epoch_reference_time + EPOCH_DURATION, SLOT_DURATION * schedSlot);
		}
	}
}
