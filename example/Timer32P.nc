#include <Timer.h>
configuration Timer32P {
	provides interface Timer<T32khz> as Timer32khz[uint8_t num];
}
implementation
{
	components new Alarm32khz32C(); 
	components new AlarmToTimerC(T32khz);
	components new VirtualizeTimerC(T32khz, uniqueCount("Timer32khz"));

	
	VirtualizeTimerC.TimerFrom -> AlarmToTimerC;
	AlarmToTimerC.Alarm -> Alarm32khz32C;

	Timer32khz = VirtualizeTimerC.Timer;
}
