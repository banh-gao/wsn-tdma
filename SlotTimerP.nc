#include <Timer.h>
#include <printf.h>

#define EPOCH_DURATION (SLOT_DURATION*N_SLOTS)

module SlotTimerP {
	provides interface SlotTimer;

	uses {
		interface Timer<T32khz> as EpochTimer;
		interface Timer<T32khz> as StartSlotTimer;
		interface Timer<T32khz> as EndSlotTimer;
	}
}

implementation {

	uint32_t epoch_reference_time;
	uint8_t schedSlot;

	command void SlotTimer.setEpochTime(uint32_t reference_time) {
		epoch_reference_time = reference_time;
		//Immediately restart epoch timer to be as close as possible to the reference_time
		call EpochTimer.startPeriodic(EPOCH_DURATION);
	}

	command uint32_t SlotTimer.getEpochTime() {
		return epoch_reference_time;
	}

	event void EpochTimer.fired() {
		epoch_reference_time += EPOCH_DURATION;
	}

	command void SlotTimer.scheduleSlot(uint8_t slotId) {
		if(!call EpochTimer.isRunning()) {
			printf("ERROR: Reference epoch not set!\n");
			return;
		} else if(slotId >= N_SLOTS) {
			printf("ERROR: Invalid slot ID %d!\n", slotId);
			return;
		}
		
		schedSlot = slotId;

		//If epoch timer has already passed the slot beginning time, the the slot is scheduled for the next epoch
		if(call EpochTimer.getNow() > epoch_reference_time + (SLOT_DURATION * slotId))
			call StartSlotTimer.startOneShotAt(epoch_reference_time + EPOCH_DURATION, SLOT_DURATION * slotId);
		else
			call StartSlotTimer.startOneShotAt(epoch_reference_time, SLOT_DURATION * slotId);
	}

	event void StartSlotTimer.fired() {
		call EndSlotTimer.startOneShot(SLOT_DURATION);
		signal SlotTimer.slotStarted(schedSlot);
	}

	event void EndSlotTimer.fired() {
		signal SlotTimer.slotEnded(schedSlot);
	}
}
