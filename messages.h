#ifndef MESSAGES_H
#define MESSAGES_H

////// TDMA time tuning ///////
#define SECOND 32768L
#define SLOT_DURATION (SECOND)
#define N_SLOTS 12
///////////////////////////////

#define SYNC_SLOT 0
#define JOIN_SLOT 1

enum {
	AM_SYNCMSG = 130,
	AM_JOINREQMSG = 131,
	AM_JOINANSMSG = 132,
	AM_DATAMSG = 133
};

typedef nx_struct {
} SyncMsg;

typedef nx_struct {
} JoinReqMsg;

typedef nx_struct {
	nx_uint8_t slot;
} JoinAnsMsg;

typedef nx_struct {
	nx_uint16_t seqn;
} DataMsg;

#endif
