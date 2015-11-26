#include <Timer.h>
#include "messages.h"

module ExampleP {
	uses { 
		interface Boot;
		interface Leds;
		interface Timer<T32khz> as TimerBeaconTx;
		interface Timer<T32khz> as TimerOn;
		interface Timer<T32khz> as TimerOff;
    	interface TimeSyncAMSend<T32khz, uint32_t> as SendBeacon;
        interface TimeSyncPacket<T32khz, uint32_t> as TSPacket;
    	interface Receive as ReceiveBeacon;
		interface SplitControl as AMControl;
	}
}
implementation {

#define SECOND 32768L
#define EPOCH_DURATION (SECOND*2)
#define IS_MASTER (TOS_NODE_ID==1)
#define SLOT_DURATION (SECOND/8)
#define ON_DURATION (SECOND/16)
#define N_BLINKS 3
	
	uint32_t epoch_reference_time;
	
	// When to turn on the led the next time.
	// Relative to the epoch_reference_time
	uint32_t next_on;  
	
	int slot;	// current slot number
	int epoch;	// current epoch number
	
	message_t beacon;

	void start_epochs();

	event void Boot.booted() {
		// turn on the radio
		call AMControl.start();
	}

	event void AMControl.startDone(error_t err) {
		if (IS_MASTER) {
			// simple delay to make sure all the slaves are up and running when we send the beacon
			call TimerBeaconTx.startOneShot(3*SECOND);
		}
	}

	event void TimerBeaconTx.fired() {
		// initializing the reference time to now
		epoch_reference_time = call TimerBeaconTx.getNow();
		call SendBeacon.send(AM_BROADCAST_ADDR, &beacon, sizeof(BeaconMsg), epoch_reference_time);
		start_epochs();
	}
	
	event message_t* ReceiveBeacon.receive(message_t* msg, void* payload, uint8_t len){
		// we have to check whether the packet is valid before retrieving the reference time
		if (call TSPacket.isValid(msg) && len == sizeof(BeaconMsg)) {
			// get the epoch start time (converted to our local time reference frame)
			epoch_reference_time = call TSPacket.eventTime(msg);
			// turn off the radio
			call AMControl.stop();
			start_epochs();
		}
		return msg;
	}

	// initialise and start the first epoch
	void start_epochs() {
		epoch = 1;
		slot = 0;
		next_on = EPOCH_DURATION;
		// setting a timer to turn on the leds
		call TimerOn.startOneShotAt(epoch_reference_time, EPOCH_DURATION);
		// setting another timer to turn off the leds
		//call TimerOff.startOneShotAt(epoch_reference_time, EPOCH_DURATION + ON_DURATION);
	}

	// compute the next_on time, update the reference if needed
	void compute_next_slot() {
		if (slot == 0)
			// new epoch started, now we can update the reference time 
			epoch_reference_time += EPOCH_DURATION;

		if (slot < N_BLINKS-1) {
			// proceed to the next slot
			slot++;
			// compute the relative led on time based on the slot number
			next_on = slot*SLOT_DURATION;
		}
		else {
			// it was the last slot of the epoch, prepare for the next epoch
			slot = 0;
			epoch ++;
			// next time to turn on the leds is exactly the start of the next epoch
			next_on = EPOCH_DURATION;
			// note that we cannot update the epoch_reference_time now as
			// it would point to the future and we cannot use a reference
			// in the future when setting the timers!
		}
	}

	event void TimerOn.fired() {
		call Leds.set(epoch);
		// set the off timer usting the current values of reference and next_on
		call TimerOff.startOneShotAt(epoch_reference_time, next_on + ON_DURATION);

		// update the values
		compute_next_slot();

		// set on timer useing the new values
		call TimerOn.startOneShotAt(epoch_reference_time, next_on);
	}
	event void TimerOff.fired() {
		call Leds.set(0);
	}
	
	event void SendBeacon.sendDone(message_t* msg, error_t err) {
		call AMControl.stop();
	}
	
	event void AMControl.stopDone(error_t err) {}
}
