#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"../port/error.h"

#include	<image.h>
#include	<memimage.h>
#include	<cursor.h> 
#include	"vga.h"

#define	Backgnd		(0xff)
#define	Foregnd		(0x00)

typedef struct SWcursor SWcursor;
static SWcursor *swc = nil;
SWcursor* swcurs_create(ulong *, int, int, Rectangle, int);
void swcurs_destroy(SWcursor*);
void swcurs_enable(SWcursor*);
void swcurs_disable(SWcursor*);
void swcurs_hide(SWcursor*);
void swcurs_unhide(SWcursor*);
void swcurs_load(SWcursor*, Cursor*);

Cursor	arrow = {
	{ -1, -1 },
	{ 0xFF, 0xFF, 0x80, 0x01, 0x80, 0x02, 0x80, 0x0C, 
	  0x80, 0x10, 0x80, 0x10, 0x80, 0x08, 0x80, 0x04, 
	  0x80, 0x02, 0x80, 0x01, 0x80, 0x02, 0x8C, 0x04, 
	  0x92, 0x08, 0x91, 0x10, 0xA0, 0xA0, 0xC0, 0x40, 
	},
	{ 0x00, 0x00, 0x7F, 0xFE, 0x7F, 0xFC, 0x7F, 0xF0, 
	  0x7F, 0xE0, 0x7F, 0xE0, 0x7F, 0xF0, 0x7F, 0xF8, 
	  0x7F, 0xFC, 0x7F, 0xFE, 0x7F, 0xFC, 0x73, 0xF8, 
	  0x61, 0xF0, 0x60, 0xE0, 0x40, 0x40, 0x00, 0x00, 
	},
};

static	Rectangle	update;
static	Rectangle	nilbb = { 10000, 10000, -10000, -10000};

int	novgascreen;

Memimage	gscreen;
Memdata		gscreendata;
ulong		consbits = 0;

Memdata	consdata = {
	nil,
	&consbits
};
Memimage conscol =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&consdata,
	0,
	1
};

ulong	onesbits = ~0;
Memdata	onesdata = {
	nil,
	&onesbits,
};
Memimage	xones =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&onesdata,
	0,
	1
};
Memimage *memones = &xones;

ulong	zerosbits = 0;
Memdata	zerosdata = {
	nil,
	&zerosbits,
};
Memimage	xzeros =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&zerosdata,
	0,
	1
};
Memimage *memzeros = &xzeros;

ulong	backbits = (Backgnd<<24)|(Backgnd<<16)|(Backgnd<<8)|Backgnd;
Memdata	backdata = {
	nil,
	&backbits
};
Memimage	xback =
{
	{ 0, 0, 1, 1 },
	{ -100000, -100000, 100000, 100000 },
	3,
	1,
	&backdata,
	0,
	1
};
Memimage *back = &xback;

static	Memsubfont *memdefont;
static	Lock	palettelock;			/* access to DAC registers */
static	Lock	screenlock;
static	ulong	colormap[256][3];
static	int	h;
static	Point	curpos;
static	Rectangle window;
static	int	useflush;

static	void	setscreen(Mode*);
static	void	screenputc(char*);
static	void	scroll(void);
static	void	cursorlock(Rectangle);
static	void	cursorunlock(void);

extern Vgac* knownvga[];
static Vgac* vgac;

static Mode mode = {
	640,					/* x */
	480,					/* y */
	3,					/* d */

	(uchar*)0xA0000,			/* aperture */
	1<<16,					/* apsize */
	16,					/* apshift */
};

int
vgaxi(long port, uchar index)
{
	uchar data, x;

	switch(port) {
	case Seqx:
	case Crtx:
	case Grx:
		outb(port, index);
		data = inb(port+1);
		break;
	case Attrx:
		x = inb(Status1);
		if(index < 0x10){
			outb(Attrx, index);
			data = inb(Attrx+1);
			x = inb(Status1);
			outb(Attrx, 0x20|index);
		}
		else{
			outb(Attrx, 0x20|index);
			data = inb(Attrx+1);
		}
		USED(x);
		break;
	default:
		return -1;
	}
	return data & 0xFF;
}

