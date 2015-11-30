generic configuration SlotSchedulerC(uint32_t slotDuration, uint8_t maxSlotId) {
	provides interface SlotScheduler;
} implementation {
	components new SlotSchedulerP(slotDuration, maxSlotId);
	components new Timer32C() as EpochTimer;
	components new Timer32C() as StartSlotTimer;
	components new Timer32C() as EndSlotTimer;

	SlotSchedulerP.EpochTimer -> EpochTimer;
	SlotSchedulerP.StartSlotTimer -> StartSlotTimer;
	SlotSchedulerP.EndSlotTimer -> EndSlotTimer;

	SlotScheduler = SlotSchedulerP;
}
