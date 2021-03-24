#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	<image.h>
#include	<memimage.h>
#include	<cursor.h> 
#include	"screen.h"

#include	"archipe.h"

/*
 * board-specific support for the Bright Star Engineering ipEngine-1
 */

enum {
	/* sccr */
	COM3=	IBIT(1)|IBIT(2),	/* clock output disabled */
	TBS =	IBIT(6),	/* =0, time base is OSCCLK/{4,16}; =1, time base is GCLK2/16 */
	RTSEL = IBIT(8),	/* =0, select main oscillator (OSCM); =1, select external crystal (EXTCLK) */
	RTDIV = IBIT(7),	/* =0, divide by 4; =1, divide by 512 */
	CRQEN = IBIT(9),	/* =1, switch to high frequency when CPM active */
	PRQEN = IBIT(10),	/* =1, switch to high frequency when interrupt pending */

	/* plprcr */
	CSRC = IBIT(21),	/* =0, clock is DFNH; =1, clock is DFNL */
};

/*
 * called early in main.c, after machinit:
 * using board and architecture specific registers, initialise
 * 8xx registers that need it and complete initialisation of the Mach structure.
 */
void
archinit(void)
{
	IMM *io;
	int mf;

	io = m->iomem;	/* run by reset code: no need to lock */
	m->clockgen = 4000000;	/* crystal frequency */
	m->oscclk = m->clockgen/MHz;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~CSRC;	/* general system clock is DFNH */
	mf = (io->plprcr >> 20)+1;	/* use timing set by bootstrap */
	io->plprcrk = ~KEEP_ALIVE_KEY;
	io->sccrk = KEEP_ALIVE_KEY;
	io->sccr |= CRQEN | PRQEN | RTDIV;
	if(0)
		io->sccr |= COM3;	/* the FPGA can use the clock */
	io->sccrk = ~KEEP_ALIVE_KEY;
	m->cpuhz = m->clockgen*mf;
	m->speed = m->cpuhz/MHz;
	if((io->memc[CLOCKCS].base & 1) == 0){	/* prom hasn't mapped it */
		io->memc[CLOCKCS].option = 0xFFFF0F24;
		io->memc[CLOCKCS].base = 0xFF020001;
	}
}

static ulong
banksize(int x, ulong *pa)
{
	IMM *io;

	io = m->iomem;
	if((io->memc[x].base & 1) == 0)
		return 0;	/* bank not valid */
	*pa = io->memc[x].base & ~0x7FFF;
	return -(io->memc[x].option&~0x7FFF);
}

/*
 * initialise the kernel's memory configuration:
 * there are two banks (base0, npage0) and (base1, npage1).
 * initialise any other values in conf that are board-specific.
 */
void
archconfinit(void)
{
	ulong pa, nbytes, ktop;

	conf.nscc = 2;
	conf.sccuarts = 0;	/* no SCC uarts */
	conf.smcuarts = (1<<0)|(1<<1);	/* SMC1 (console) and SMC2 */

	nbytes = banksize(DRAMCS, &pa);
	if(nbytes == 0){	/* force default */
		nbytes = 16*1024*1024;
		pa = 0;
	}
	conf.npage0 = nbytes/BY2PG;
	conf.base0 = pa;

	conf.npage1 = 0;

	/* the following assumes the kernel text and/or data is in bank 0 */
	ktop = PGROUND((ulong)end);
	ktop = PADDR(ktop) - conf.base0;
	conf.npage0 -= ktop/BY2PG;
	conf.base0 += ktop;
}