int
vgaxo(long port, uchar index, uchar data)
{
	uchar x;

	switch(port) {
	case Seqx:
	case Crtx:
	case Grx:
		/*
		 * We could use an outport here, but some chips
		 * (e.g. 86C928) have trouble with that for some
		 * registers.
		 */
		outb(port, index);
		outb(port+1, data);
		break;
	case Attrx:
		x = inb(Status1);
		if(index < 0x10){
			outb(Attrx, index);
			outb(Attrx, data);
			x = inb(Status1);
			outb(Attrx, 0x20|index);
		}
		else{
			outb(Attrx, 0x20|index);
			outb(Attrx, data);
		}
		USED(x);
		break;
	default:
		return -1;
	}

	return 0;
}

/*
 *  Called by main().
 */
void
screeninit(void)
{
	char *p;

	memdefont = getmemdefont();

	if (getconf("_v_res")) {
		mode.x = mode.y = -1;		/* ignore vgasize if mode has been set up already */
	} else if(p = getconf("vgasize")){
		if(cistrcmp(p, "800x600x8") == 0){
			mode.x = 800;
			mode.y = 600;
		}
		else if(cistrcmp(p, "1024x768x8") == 0){
			mode.x = 1024;
			mode.y = 768;
		}
		else{
			mode.x = 640;
			mode.y = 480;
		}
	}
	if(novgascreen == 0)
		setscreen(&mode);

	update = gscreen.r;
}

typedef struct VGAmode	VGAmode;
struct VGAmode
{
	uchar	misc;
	uchar	sequencer[5];
	uchar	crt[0x19];
	uchar	graphics[9];
	uchar	attribute[0x15];
};

/*
 *  640x480 display, 1, 2, or 4 bit color.
 */
VGAmode mode12 = 
{
	/* general */
	0xe7,
	/* sequence */
	0x03, 0x01, 0x0f, 0x00, 0x06,
	/* crt */
	0x65, 0x4f, 0x50, 0x88, 0x55, 0x9a, 0x09, 0x3e,
	0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xe8, 0x8b, 0xdf, 0x28, 0x00, 0xe7, 0x04, 0xe3,
	0xff,
	/* graphics */
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x0f,
	0xff,
	/* attribute 0x11 is overscan color */
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
	0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x01, Backgnd, 0x0f, 0x00, 0x00,
};

/*
 *  320x200 display, 8 bit color.
 */
VGAmode mode13 = 
{
	/* general */
	0x63,
	/* sequence */
	0x03, 0x01, 0x0f, 0x00, 0x0e,
	/* crt */
	0x5f, 0x4f, 0x50, 0x82, 0x54, 0x80, 0xbf, 0x1f,
	0x00, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28,
	0x9c, 0x8e, 0x8f, 0x28, 0x40, 0x96, 0xb9, 0xa3,
	0xff,
	/* graphics */
	0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x05, 0x0f,
	0xff,
	/* attribute */
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
	0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x41, Backgnd, 0x0f, 0x00, 0x00,
};

VGAmode vga640x480x8 = {
	0xE3,						/* Misc */
	0x03, 0x01, 0x0F, 0x00, 0x0A,			/* Sequencer */
	0x5F, 0x4F, 0x52, 0x9F, 0x53, 0x1F, 0x0B, 0x3E,	/* Crt */
	0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xEB, 0x2D, 0xDF, 0x50, 0x60, 0xEB, 0xEC, 0xA3,
	0xFF,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x05, 0x0F,	/* Graphics */
	0xFF,
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,	/* Attribute */
	0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
	0x41, Backgnd, 0x0F, 0x00, 0x00,
};

