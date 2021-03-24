#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"flashif.h"

#define	FLASHBASE	0x00100000
#define	FLASHLEN	0x00700000
#define	LOG2FPGSZ	17
#define	FLASHPGSZ	(1<<LOG2FPGSZ)

/*
 * Intel 28F128J3A in word mode
 */

enum {
	DQ7 = 0x00800080,
	DQ6 = 0x00400040,
	DQ5 = 0x00200020,
	DQ4 = 0x00100010,
	DQ3 = 0x00080008,
	DQ2 = 0x00040004,
	DQ1 = 0x00020002,
	DQ0 = 0x00010001,
};

enum {
	FLRDM = 0x00FF00FF,		/* read */
	FLWTM = 0x00400040,		/* write/program */
	FLCLR = 0x00500050,		/* clear SR */
	FLBE1 = 0x00200020,		/* block erase */
	FLBE2 = 0x00D000D0,		/* block erase */
	FLRSR = 0x00700070,		/* read SR */
	FLDID = 0x00900090,		/* read id */
};

#define	DPRINT	if(0)print
#define	EPRINT	if(1)print

static int
intelwait(ulong *p, ulong ticks)
{
	ulong csr;

	ticks += m->ticks+1;
	while((*p & DQ7) != DQ7){
		sched();
		if(m->ticks >= ticks){
			EPRINT("flash: timed out: %8.8lux\n", *p);
			return -1;
		}
	}
	csr = *p;
	if(csr & (DQ5|DQ4|DQ3)){
		EPRINT("flash: DQ5 error: %8.8lux %8.8lux\n", p, csr);
		return 0;
	}
	return 1;
}

static int
eraseall(Flash*)
{
	return -1;	/* don't implement: the ipaq could be lost for ever */
}

static int
erasezone(Flash *f, int zone)
{
	ulong *p;
	int s;

	DPRINT("flash: erase zone %d\n", zone);
	if(zone & ~0x7F || zone == 0)
		return -1;	/* bad zone */
	p = (ulong*)((ulong)f->addr + (zone*f->erasesize));
	s = splhi();
	*p = FLBE1;
	*p = FLBE2;
	splx(s);
	if(intelwait(p, MS2TK(8*1000)) <= 0){
		*p = FLCLR;
		*p = FLRDM;	/* reset */
		f->unusable |= 1<<zone;
		return -1;
	}
	*p = FLCLR;
	*p = FLRDM;
	return 0;
}

static int
write4(Flash *f, ulong offset, void *buf, long n)
{
	ulong *p, *a, *v;
	int s;

	p = (ulong*)f->addr;
	if(((ulong)p|offset|n)&3)
		return -1;
	n >>= 2;
	a = p + (offset>>2);
	v = buf;
	for(; --n >= 0; v++, a++){
		DPRINT("flash: write %lux %lux -> %lux\n", (ulong)a, *a, *v);
		if(~*a & *v){
			EPRINT("flash: bad write: %lux %lux -> %lux\n", (ulong)a, *a, *v);
			return -1;
		}
		if(*a == *v)
			continue;	/* already set */
		s = splhi();
		*a = FLWTM;	/* program */
		*a = *v;
		splx(s);
		microdelay(8);
		if(intelwait(a, 5) <= 0){
			*a = FLCLR;
			*a = FLRDM;
			return -1;
		}
		*a = FLCLR;
		*a = FLRDM;
		if(*a != *v){
			EPRINT("flash: write %8.8lux %8.8lux -> %8.8lux failed\n", (ulong)a, *a, *v);
			return -1;
		}
	}
	return 0;
}

static int
reset(Flash *f)
{
	f->id = 0x0089;	/* can't use autoselect: might be running in flash */
	f->devid = 0;
	f->write = write4;
	f->eraseall = eraseall;
	f->erasezone = erasezone;
	f->suspend = nil;
	f->resume = nil;
	f->width = 4;
	f->erasesize = 256*1024;
	*(ulong*)f->addr = FLCLR;	/* clear status registers */
	*(ulong*)f->addr = FLRDM;	/* reset to read mode */
	return 0;
}

void
flashipaqlink(void)
{
	addflashcard("Intel28F128", reset);
}
