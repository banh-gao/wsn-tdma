generic configuration SlotSchedulerC(uint32_t slotDuration, uint8_t maxSlotId) {
	provides interface SlotScheduler;
} implementation {
	//Slot duration is multiplied by 32 because of the usage of 32kHz timers where 1ms = 32 ticks
	components new SlotSchedulerP(slotDuration * 32, maxSlotId);
	components new Timer32C() as EpochTimer;
	components new Timer32C() as StartSlotTimer;
	components new Timer32C() as EndSlotTimer;

	SlotSchedulerP.EpochTimer -> EpochTimer;
	SlotSchedulerP.StartSlotTimer -> StartSlotTimer;
	SlotSchedulerP.EndSlotTimer -> EndSlotTimer;

	SlotScheduler = SlotSchedulerP;
}