VGAmode vga800x600x8 = {
	0xE3,						/* Misc */
	0x03, 0x01, 0x0F, 0x00, 0x0A,			/* Sequencer */
	0x7F, 0x63, 0x68, 0x9D, 0x69, 0x9D, 0x77, 0xF0,	/* Crt */
	0x00, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x5D, 0x2F, 0x57, 0x64, 0x60, 0x5D, 0x5E, 0xA3,
	0xFF,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x05, 0x0F,	/* Graphics */
	0xFF,
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,	/* Attribute */
	0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
	0x41, Backgnd, 0x0F, 0x00, 0x00,
};

VGAmode vga1024x768x8 = {
	0xE3,						/* Misc */
	0x03, 0x01, 0x0F, 0x00, 0x0A,			/* Sequencer */
	0xA5, 0x7F, 0x86, 0x9A, 0x85, 0x14, 0x25, 0xFD,	/* Crt */
	0x00, 0x60, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x02, 0x26, 0xFF, 0x80, 0x60, 0x03, 0x04, 0xA3,
	0xFF,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x50, 0x05, 0x0F,	/* Graphics */
	0xFF,
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,	/* Attribute */
	0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
	0x41, Backgnd, 0x0F, 0x00, 0x00,
};

enum {
	NSeqx		= 0x05,
	NCrtx		= 0x19,
	NGrx		= 0x09,
	NAttrx		= 0x15,
};

static void
setVGAmode(VGAmode *vga)
{
	int i;
	uchar seq01;

	/*
	 * Turn off the screen and
	 * reset the sequencer and leave it off.
	 * Load the generic VGA registers:
	 *	misc;
	 *	sequencer;
	 *	restore the sequencer reset state;
	 *	take off write-protect on crt[0x00-0x07];
	 *	crt;
	 *	graphics;
	 *	attribute;
	 * Restore the screen state.
	 */
	seq01 = vgaxi(Seqx, 0x01);
	vgaxo(Seqx, 0x01, seq01|0x20);

	vgao(MiscW, vga->misc);

	for(i = 0; i < NSeqx; i++){
		if(i == 1)
			continue;
		vgaxo(Seqx, i, vga->sequencer[i]);
	}

	vgaxo(Crtx, 0x11, vga->crt[0x11] & ~0x80);
	for(i = 0; i < NCrtx; i++)
		vgaxo(Crtx, i, vga->crt[i]);

	for(i = 0; i < NGrx; i++)
		vgaxo(Grx, i, vga->graphics[i]);

	for(i = 0; i < NAttrx; i++)
		vgaxo(Attrx, i, vga->attribute[i]);

	vgaxo(Seqx, 0x01, vga->sequencer[1]);
}

static int
setvgadev(char* ctlr, Mode* mode)
{
	int i;

	for(i = 0; knownvga[i]; i++){
		if(ctlr){
			if(knownvga[i]->name && strcmp(ctlr, knownvga[i]->name) == 0){
				vgac = knownvga[i];
				break;
			}
		}
		else if(knownvga[i]->ident && knownvga[i]->ident()){
			vgac = knownvga[i];
			break;
		}
	}

	if(vgac == 0)
		return 1;

	if(vgac->init)
		vgac->init(mode);

	return 0;
}

/*
 * On 8 bit displays, load the default color map
 */
void
graphicscmap(int invert)
{
	int num, den, i, j;
	int r, g, b, cr, cg, cb, v;

	for(r=0,i=0;r!=4;r++) for(v=0;v!=4;v++,i+=16){
		for(g=0,j=v-r;g!=4;g++) for(b=0;b!=4;b++,j++){
			den=r;
			if(g>den) den=g;
			if(b>den) den=b;
			if(den==0)	/* divide check -- pick grey shades */
				cr=cg=cb=v*17;
			else{
				num=17*(4*den+v);
				cr=r*num/den;
				cg=g*num/den;
				cb=b*num/den;
			}
			if(invert)
				setcolor(255-i-(j&15),
					cr*0x01010101, cg*0x01010101, cb*0x01010101);
			else
				setcolor(i+(j&15),
					cr*0x01010101, cg*0x01010101, cb*0x01010101);
		}
	}
}

