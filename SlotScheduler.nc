interface SlotScheduler {
	command error_t start(uint32_t epoch_time, uint8_t firstSlot);
	command error_t stop();
	command void syncEpochTime(uint32_t reference_time);
	command uint32_t getEpochTime();
	command uint8_t getScheduledSlot();
	event void slotStarted(uint8_t slotId);
	event uint8_t slotEnded(uint8_t slotId);
}
