#include	"u.h"
#include	"lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

#include	"archrpcg.h"

/*
 * board-specific support for the RPCG RXLite
 */

enum {
	SYSMHZ =	66,	/* target frequency */

	/* sccr */
	RTSEL = IBIT(8),	/* =0, select main oscillator (OSCM); =1, select external crystal (EXTCLK) */
	RTDIV = IBIT(7),	/* =0, divide by 4; =1, divide by 512 */
	CRQEN = IBIT(9),	/* =1, switch to high frequency when CPM active */
	PRQEN = IBIT(10),	/* =1, switch to high frequency when interrupt pending */

	/* plprcr */
	CSRC = IBIT(21),	/* =0, clock is DFNH; =1, clock is DFNL */
};

static	char	flashsig[] = "RPXsignature=1.0\nNAME=qbrpcg\nSTART=FFC00100\nVERSION=1.0\n";

/*
 * called early in main.c, after machinit:
 * using board and architecture specific registers, initialise
 * 8xx registers that need it and complete initialisation of the Mach structure.
 */
void
archinit(void)
{
	IMM *io;
	int mf, t;
	ulong v;

	v = getimmr() & 0xFFFF;
	switch(v>>8){
	case 0x00:	t = 0x86000; break;
	case 0x20:	t = 0x82300; break;
	case 0x21:	t = 0x823a0; break;
	default:	t = 0; break;
	}
	m->cputype = t;
	m->bcsr = KADDR(BCSRMEM);
m->bcsr = KADDR(0xFA400000);
	io = m->iomem;
	m->clockgen = 8*MHz;
	mf = (SYSMHZ*MHz)/m->clockgen;
	m->cpuhz = m->clockgen*mf;
	m->bcsr[0] = DisableColTest|DisableFullDplx|DisableUSB|HighSpdUSB;	/* first write enables bcsr regs */
return;
	io->plprcrk = KEEP_ALIVE_KEY;
	io->plprcr &= ~CSRC;	/* general system clock is DFNH */
	io->plprcr = (io->plprcr & ((1<<20)-1)) | ((mf-1)<<20);
	io->mptpr = 0x0400;	/* memory prescaler = 16 for refresh */
	io->plprcrk = ~KEEP_ALIVE_KEY;
}

void
cpuidprint(void)
{
	int t, v;

	print("RPXLite bootloader for Inferno Network OS\n");
	print("RPCG 1999\n");
	print("PVR: ");
	t = getpvr()>>16;
	switch(t){
	case 0x01:	print("MPC601"); break;
	case 0x03:	print("MPC603"); break;
	case 0x04:	print("MPC604"); break;
	case 0x06:	print("MPC603e"); break;
	case 0x07:	print("MPC603e-v7"); break;
	case 0x50:	print("MPC8xx"); break;
	default:	print("PowerPC version #%x", t); break;
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
	print("options: #%lux\n", archoptionsw());
	print("bcsr: %8.8lux\n", m->bcsr[0]);
	print("plprcr=%8.8lux sccr=%8.8lux\n", m->iomem->plprcr, m->iomem->sccr);
	print("%lud MHz system\n", m->cpuhz/MHz);
	print("\n");
}

static	char*	defplan9ini[2] = {
	/* 860/821 */
	"ether0=type=SCC port=1 ea=00108bf12900\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0\r\nbaud=9600\r\n",

	/* 823 */
	"ether0=type=SCC port=2 ea=00108bf12900\r\n"
	"vgasize=640x480x8\r\n"
	"kernelpercent=40\r\n"
	"console=0\r\nbaud=9600\r\n",
};

char *
archconfig(void)
{
	print("Using default configuration\n");
	return defplan9ini[MPCMODEL(m->cputype) == 0x823];
}

/*
 * provide value for #r/switch (devrtc.c)
 */
int
archoptionsw(void)
{
	return (m->bcsr[0]&DipSwitchMask)>>4;
}

/*
 * invoked by clock.c:/^clockintr
 */
static void
twinkle(void)
{
	if(m->ticks%MS2TK(1000) == 0)
		m->bcsr[0] ^= LedOff;
}

void	(*archclocktick)(void) = twinkle;

/*
 * for flash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	if((m->iomem->memc[BOOTCS].base & 1) == 0)
		return -1;		/* shouldn't happen */
	strcpy(type, "AMD29F0x0");
	*addr = KADDR(FLASHMEM);
*addr = KADDR(0xFE000000);
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

	switch(cpmid){
	default:
		/* no other SCCs are wired for ether on RXLite*/
		return -1;

	case SCC2ID:
		io = ioplock();
		m->bcsr[0] |= EnableEnet;
		io->papar |= SIBIT(6)|SIBIT(4);	/* enable CLK2 and CLK4 */
		io->padir &= ~(SIBIT(6)|SIBIT(4));
		*rcs = CLK2;
		*tcs = CLK4;
		iopunlock();
		break;
	}
	return 0;
}

void
archetherdisable(int id)
{
	USED(id);
	m->bcsr[0] &= ~EnableEnet;
}

/*
 * do anything extra required to enable the UART on the given CPM port
 */
void
archenableuart(int id, int irda)
{
	USED(id, irda);
}

/*
 * do anything extra required to disable the UART on the given CPM port
 */
void
archdisableuart(int id)
{
	USED(id);
}

/*
 * enable/disable the LCD panel's backlight
 */
void
archbacklight(int on)
{
	USED(on);
}