/*
 *  reconfigure screen shape
 */
static void
setscreen(Mode* mode)
{
	int i, width;

	if(swc)
		swcurs_destroy(swc);

	if(mode->x == 640 && mode->y == 480 && mode->d == 3)
		setVGAmode(&vga640x480x8);
	else if(mode->x == 800 && mode->y == 600 && mode->d == 3)
		setVGAmode(&vga800x600x8);
	else if(mode->x == 1024 && mode->y == 768 && mode->d == 3)
		setVGAmode(&vga1024x768x8);
	else if (mode->x >= 0)
		error(Ebadarg);

	if(setvgadev(0, mode))
		panic("no display hardware configured\n");

	width = (mode->x*(1<<mode->d))/BI2WD;
	if(mode->aperture == 0xA0000){
		gscreendata.data = xalloc(width*BY2WD*mode->y);
		if(gscreendata.data == 0)
			panic("setscreen: vga soft memory");
		memset(gscreendata.data, Backgnd, width*BY2WD*mode->y);
		useflush = 1;
	}
	else
		gscreendata.data = KADDR(mode->aperture);

	gscreen.data = &gscreendata;
	gscreen.ldepth = mode->d;
	gscreen.width = (mode->x*(1<<gscreen.ldepth)+31)/32;
	gscreen.r.min = Pt(0, 0);
	gscreen.r.max = Pt(mode->x, mode->y);
	gscreen.clipr = gscreen.r;
	gscreen.repl = 0;

	for(i = 0; i < gscreen.width*BY2WD*mode->y; i += mode->apsize){
		vgac->page(i>>mode->apshift);
		memset(gscreendata.data, Backgnd, mode->apsize);
	}

	/* get size for a system window */
	h = memdefont->height;
	window = gscreen.r;
	window.max.x = mode->x;
	window.max.y = (mode->y/h) * h;
	curpos = window.min;

	if (0)
		graphicscmap(0);

	if (swcursor) {
		swc = swcurs_create(gscreendata.data, gscreen.width, gscreen.ldepth, gscreen.r, 1);

		drawcursor(nil);
	}
}

void
nmiscreen(void)
{
	Point p;

	unlock(&screenlock);	/* Break the screenlock we are splhi */

	curpos = window.min;	/* Reset cursor */

	update = gscreen.r;

	p = (Point){0, 0};
	memdraw(&gscreen, gscreen.r, memones, p, memones, p);
	update = gscreen.r;
}

void
flushmemscreen(Rectangle r)
{
	uchar *sp, *hp, *edisp, *disp;
	int y, len, incs, off, page;
	static int flushing;
	static Lock pagelock;

	if(useflush == 0)
		return;
	if(rectclip(&r, gscreen.r) == 0)
		return;
	incs = gscreen.width * BY2WD;

	switch(gscreen.ldepth){
	default:
		len = 0;
		panic("flushmemscreen: ldepth\n");
		break;
	case 3:
		len = Dx(r);
		break;
	}
	if(len < 1)
		return;

	ilock(&pagelock);
	if (flushing) {
		iunlock(&pagelock);
		return;
	}
	flushing = 1;
	iunlock(&pagelock);

	off = r.min.y*gscreen.width*BY2WD+(r.min.x>>(3-gscreen.ldepth));
	page = off>>mode.apshift;
	off &= (1<<mode.apshift)-1;
	disp = KADDR(mode.aperture);
	hp = disp+off;
	off = r.min.y*gscreen.width*BY2WD+(r.min.x>>(3-gscreen.ldepth));
	sp = ((uchar*)gscreendata.data) + off;

	edisp = disp+mode.apsize;
	vgac->page(page);
	for(y = r.min.y; y < r.max.y; y++) {
		if(hp + incs < edisp) {
			memmove(hp, sp, len);
			sp += incs;
			hp += incs;
		}
		else {
			off = edisp - hp;
			if(off <= len){
				if(off > 0) {
					memmove(hp, sp, off);
				}
				vgac->page(++page);
				if(len - off > 0) {
					memmove(disp, sp+off, len - off);
				}
			}
			else {
				memmove(hp, sp, len);
				vgac->page(++page);
			}
			sp += incs;
			hp += incs - mode.apsize;
		}
	}
	ilock(&pagelock);
	flushing = 0;
	iunlock(&pagelock);
}