void
cpuidprint(void)
{
	ulong v;

	print("PVR: ");
	switch(m->cputype){
	case 0x01:	print("MPC601"); break;
	case 0x03:	print("MPC603"); break;
	case 0x04:	print("MPC604"); break;
	case 0x06:	print("MPC603e"); break;
	case 0x07:	print("MPC603e-v7"); break;
	case 0x50:	print("MPC8xx"); break;
	default:	print("PowerPC version #%x", m->cputype); break;
	}
	print(", revision #%lux\n", getpvr()&0xffff);
	print("IMMR: ");
	v = getimmr() & 0xFFFF;
	switch(v>>8){
	case 0x00:	print("MPC860/821"); break;
	case 0x20:	print("MPC823"); break;
	case 0x21:	print("MPC823A"); break;
	default:	print("Type #%lux", v>>8); break;
	}
	print(", mask #%lux\n", v&0xFF);
	print("plprcr=%8.8lux sccr=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr);
	print("pipr=%8.8lux\n", m->iomem->pipr);
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("\n");

	/* dump the memory configuration while we're at it */
	for(v=0; v<nelem(m->iomem->memc); v++)
		if(m->iomem->memc[v].base & 1)
			print("%ld %8.8lux %8.8lux\n", v, m->iomem->memc[v].base, m->iomem->memc[v].option);
}

void
toggleled(int b)
{
	int s;
	s = splhi();
	m->iomem->pdpar &= ~(0x20<<b);
	m->iomem->pddir |= 0x20<<b;
	m->iomem->pddat ^= 0x020<<b;
	splx(s);
}

/*
 * provide value for #r/switch (devrtc.c)
 */
int
archoptionsw(void)
{
	return 0;
}

/*
 * invoked by clock.c:/^clockintr
 */
static void
twinkle(void)
{
	if(m->ticks%MS2TK(1000) == 0 && m->iomem)
		toggleled(0);
}

void	(*archclocktick)(void) = twinkle;

/*
 * invoked by ../port/taslock.c:/^ilock:
 * reset watchdog timer here, if there is one and it is enabled
 */
void
clockcheck(void)
{
}

/*
 * for devflash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	strcpy(type, "Intel28F320");
	*addr = KADDR(FLASHMEM);
	*length = 4*1024*1024;
	return 0;
}

/*
 * enable the clocks for the given SCC ether and reveal them to the caller.
 * do anything else required to prepare the transceiver (eg, set full-duplex, reset loopback).
 */
int
archetherenable(int cpmid, int *rcs, int *tcs)
{
	IMM *io;

	if(cpmid != CPscc2)
		return -1;
	io = ioplock();
	io->pcpar &= ~EnetLoopback;
	io->pcdir |= EnetLoopback;
	io->pcdat &= ~EnetLoopback;
	io->pbpar &= ~EnableEnet;
	io->pbdir |= EnableEnet;
	io->pbdat |= EnableEnet;
	io->papar |= SIBIT(7)|SIBIT(6);	/* enable CLK1 and CLK2 */
	io->padir &= ~(SIBIT(7)|SIBIT(6));
	iopunlock();
	*rcs = CLK2;
	*tcs = CLK1;
	return 0;
}

/*
 * do anything extra required to enable the UART on the given CPM port
 */
static	ulong	uartsactive;

void
archenableuart(int id, int irda)
{
	IMM *io;

	USED(id);	/* both uarts seem to be controlled by the same bit */
	USED(irda);	/* no IrDA on ipEngine */
	io = ioplock();
	if(uartsactive == 0){
		io->pbpar &= ~EnableRS232;
		io->pbdir |= EnableRS232;
		io->pbdat |= EnableRS232;
	}
	uartsactive |= 1<<id;
	iopunlock();
}

/*
 * do anything extra required to disable the UART on the given CPM port
 */
void
archdisableuart(int id)
{
	IMM *io;

	io = ioplock();
	uartsactive &= ~(1<<id);
	if(uartsactive == 0)
		io->pbdat &= ~EnableRS232;
	iopunlock();
}

/*
 * enable the external USB transceiver
 *	speed is 12MHz if highspeed is non-zero; 1.5MHz if zero
 *	master is non-zero if the node is acting as USB Host and should provide power
 */
void
archenableusb(int highspeed, int master)
{
	IMM *io;

	USED(master);
	io = ioplock();
	if(highspeed)
		io->pcdat |= USBFullSpeed;
	else
		io->pcdat &= ~USBFullSpeed;
	io->pcdir |= USBFullSpeed;
	io->pcpar &= ~USBFullSpeed;
	iopunlock();
}

/*
 * shut down the USB transceiver
 */
void
archdisableusb(void)
{
	/* nothing to be done on ipEngine, apparently */
}

/*
 * set the external infrared transceiver to the given speed
 */
void
archsetirxcvr(int highspeed)
{
	USED(highspeed);
}

/*
 * force hardware reset/reboot
 */
void
archreboot(void)
{
	IMM *io;

	io = m->iomem;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr |= 1<<7;	/* checkstop reset enable */
	io->plprcrk = ~KEEP_ALIVE_KEY;
	eieio();
	io->sdcr = 1;
	eieio();
	io->lccr = 0;	/* switch LCD off */
	eieio();
	firmware(0);
}

/*
 * enable/disable the LCD panel's backlight
 */
void
archbacklight(int on)
{
	USED(on);
}

/*
 * set parameters to describe the screen
 */
int
archlcdmode(Mode *m)
{
	/* sample parameters in case a panel is attached to the external pins */
	m->x = 640;
	m->y = 480;
	m->d = 3;
	m->lcd.freq = 25000000;
	m->lcd.ac = 0;
	m->lcd.vpw = 1;
	m->lcd.wbf = 33;
	m->lcd.wbl = 228;
	m->lcd.flags = IsColour | IsTFT | OELow | VsyncLow | ClockLow;
	return -1;	/* there isn't a screen */
}

/*
 * there isn't a keyboard port
 */
void
archkbdinit(void)
{
}

/*
 * there isn't a screen
 */
void
screeninit(void)
{
}

void
screenputs(char*, int)
{
}

int
lcdctl(char*, long)
{
	return -1;
}

void
cursorenable(void)
{
}

void
cursordisable(void)
{
}

void
mousetrack(int, int, int)
{
}
