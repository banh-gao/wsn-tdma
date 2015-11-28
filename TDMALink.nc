interface TDMALink {
	command error_t startMaster();
	command error_t startSlave();
	command error_t stop();
	command bool isMaster();
	event void startDone(error_t error);
	event void stopDone(error_t error);
}
