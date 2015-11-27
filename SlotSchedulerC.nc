//#include <Timer.h>

configuration SlotSchedulerC {
	provides interface SlotScheduler;
}
implementation {
	components SlotSchedulerP;
	components new Timer32C() as EpochTimer;
	components new Timer32C() as StartSlotTimer;
	components new Timer32C() as EndSlotTimer;

	SlotSchedulerP.EpochTimer -> EpochTimer;
	SlotSchedulerP.StartSlotTimer -> StartSlotTimer;
	SlotSchedulerP.EndSlotTimer -> EndSlotTimer;

	SlotScheduler = SlotSchedulerP;
}
