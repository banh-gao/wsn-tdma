#include <Timer.h>
#include "messages.h"

configuration SlotTimerC {
	provides interface SlotTimer;
}
implementation {
	components SlotTimerP;
	components new Timer32C() as EpochTimer;
	components new Timer32C() as StartSlotTimer;
	components new Timer32C() as EndSlotTimer;

	SlotTimerP.EpochTimer -> EpochTimer;
	SlotTimerP.StartSlotTimer -> StartSlotTimer;
	SlotTimerP.EndSlotTimer -> EndSlotTimer;

	SlotTimer = SlotTimerP;
}