/* 
 * export screen to interpreter
 */
ulong*
attachscreen(Rectangle *r, int *ld, int *width, int *softscreen)
{
	*r = gscreen.r;
	*ld = gscreen.ldepth;
	*width = gscreen.width;
	*softscreen = useflush;

	return gscreendata.data;
}

void
detachscreen(void)
{
}

/*
 *  write a string to the screen
 */
void
screenputs(char *s, int n)
{
	int i;
	Rune r;
	char buf[4];

	if(novgascreen)
		return;
	if(islo() == 0) {
		/* don't deadlock trying to print in interrupt */
		if(!canlock(&screenlock))
			return;	
	} else
		lock(&screenlock);

	while(n > 0) {
		i = chartorune(&r, s);
		if(i == 0){
			s++;
			--n;
			continue;
		}
		memmove(buf, s, i);
		buf[i] = 0;
		n -= i;
		s += i;
		screenputc(buf);
	}

	flushmemscreen(update);
	update = nilbb;

	unlock(&screenlock);
}

static void
scroll(void)
{
	int o;
	Point p;
	Rectangle r;

	o = 6*h;
	r = Rpt(window.min, Pt(window.max.x, window.max.y-o));
	p = Pt(window.min.x, window.min.y+o);
	memdraw(&gscreen, r, &gscreen, p, memones, p);
	r = Rpt(Pt(window.min.x, window.max.y-o), window.max);
	memdraw(&gscreen, r, back, memzeros->r.min, memones, memzeros->r.min);

	curpos.y -= o;

	update = gscreen.r;
}

static void
bbmax(Rectangle *u, Rectangle *r)
{
	if(r->min.x < u->min.x)
		u->min.x = r->min.x;
	if(r->min.y < u->min.y)
		u->min.y = r->min.y;
	if(r->max.x > u->max.x)
		u->max.x = r->max.x;
	if(r->max.y > u->max.y)
		u->max.y = r->max.y;
}

static void
screenputc(char *buf)
{
	Point p;
	int w, pos;
	static int *xp;
	Rectangle r;
	static int xbuf[256];

	if(xp < xbuf || xp >= &xbuf[sizeof(xbuf)])
		xp = xbuf;

	switch(buf[0]) {
	case '\n':
		if(curpos.y+h >= window.max.y)
			scroll();
		curpos.y += h;
		screenputc("\r");
		break;
	case '\r':
		xp = xbuf;
		curpos.x = window.min.x;
		break;
	case '\t':
		p = memsubfontwidth(memdefont, " ");
		w = p.x;
		*xp++ = curpos.x;
		pos = (curpos.x-window.min.x)/w;
		pos = 8-(pos%8);
		curpos.x += pos*w;
		break;
	case '\b':
		if(xp <= xbuf)
			break;
		xp--;
		r = Rpt(Pt(*xp, curpos.y), Pt(curpos.x, curpos.y + h));
		memdraw(&gscreen, r, back, back->r.min, memones, back->r.min);
		curpos.x = *xp;
		bbmax(&update, &r);
		break;
	default:
		p = memsubfontwidth(memdefont, buf);
		w = p.x;

		if(curpos.x >= window.max.x-w)
			screenputc("\n");

		*xp++ = curpos.x;
		memimagestring(&gscreen, curpos, &conscol, memdefont, buf);
		r.min = curpos;
		r.max = addpt(curpos, p);
		bbmax(&update, &r);
		curpos.x += w;
	}
}

