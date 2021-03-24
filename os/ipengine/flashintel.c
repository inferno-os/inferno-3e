#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	"flashif.h"

#define FLASHMEM	0xfff80000
#define FLASHPGSZ	0x40000
#define FLASHBKSZ	(FLASHPGSZ>>2)
#define LOG2FPGSZ	18
#define FLASHEND	(FLASHMEM+FLASHPGSZ)
#define SYSREG0	0x78
#define SYSREG1	0x878

/* Intel28F016SA flash memory family (8SA and (DD)32SA as well) in byte mode */

/*
  * word mode does not work - a 2 byte write to a location results in the lower address 
  * byte being unchanged (4 byte writes are even stranger) and no indication of error.
  * Perhaps the bridge is interfering with the address lines.
  * Looks like the BIOS code doesn't use it either but that's not certain.
  */

enum {
	DQ7 = 0x80,
	DQ6 = 0x40,
	DQ5 = 0x20,
	DQ4 = 0x10,
	DQ3 = 0x08,
	DQ2 = 0x04,
	DQ1 = 0x02,
	DQ0 = 0x01,
};

enum {
	FLRDM = 0xFF,		/* read */
	FLWTM = 0x10,	/* write/program */
	FLCLR = 0x50,		/* clear SR */
	FLBE1 = 0x20,		/* block erase */
	FLBE2 = 0xD0,		/* block erase */
	FLRSR = 0x70,		/* read SR */
	FLDID = 0x90,		/* read id */
};

#define	DPRINT	if(0)print
#define	EPRINT	if(1)print

static int
intelwait(uchar *p, ulong ticks)
{
	uchar csr;

	ticks += m->ticks+1;
         while((*p & DQ7) != DQ7){
		sched();
		if(m->ticks >= ticks){
			EPRINT("flash: timed out: %8.8lux\n", (ulong)*p);
			return -1;
		}
	}
	csr = *p;
	if(csr & (DQ5|DQ4|DQ3)){
		EPRINT("flash: DQ5 error: %8.8lux %8.8lux\n", p, (ulong)csr);
		return 0;
	}
	return 1;
}

static int
eraseall(Flash *f)
{
	uchar r;
	uchar *p;
	int i, j, s;

	DPRINT("flash: erase all\n");
	for (i = 0; i < 8; i++) {		/* page */
		/* set page */
		r = inb(SYSREG0);
		r &= 0x8f;
		r |= i<<4;
		outb(SYSREG0, r);
		p = (uchar *)f->addr;
		for (j = 0; j < 4; j++) {	/* block within page */
			DPRINT("erasing page %d block %d addr %lux\n", i, j, p);
			s = splhi();
			*p = FLBE1;
			*p = FLBE2;
			splx(s);
			if(intelwait(p, MS2TK(16*1000)) <= 0){
				*p = FLCLR;	/* clr SR */
				*p = FLRDM;	/* read mode */
				f->unusable = ~0;
				return -1;
			}
			*p = FLCLR;
			*p = FLRDM;
			p += FLASHPGSZ>>2;
		}
	}
	return 0;
}

static int
erasezone(Flash *f, int zone)
{
	uchar r;
	uchar *p;
	int s, pg, blk;

	DPRINT("flash: erase zone %d\n", zone);
	if(zone & ~31) {
		EPRINT("flash: bad erasezone %d\n", zone);
		return -1;	/* bad zone */
	}
	pg = zone>>2;
	blk = zone&3;
	/* set page */
	r = inb(SYSREG0);
	r &= 0x8f;
	r |= pg<<4;
	outb(SYSREG0, r);
	p = (uchar *)f->addr + blk*(FLASHPGSZ>>2);
	DPRINT("erasing zone %d pg %d blk %d addr %lux\n", zone, pg, blk, p);
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
writex(Flash *f, ulong offset, void *buf, long n)
{
	int i, s;
	uchar r;
	ulong pg, o;
	long m;
	uchar *a, *v = buf;

	DPRINT("flash: writex\n");
	pg = offset>>LOG2FPGSZ;
	o = offset&(FLASHPGSZ-1);
	while (n > 0) {
		if (pg < 0 || pg > 7) {
			EPRINT("flash: bad write %ld %ld\n", offset, n);
			return -1;
		}
		/* set page */
		r = inb(SYSREG0);
		r &= 0x8f;
		r |= pg<<4;
		outb(SYSREG0, r);
		if (o+n > FLASHPGSZ)
			m = FLASHPGSZ-o;
		else
			m = n;
		a = (uchar *)f->addr + o;
		DPRINT("flash: write page %ld offset %lux buf %lux n %d\n", pg, o, v-(uchar*)buf, m);
		for (i = 0; i < m; i++, v++, a++) {
			if (~*a & *v) {
				EPRINT("flash: bad write: %lux %lux -> %lux\n", (ulong)a, (ulong)*a, (ulong)*v);
				return -1;
			}
			if (*a == *v)
				continue;
			s = splhi();
			*a = FLWTM;	/* program */
			*a = *v;
			splx(s);
			microdelay(8);
			if(intelwait(a, 5) <= 0){
				*a = FLCLR;	/* clr SR */
				*a = FLRDM;	/* read mode */
				f->unusable = ~0;
				return -1;
			}
			*a = FLCLR;
			*a = FLRDM;
			if (*a != *v) {
				EPRINT("flash: write %lux %lux -> %lux failed\n", (ulong)a, (ulong)*a, (ulong)*v);
				return -1;
			}
		}
		n -= m;
		pg++;
		o = 0;
	}
	return 0;
}

static int
reset(Flash *f)
{
	f->id = 0x0089;	/* can't use autoselect: might be running in flash */
	f->devid = 0x66a0;
	f->write = writex;
	f->eraseall = eraseall;
	f->erasezone = erasezone;
	f->suspend = nil;
	f->resume = nil;
	f->width = 1;				/* must be 1 since devflash.c must not read directly */
	f->erasesize = 64*1024;
	*(uchar*)f->addr = FLCLR;	/* clear status registers */
	*(uchar*)f->addr = FLRDM;	/* reset to read mode */
	return 0;
}

void
flashintellink(void)
{
	addflashcard("Intel28F032SA", reset);
}
