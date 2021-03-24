/*
 * ipaq
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"
#include	"io.h"
#include	"image.h"
#include	<memimage.h>
#include	"screen.h"

#include "../port/netif.h"
#include "etherif.h"
#include	"flashif.h"

#define	EGPIOADDR		0x49000000	/* physical address of write only register in CS5 space */

enum {
	/* EGPIO bits used so far */
	EnableFlashWrite = 1<<0,	/* enable programming and erasing of flash */
	ResetCF = 1<<1,	/* CF/PCMCIA card reset */
	ResetOpt = 1<<2,	/* expansion pack reset */
	EnableCodec = 1<<3,	/* onboard codec enable (ie, active low reset) */
	EnableOptNVRAM = 1<<4,	/* enable power to NVRAM of expansion pack */
	EnableOptPack = 1<<5,	/* enable full power to the expansion pack */
	EnableLCD_3v = 1<<6,	/* enables LCD 3.3v power supply */
	EnableRS232 = 1<<7,	  /* UART3 transceiver force on.  Active high. */
	EnableLCD_IC = 1<<8,	/* enables power to LCD control IC */
	EnableAudioAmp = 1<<10,	/* enable power to audio output amplifier */
	EnableAudioPower = 1<<11,	/* power up reset of audio circuitry */
	MuteAudio = 1<<12,		/* mute the audio codec (nb: wastes power if set when audio not powered) */
	EnableLCD_5v = 1<<14,	/* enables 5v to the LCD module */
	EnableLCD_Vdd = 1<<15,	/* enables 9v and -6.5v to the LCD module */
};

/* gpio bits */
#define	SSPCLK	(1<<19)
#define	CSET0	(1<<12)
#define	CSET1	(1<<13)

static ulong egpiocopy = EnableRS232;

ulong cpuidlecount;

extern int cflag;
extern int consoleprint;
extern int redirectconsole;
extern int main_pool_pcnt;
extern int heap_pool_pcnt;
extern int image_pool_pcnt;
extern int kernel_pool_pcnt;
extern char debug_keys;
extern Vmode default_vmode;

static void
egpiosc(ulong set, ulong clr)
{
	int s;

	s = splhi();
	egpiocopy = (egpiocopy & ~clr) | set;
	*(ulong*)EGPIOADDR = egpiocopy;
	splx(s);
}

void
archreset(void)
{
	GpioReg *g = GPIOREG;

	g->grer = 0;
	g->gfer = 0;
	g->gedr = g->gedr;
	g->gpdr = (1<<26)|CSET0|CSET1;
	g->gafr |= SSPCLK;

	*(ulong*)EGPIOADDR = egpiocopy;	/* in case boostrap hasn't set it */
	GPCLKREG->gpclkr0 = 1;	/* SUS=1 for uart on serial 1 */
	dmareset();
	L3init();
}

void
archconfinit(void)
{
	int w;

/*
	bpoverride("cflag", &cflag);
	bpoverride("consoleprint", &consoleprint);
	bpoverride("redirectconsole", &redirectconsole);
	bpoverride("kernel_pool_pcnt", &kernel_pool_pcnt);
	bpoverride("main_pool_pcnt", &main_pool_pcnt);
	bpoverride("heap_pool_pcnt", &heap_pool_pcnt);
	bpoverride("image_pool_pcnt", &image_pool_pcnt);
	bpoverride_uchar("debugkeys", (uchar*)&debug_keys);
	bpoverride("textwrite", &conf.textwrite);
*/

	conf.topofmem = 0xC0000000+32*MB;
	w = PMGRREG->ppcr & 0x1f;
	conf.cpuspeed = TIMER_HZ*(w*4+16);

	conf.useminicache = 1;
	conf.cansetbacklight = 1;
	conf.cansetcontrast = 0;
	conf.portrait = 1;	/* should take from param flash or allow dynamic change */
}

static LCDmode lcd320x240x256tft =
{
	320, 240, 4, 70,         /* wid hgt d hz */
	2, 0, 0, 1,             /* pbs dual mono active */
	4-2, 12-1, 17-1,             /* hsync_wid sol_wait eol_wait */
	3-1, 10, 1,             /* vsync_wid sof_wait eof_wait */
	0, 0, 0,                /* lines_per_int palette_delay acbias_lines */
	16,                     /* obits */
	1, 1,			/* vsync low, hsync low */
};

int
archlcdmode(LCDmode *m)
{
	*m = lcd320x240x256tft;
	return 0;
}

void
archlcdenable(int on)
{
	if(on)
		egpiosc(EnableLCD_3v|EnableLCD_IC|EnableLCD_5v|EnableLCD_Vdd, 0);
	else
		egpiosc(0, EnableLCD_3v|EnableLCD_IC|EnableLCD_5v|EnableLCD_Vdd);
}

void
kbdinit(void)
{
	addclock0link(kbdclock);
}

void
idlehands(void)
{

	cpuidlecount++;
	INTRREG->iccr = 1;	/* only unmasked interrupts will stop idle mode */
	idle();
}

void
archreboot(void)
{
	GPIOREG->gedr = 1<<0;
	mmuctlregw(mmuctlregr() & ~CpCaltivec);	/* restore bootstrap's vectors */
	RESETREG->rsrr = 1;	/* software reset */
	for(;;)
		spllo();
}

void
lights(ulong)
{
}