void
getcolor(ulong p, ulong *pr, ulong *pg, ulong *pb)
{
	ulong x;

	switch(gscreen.ldepth){
	default:
		x = 0xf;
		break;
	case 3:
		x = 0xff;
		break;
	}
	p &= x;
	p ^= x;
	lock(&palettelock);
	*pr = colormap[p][0];
	*pg = colormap[p][1];
	*pb = colormap[p][2];
	unlock(&palettelock);
}

int
setcolor(ulong p, ulong r, ulong g, ulong b)
{
	ulong x;

	switch(gscreen.ldepth){
	default:
		x = 0xf;
		break;
	case 3:
		x = 0xff;
		break;
	}
	p &= x;
	p ^= x;
	lock(&palettelock);
	colormap[p][0] = r;
	colormap[p][1] = g;
	colormap[p][2] = b;
	vgao(PaddrW, p);
	vgao(Pdata, r>>(32-6));
	vgao(Pdata, g>>(32-6));
	vgao(Pdata, b>>(32-6));
	unlock(&palettelock);
	return ~0;
}

void
setcursor(Point p)
{
	if (!ptinrect(p, gscreen.r))
		return;
	mouse.x = p.x;
	mouse.y = p.y;
	mouse.modify = 1;
	wakeup(&mouse.r);
	if (vgac->move != nil)
		vgac->move(p.x, p.y);
}

/*
 *	Software cursor code.  Interim version (for baseline).
 *	we may want to replace code here by memdraw primitives.
 */

enum {
	CUR_ENA = 0x01,		/* cursor is enabled */
	CUR_DRW = 0x02,		/* cursor is currently drawn */
	CUR_SWP = 0x10,		/* bit swap */
	CURSWID	= 16,
	CURSHGT	= 16,
};

typedef struct SWcursor {
	ulong	*fb;	/* screen frame buffer */
	Rectangle r;
	int	d;	/* ldepth of screen */
	int 	width;	/* width of screen in ulongs */
	int	x;
	int	y;
	int	hotx;
	int	hoty;
	uchar	cbwid;	/* cursor byte width */
	uchar	f;	/* flags */
	uchar	cwid;
	uchar	chgt;
	int	hidecount;
	uchar	data[CURSWID*CURSHGT];
	uchar	mask[CURSWID*CURSHGT];
	uchar	save[CURSWID*CURSHGT];
} SWcursor;

static Rectangle cursoroffrect;
static int	cursorisoff;

static void swcursorflush(int, int);
static void	swcurs_draw_or_undraw(SWcursor *);

static void
cursorupdate0(void)
{
	int inrect, x, y;

	x = mouse.x - swc->hotx;
	y = mouse.y - swc->hoty;
	inrect = (x >= cursoroffrect.min.x && x < cursoroffrect.max.x
		&& y >= cursoroffrect.min.y && y < cursoroffrect.max.y);
	if (cursorisoff == inrect)
		return;
	cursorisoff = inrect;
	if (inrect)
		swcurs_hide(swc);
	else {
		swc->hidecount = 0;
		swcurs_draw_or_undraw(swc);
	}
	swcursorflush(mouse.x, mouse.y);
}

void
cursorupdate(Rectangle r)
{
	lock(&screenlock);
	if (swc) {
		r.min.x -= 16;
		r.min.y -= 16;
		cursoroffrect = r;
		cursorupdate0();
	}
	unlock(&screenlock);
}

void
cursorenable(void)
{
	lock(&screenlock);
	if(vgac->enable == nil && !swc) {
		unlock(&screenlock);
		return;
	}
	if (swc) {
		swcurs_enable(swc);
		swcursorflush(mouse.x, mouse.y);
	} else {
		vgac->enable();
		vgac->load(&arrow);
	}
	unlock(&screenlock);
}

