#ifndef MESSAGES_H
#define MESSAGES_H

enum {
	AM_BEACONMSG = 130,
};

typedef nx_struct BeaconMsg {
	nx_uint16_t seqn;
} BeaconMsg;

#endif
