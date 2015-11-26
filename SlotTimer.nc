interface SlotTimer {
	command void setEpochTime(uint32_t reference_time);
	command uint32_t getEpochTime();
	command void scheduleSlot(uint8_t slotId);
	event void slotStarted(uint8_t slotId);
	event void slotEnded(uint8_t slotId);
}