void
cursordisable(void)
{
	lock(&screenlock);
	if(vgac->disable == nil && !swc) {
		unlock(&screenlock);
		return;
	}
	if (swc) {
		swcurs_disable(swc);
		swcursorflush(mouse.x, mouse.y);
	} else
		vgac->disable();
	unlock(&screenlock);
}

void
mousetrack(int b, int dx, int dy)
{
	ulong tick;
	int x, y, oldx, oldy;
	static ulong lastt;
	static int lastclick, lastb;

	x = mouse.x + dx;
	if(x < gscreen.r.min.x)
		x = gscreen.r.min.x;
	if(x >= gscreen.r.max.x)
		x = gscreen.r.max.x;
	y = mouse.y + dy;
	if(y < gscreen.r.min.y)
		y = gscreen.r.min.y;
	if(y >= gscreen.r.max.y)
		y = gscreen.r.max.y;

	tick = TK2MS(MACHP(0)->ticks);
	mouse.b = b;
	if(b && lastb == 0) {
		if(b == lastclick && tick - lastt < 400
		   && abs(dx) < 10 && abs(dy) < 10)
			mouse.b |= (1<<4);
		lastt = tick;
		lastclick = b;
	}
	lastb = b;
	oldx = mouse.x;
	oldy = mouse.y;
	mouse.x = x;
	mouse.y = y;
	mouse.modify = 1;
	if (swc) {			/* XXX this test was inside screenlock - possibly a problem? */
		if (!canlock(&screenlock))
			return;		/* if can't lock, don't wake up stuff */
		swcurs_hide(swc);
		swc->x = x;
		swc->y = y;
		cursorupdate0();
		swcurs_unhide(swc);
		swcursorflush(oldx, oldy);
		swcursorflush(x, y);
		
		unlock(&screenlock);
		wakeup(&mouse.r);
	} else {
		wakeup(&mouse.r);
		if(vgac->move != nil)
			vgac->move(x, y);
	}
}

void
drawcursor(Drawcursor *c)
{
	Point p;
	Cursor curs, *cp;
	int j, i, h, bpl;
	uchar *bc, *bs, *cclr, *cset;

	if(vgac->load == nil && !swc)
		return;

	/* Set the default system cursor */
	if(!c || c->data == nil) {
		cp = &arrow /*&crosshair_black*/;
	} else {
		cp = &curs;
		p.x = c->hotx;
		p.y = c->hoty;
		curs.offset = p;
		bpl = bytesperline(Rect(c->minx, c->miny, c->maxx, c->maxy), 0);
	
		h = (c->maxy-c->miny)/2;
		if(h > 16)
			h = 16;
	
		bc = c->data;
		bs = c->data + h*bpl;
	
		cclr = curs.clr;
		cset = curs.set;
		for(i = 0; i < h; i++) {
			for(j = 0; j < 2; j++) {
				cclr[j] = bc[j];
				cset[j] = bs[j];
			}
			bc += bpl;
			bs += bpl;
			cclr += 2;
			cset += 2;
		}
	}
	if (swc)  {
		swcurs_load(swc, cp);
		swcursorflush(mouse.x, mouse.y);
	} else {
		vgac->load(cp);
	}
}

SWcursor*
swcurs_create(ulong *fb, int width, int ldepth, Rectangle r, int bitswap)
{
	SWcursor *swc = (SWcursor*)malloc(sizeof(SWcursor));
	swc->fb = fb;
	swc->r = r;
	swc->d = ldepth;
	swc->width = width;
	swc->f = bitswap ? CUR_SWP : 0;
	swc->x = swc->y = 0;
	swc->hotx = swc->hoty = 0;
	swc->hidecount = 0;
	return swc;
}

void
swcurs_destroy(SWcursor *swc)
{
	swcurs_disable(swc);
	free(swc);
}

static void
swcursorflush(int x, int y)
{
	Rectangle r;

	/* XXX a little too paranoid here */
	r.min.x = x-16;
	r.min.y = y-16;
	r.max.x = x+17;
	r.max.y = y+17;
	flushmemscreen(r);
}

