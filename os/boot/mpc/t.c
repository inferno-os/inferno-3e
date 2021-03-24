#include "boot.h"
#define	offsetof(x,y) (&((x*)0)->y)

static int xx[] = {
	offsetof(IMM, civr),
	offsetof(IMM, padir),
	offsetof(IMM, rsv14),
	offsetof(IMM, cpcr),
	offsetof(IMM, brgc4),
	offsetof(IMM, pbdir),
	offsetof(IMM, pbpar),
	offsetof(IMM, lccr),
	offsetof(IMM, rctr1),
	offsetof(IMM, rctr4),
	offsetof(IMM, rter),
	offsetof(IMM, brgc1),
	offsetof(IMM, usmod),
};
static int pop = sizeof(struct usb_regs);
