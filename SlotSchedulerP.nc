#include <Timer.h>

generic module SlotSchedulerP(uint32_t slotDuration, uint8_t maxSlots) {
	provides interface SlotScheduler;

	uses {
		interface Timer<T32khz> as EpochTimer;
		interface Timer<T32khz> as StartSlotTimer;
		interface Timer<T32khz> as EndSlotTimer;
	}
} implementation {

	//Defined at compile time
	uint32_t epochDuration = slotDuration * maxSlots;

	bool isStarted = FALSE;
	uint32_t epoch_reference_time;
	uint8_t schedSlot;

	command error_t SlotScheduler.start(uint32_t epoch_time, uint8_t firstSlot) {
		if(isStarted == TRUE) {
			return EALREADY;
		} if(firstSlot >= maxSlots)
			return FAIL;

		epochDuration = slotDuration * maxSlots;

		isStarted = TRUE;
		schedSlot = firstSlot;
		epoch_reference_time = epoch_time;

		call StartSlotTimer.startOneShotAt(epoch_time, slotDuration * firstSlot);
		call EpochTimer.startPeriodicAt(epoch_time, epochDuration);

		return SUCCESS;
	}

	command bool SlotScheduler.isRunning() {
		return isStarted;
	}

	command error_t SlotScheduler.stop() {
		bool wasStarted = isStarted;
		call StartSlotTimer.stop();
		call EpochTimer.stop();
		isStarted = FALSE;
		return (wasStarted) ? EALREADY : SUCCESS;
	}

	command void SlotScheduler.syncEpochTime(uint32_t reference_time) {
		epoch_reference_time = reference_time;
		call EpochTimer.startPeriodicAt(reference_time, epochDuration);
	}

	command uint32_t SlotScheduler.getEpochTime() {
		return epoch_reference_time;
	}

	command uint8_t SlotScheduler.getScheduledSlot() {
		return schedSlot;
	}

	event void EpochTimer.fired() {
		epoch_reference_time += epochDuration;
	}

	event void StartSlotTimer.fired() {
		call EndSlotTimer.startOneShot(slotDuration);
		signal SlotScheduler.slotStarted(schedSlot);
	}

	event void EndSlotTimer.fired() {
		uint8_t nextSlot = signal SlotScheduler.slotEnded(schedSlot);

		//If scheduler is not running don't schedule other slots
		if(!isStarted)
			return;

		if (nextSlot > schedSlot || (schedSlot == maxSlots-1 && nextSlot == 0)) {
			schedSlot = nextSlot;
			call StartSlotTimer.startOneShotAt(epoch_reference_time, slotDuration * schedSlot);
		} else {
			schedSlot = nextSlot;
			call StartSlotTimer.startOneShotAt(epoch_reference_time + epochDuration, slotDuration * schedSlot);
		}
	}
}
