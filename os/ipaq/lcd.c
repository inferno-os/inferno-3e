#include	"u.h"
#include 	"mem.h"
#include	"../port/lib.h"
#include 	"dat.h"
#include 	"image.h"
#include	"fns.h"
#include	"io.h"
#include	<memimage.h>
#include	"screen.h"

#define	Backgnd		(0xff)

#define	DPRINT	if(1)iprint

extern int r_gamma;
extern int g_gamma;
extern int b_gamma;

enum {
	SETGAMMA = 1
};

enum {
	/* lccr0 */
	EnableCtlr = 1<<0,	/* controller enable */
	IsColour = 0<<1,
	IsMono = 1<<1,
	SinglePanel = 0<<2,
	DualPanel = 1<<2,
	DisableDone = 1<<3,
	DisableBAU = 1<<4,
	DisableErr = 1<<5,
	PassivePanel = 0<<7,
	ActivePanel = 1<<7,
	BigEndian = 1<<8,
	DoublePixel = 1<<9,
	/* 19:12 is palette dma delay */

	/* lccr3 */
	VsyncLow = 1<<20,
	HsyncLow = 1<<21,
	PixelClockLow = 1<<22,
	OELow = 1<<23,
};

typedef struct {
	Vdisplay;
	LCDparam;
	ushort*	palette;
	uchar*	upper;
	uchar*	lower;
} LCDdisplay;

static LCDdisplay	*vd;	// current active display

void
lcd_setcolor(ulong p, ulong r, ulong g, ulong b)
{
	if(vd->pbs == 0 && p > 15 ||
	   vd->pbs == 1 && p > 255 ||
	   vd->pbs == 2)
		return;
	vd->palette[p] = (vd->pbs<<12) |
			((r>>(32-4))<<8) |
			((g>>(32-4))<<4) |
			(b>>(32-4));
}

static void
setLCD(LCDdisplay *vd)
{
	LCDmode *m;
	int ppf, pclk, clockdiv;
	ulong v, c;
	LcdReg *lcd = LCDREG;
	GpioReg *gpio = GPIOREG;

	m = (LCDmode*)&vd->Vmode;
	ppf = ((((m->wid+m->sol_wait+m->eol_wait) *
		       (m->mono ? 1 : 3)) >> (3-m->mono)) +
			m->hsync_wid) *
		       (m->hgt/(m->dual+1)+m->vsync_hgt+
			m->sof_wait+m->eof_wait);
	pclk = ppf*m->hz;
	clockdiv = ((conf.cpuspeed/pclk) >> 1)-2;
	DPRINT(" oclockdiv=%d\n", clockdiv);
clockdiv=0x10;
	// if LCD enabled, turn off and wait for current frame to end
	if(lcd->lccr0 & EnableCtlr) {
		lcd->lccr0 &= ~EnableCtlr;
		if (lcd->lcsr & 0x00000001)		/* broken old rev CPU -- bit always on */
			delay(50);				/* give it plenty of time to end */
		while(!(lcd->lcsr & 0x00000001))
			;
	}
	// Then make sure it gets reset
	lcd->lccr0 = 0;

	DPRINT("  pclk=%d clockdiv=%d\n", pclk, clockdiv);
	lcd->lccr3 =  (clockdiv << 0) |
		(m->acbias_lines << 8) |
		(m->lines_per_int << 16) |
		VsyncLow | HsyncLow;	/* vsync active low, hsync active low */
	lcd->lccr2 =  (((m->hgt/(m->dual+1))-1) << 0) |
		(m->vsync_hgt << 10) |
		(m->eof_wait << 16) |
		(m->sof_wait << 24);
	lcd->lccr1 =  ((m->wid-16) << 0) |
		(m->hsync_wid << 10) |
		(m->eol_wait << 16) |
		(m->sol_wait << 24);

	// enable LCD controller, CODEC, and lower 4/8 data bits (for tft/dual)
	v = m->obits < 12? 0: m->obits < 16? 0x3c: 0x3fc;
	c = m->obits == 12? 0x3c0: 0;
	gpio->gafr |= v;
	gpio->gpdr |= v | c;
	gpio->gpcr = c;

	lcd->dbar1 = PADDR(vd->palette);
	if(vd->dual)
		lcd->dbar2 = PADDR(vd->lower);

	// Enable LCD
	lcd->lccr0 = EnableCtlr | (m->mono?IsMono:IsColour)
		| (m->palette_delay << 12)
		| (m->dual ? DualPanel : SinglePanel)
		| (m->active? ActivePanel: PassivePanel)
		| DisableDone | DisableBAU | DisableErr;

	// recalculate actual HZ
	pclk = (conf.cpuspeed/(clockdiv+2)) >> 1;
	m->hz = pclk/ppf;

	archlcdenable(1);
iprint("lccr0=%8.8lux lccr1=%8.8lux lccr2=%8.8lux lccr3=%8.8lux\n", lcd->lccr0, lcd->lccr1, lcd->lccr2, lcd->lccr3);
}

Vdisplay*
lcd_init(LCDmode *m)
{
	static LCDdisplay main_display;	/* TO DO: limits us to a single display */
	int palsize;
	int fbsize;

	vd = &main_display;
	vd->Vmode = *m;
	vd->LCDparam = *m;
	DPRINT("%dx%dx%d: hz=%d\n", vd->wid, vd->hgt, 1<<vd->d, vd->hz); /* */

	palsize = vd->pbs==1? 256 : 16;
	fbsize = palsize*2+(((vd->wid*vd->hgt) << vd->d) >> 3);
	if((vd->palette = xspanalloc(fbsize+CACHELINESZ+512, CACHELINESZ, 0)) == nil)	/* at least 16-byte alignment */
		panic("no vidmem, no party...");
	vd->palette[0] = (vd->pbs<<12);
	vd->palette = minicached(vd->palette);
	vd->upper = (uchar*)(vd->palette + palsize);
	vd->bwid = (vd->wid << vd->pbs) >> 1;
	vd->lower = vd->upper+((vd->bwid*vd->hgt) >> 1);
	vd->fb = vd->upper;
	DPRINT("  fbsize=%d p=%ux u=%ux l=%ux\n", fbsize, vd->palette, vd->upper, vd->lower); /* */

	setLCD(vd);

	if(SETGAMMA){
		r_gamma = 1;
		b_gamma = 1;
		g_gamma = 1;
	}
	vd->contrast = MAX_VCONTRAST/2+1;
	vd->brightness = MAX_VBRIGHTNESS/2+1;
	return vd;
}

void
lcd_flush(void)
{
	if(conf.useminicache)
		miniwbflush();
	else
		wbflush(nil, 0);	/* need more precise addresses */
}

void
lcd_sethz(int hz)
{
	vd->hz = hz;
	setLCD(vd);
}