static void
swcurs_draw_or_undraw(SWcursor *swc)
{
	uchar *p;
	uchar *cs;
	int w, vw;
	int x1 = swc->r.min.x;
	int y1 = swc->r.min.y;
	int x2 = swc->r.max.x;
	int y2 = swc->r.max.y; 
	int xp = swc->x - swc->hotx;
	int yp = swc->y - swc->hoty;
	int ofs;

	if(((swc->f & CUR_ENA) && (swc->hidecount <= 0))
			 == ((swc->f & CUR_DRW) != 0))
		return;
	w = swc->cbwid*BI2BY/(1 << swc->d);
	x1 = xp < x1 ? x1 : xp;
	y1 = yp < y1 ? y1 : yp;
	x2 = xp+w >= x2 ? x2 : xp+w;
	y2 = yp+swc->chgt >= y2 ? y2 : yp+swc->chgt;
	if(x2 <= x1 || y2 <= y1)
		return;
	p = (uchar*)(swc->fb + swc->width*y1)
		+ x1*(1 << swc->d)/BI2BY;
	y2 -= y1;
	x2 = (x2-x1)*(1 << swc->d)/BI2BY;
	vw = swc->width*BY2WD - x2;
	w = swc->cbwid - x2;
	ofs = swc->cbwid*(y1-yp)+(x1-xp);
	cs = swc->save + ofs;
	if((swc->f ^= CUR_DRW) & CUR_DRW) {
		uchar *cm = swc->mask + ofs; 
		uchar *cd = swc->data + ofs;
		while(y2--) {
			x1 = x2;
			while(x1--) {
				*p = ((*cs++ = *p) & *cm++) ^ *cd++;
				p++;
			}
			cs += w;
			cm += w;
			cd += w;
			p += vw;
		}
	} else {
		while(y2--) {
			x1 = x2;
			while(x1--) 
				*p++ = *cs++;
			cs += w;
			p += vw;
		}
	}
}

void
swcurs_hide(SWcursor *swc)
{
	++swc->hidecount;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_unhide(SWcursor *swc)
{
	if (--swc->hidecount < 0)
		swc->hidecount = 0;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_enable(SWcursor *swc)
{
	swc->f |= CUR_ENA;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_disable(SWcursor *swc)
{
	swc->f &= ~CUR_ENA;
	swcurs_draw_or_undraw(swc);
}

void
swcurs_load(SWcursor *swc, Cursor *c)
{
	int i, k;
	uchar *bc, *bs, *cd, *cm;
	static uchar bdv[4] = {0,Backgnd,Foregnd,0xff};
	static uchar bmv[4] = {0xff,0,0,0xff};
	int bits = 1<<swc->d;
	uchar mask = (1<<bits)-1;
	int bswp = (swc->f&CUR_SWP) ? 8-bits : 0;

	bc = c->clr;
	bs = c->set;

	swcurs_hide(swc);
	cd = swc->data;
	cm = swc->mask;
	swc->hotx = c->offset.x;
	swc->hoty = c->offset.y;
	swc->chgt = CURSHGT;
	swc->cwid = CURSWID;
	swc->cbwid = CURSWID*(1<<swc->d)/BI2BY;
	for(i = 0; i < CURSWID/BI2BY*CURSHGT; i++) {
		uchar bcb = *bc++;
		uchar bsb = *bs++;
		for(k=0; k<BI2BY;) {
			uchar cdv = 0;
			uchar cmv = 0;
			int z;
			for(z=0; z<BI2BY; z += bits) {
				int n = ((bsb&(0x80))|((bcb&(0x80))<<1))>>7;
				int s = z^bswp;
				cdv |= (bdv[n]&mask) << s;
				cmv |= (bmv[n]&mask) << s;
				bcb <<= 1;
				bsb <<= 1;
				k++;
			}
			*cd++ = cdv;
			*cm++ = cmv;
		}
	}
	swcurs_unhide(swc);
}

