#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"

#include	"../port/error.h"

#include <image.h>
#include <memimage.h>

typedef struct Ptrevent Ptrevent;

struct Ptrevent {
	int	x;
	int	y;
	int	b;
	ulong	msec;
};

enum {
	Nevent = 16	/* enough for some */
};

static struct {
	int	rd;
	int	wr;
	Ptrevent	clicks[Nevent];
	Rendez r;
	int	full;
	int	put;
	int	get;
} ptrq;

Pointer	(*mouseconsumer)(void) = mouseconsume;	/* picked up by devcons.c */

void
mouseproduce(Pointer m)
{
	int lastb;
	Ptrevent e;

	e.x = m.x;
	e.y = m.y;
	e.b = m.b;
	e.msec = TK2MS(MACHP(0)->ticks);
	lastb = mouse.b;
	mouse.x = m.x;
	mouse.y = m.y;
	mouse.b = m.b;
	/* mouse.msec = e.msec; */
	if(!ptrq.full && lastb != m.b){
		ptrq.clicks[ptrq.wr] = e;
		if(++ptrq.wr == Nevent)
			ptrq.wr = 0;
		if(ptrq.wr == ptrq.rd)
			ptrq.full = 1;
	}
	mouse.modify = 1;
	ptrq.put++;
	wakeup(&ptrq.r);
	drawactive(1);
}

static int
ptrqnotempty(void*)
{
	return ptrq.full || ptrq.put != ptrq.get;
}

Pointer
mouseconsume(void)
{
	Pointer m;
	Ptrevent e;

	sleep(&ptrq.r, ptrqnotempty, 0);
	ptrq.full = 0;
	ptrq.get = ptrq.put;
	if(ptrq.rd != ptrq.wr){
		e = ptrq.clicks[ptrq.rd];
		if(++ptrq.rd >= Nevent)
			ptrq.rd = 0;
		memset(&m, 0, sizeof(m));
		m.x = e.x;
		m.y = e.y;
		m.b = e.b;
		/* m.msec = e.msec; */
	}else
		m = mouse;
	return m;
}
