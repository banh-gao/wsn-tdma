COMPONENT = TestC
CFLAGS += -DCC2420_DEF_RFPOWER=31
CFLAGS += -DCC2420_DEF_CHANNEL=18
CFLAGS += -DPACKET_LINK
#CFLAGS += -DLOW_POWER_LISTENING
CFLAGS += -DCC2420_HW_ACKNOWLEDGEMENTS 
CFLAGS += -DCC2420_HW_ADDRESS_RECOGNITION
CFLAGS += -DTOSH_DATA_LENGTH=30

CFLAGS += -I$(TINYOS_ROOT_DIR)/tos/lib/printf
CFLAGS += -DNEW_PRINTF_SEMANTICS

#Define the duration of a single time slot (in milliseconds)
CFLAGS += -DSLOT_DURATION=20
#Define the amount of available data slots (up to 254)
CFLAGS += -DMAX_SLAVES=10
#Uncomment to enable debug messages
#CFLAGS += -DDEBUG

include $(TINYOS_ROOT_DIR)/Makefile.include

