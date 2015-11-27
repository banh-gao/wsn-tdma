#ifndef MESSAGES_H
#define MESSAGES_H

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

#endif