void
lcd_setbacklight(int)
{
}

void
lcd_setbrightness(ushort)
{
}

void
lcd_setcontrast(ushort)
{
}

int
archflash12v(int /*on*/)
{
        return 1;
}

void
archflashwp(int wp)
{
	if(wp)
		egpiosc(0, EnableFlashWrite);
	else
		egpiosc(EnableFlashWrite, 0);
}

void
archspeaker(int, int)
{
}

void
archrdtsc(vlong *v)
{
	*v = (vlong)OSTMRREG->oscr;
}

ulong
archrdtsc32(void)
{
	return OSTMRREG->oscr;
}

/*
 * for devflash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	strcpy(type, "Intel28F128");
	*addr = (void*)FLASHMEM;
	*length = 16*MB;
	return 0;
}

int
archaudiopower(int on)
{
	int s;

	if(on)
		egpiosc(EnableCodec | EnableAudioPower, 0);
	else
		egpiosc(0, EnableCodec | EnableAudioAmp | EnableAudioPower | MuteAudio);
	s = splhi();
	GPIOREG->gafr |= SSPCLK;
	GPIOREG->gpdr |= CSET0 | CSET1;
	GPIOREG->gpsr = CSET0;
	GPIOREG->gpcr = CSET1;
	splx(s);
	return 0;
}

void
archcodecreset(void)
{
//	egpiosc(0, EnableCodec);
//	egpiosc(EnableCodec, 0);
}

void
archaudiomute(int on)
{
	if(on)
		egpiosc(MuteAudio, 0);
	else
		egpiosc(0, MuteAudio);
}

void
archaudioamp(int on)
{
	if(on)
		egpiosc(EnableAudioAmp, 0);
	else
		egpiosc(0, EnableAudioAmp);
}

enum {
	Fs512 = 0,
	Fs384 = 1,
	Fs256 = 2,

	MHz4_096 = CSET1,
	MHz5_6245 = CSET1|CSET0,
	MHz11_2896 = CSET0,
	MHz12_288 = 0
};

typedef struct Csel Csel;
struct Csel{
	int	speed;
	int	cfs;		/* codec system clock multiplier */
	int	gclk;		/* gpio clock generator setting */
	int	div;		/* ssp clock divisor */
};
static Csel csel[] = {
	{8000, Fs512, MHz4_096, 16},
	{11025, Fs512, MHz5_6245, 16},
	{16000, Fs256 , MHz4_096, 8},
	{22050, Fs512, MHz11_2896, 16},
	{32000, Fs384, MHz12_288, 12},
	{44100, Fs256, MHz11_2896, 8},
	{48000, Fs256, MHz12_288, 8},
	{0},
};

int
archaudiospeed(int clock, int set)
{
	GpioReg *g;
	SspReg *ssp;
	Csel *cs;
	int s, div, cr0;

	for(cs = csel; cs->speed > 0; cs++)
		if(cs->speed == clock){
			if(!set)
				return cs->cfs;
			div = cs->div;
			if(div == 0)
				div = 4;
			div = div/2 - 1;
			s = splhi();
			g = GPIOREG;
			g->gpsr = cs->gclk;
			g->gpcr = ~cs->gclk & (CSET0|CSET1);
			ssp = SSPREG;
			cr0 = (div<<8) | 0x1f;	/* 16 bits, TI frames, not enabled */
			ssp->sscr0 = cr0;
			ssp->sscr1 = 0x0020;	/* ext clock */
			ssp->sscr0 = cr0 | 0x80;	/* enable */
			splx(s);
			return cs->cfs;
		}
	return -1;
}

/*
 * pcmcia
 */
int
pcmpowered(int slotno)
{
	if(slotno)
		return 0;
	if(egpiocopy & EnableOptNVRAM)
		return 3;
	return 0;
}

void
pcmpower(int slotno, int on)
{
	USED(slotno);	/* the pack powers both or none */
	if(on){
		if((egpiocopy & EnableOptNVRAM) == 0){
			egpiosc(EnableOptNVRAM | EnableOptPack, 0);
			delay(200);
		}
	}else
		egpiosc(0, EnableOptNVRAM | EnableOptPack);
}

void
pcmreset(int slot)
{
	USED(slot);
	egpiosc(ResetCF, 0);
	delay(100);	// microdelay(10);
	egpiosc(0, ResetCF);
}

int
pcmpin(int slot, int type)
{
	USED(slot);
	switch(type){
	case PCMready:
		return slot==0? 21: 11;
	case PCMeject:
		return slot==0? 17: 10;
	case PCMstschng:
		return -1;
	}
}

void
pcmsetvpp(int slot, int vpp)
{
	USED(slot, vpp);
}


/*
 * set ether parameters: the contents should be derived from EEPROM or NVRAM
 */
int
archether(int ctlno, Ether *ether)
{
	static char opt[128];

	if(ctlno == 1){
		sprint(ether->type, "EC2T");
		return 1;
	}
	if(ctlno > 0)
		return -1;
	sprint(ether->type, "wavelan");
	strcpy(opt, "mode=0 essid=VNH1 station=ipaq1 crypt=off");	/* peertopeer */
	ether->nopt = tokenize(opt, ether->opt, nelem(ether->opt));
	return 1;
}

long
archkprofmicrosecondspertick(void)
{
	return MS2HZ*1000;
}

void
archkprofenable(int)
{
}
