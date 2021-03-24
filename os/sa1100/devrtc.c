#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

/*
 *  dallas DS1687 real time clock and non-volatile ram
 */

/*
 * rtc.h
 */
#define	RTC_ADDR	(0x0c800000)
#define	RTC_DATA	(0x0c000000)

#define	outb(p,v)	(*(uchar*)(p)=(v))
#define	inb(p) (*(uchar*)(p))

enum {
//	Paddr=		0x70,	/* address port */
//	Pdata=		0x71,	/* data port */
	Paddr= RTC_ADDR,
	Pdata= RTC_DATA,

	Seconds=	0x00,
	Minutes=	0x02,
	Hours=		0x04, 
	Mday=		0x07,
	Month=		0x08,
	Year=		0x09,
	Status=		0x0A,
		UIP=		1<<7,
		DV2=	1<<6,
		DV1=	1<<5,
		Bank1=	1<<4,
	Ctl=			0x0B,
		Set=		1<<7,
		IEN=		7<<4,
		Bin=		1<<2,
		M24=		1<<1,

	/* bank 1 */
	Model=		0x40,
	Serial=		0x41,
	  Nserial=		6,
	CRCbyte=		0x47,
	Century=		0x48,
	Nvaddr=		0x50,
	Nvdata=		0x53,

	Nvoff=		0,	/* where usable nvram lives (bank 1) */
	Nvsize=		128,

	Nbcd=		6,
	BINMODE=	1,	/* force binary mode */
};

typedef struct Rtc	Rtc;
struct Rtc
{
	int	sec;
	int	min;
	int	hour;
	int	mday;
	int	mon;
	int	year;
};

QLock rtclock;	/* mutex on clock operations */

enum{
	Qrtc = 1,
	Qnvram,
	Qrtcid,
};

Dirtab rtcdir[]={
	"nvram",	{Qnvram, 0},	Nvsize,	0664,
	"rtcid",	{Qrtcid, 0}, 0,	0444,
	"rtc",		{Qrtc, 0},	0,	0664,
};

static ulong rtc2sec(Rtc*);
static void sec2rtc(ulong, Rtc*);

static Chan*
rtcattach(char* spec)
{
	return devattach('r', spec);
}

static int	 
rtcwalk(Chan* c, char* name)
{
	return devwalk(c, name, rtcdir, nelem(rtcdir), devgen);
}

static void	 
rtcstat(Chan* c, char* dp)
{
	devstat(c, dp, rtcdir, nelem(rtcdir), devgen);
}

static Chan*
rtcopen(Chan* c, int omode)
{
	Osenv *o;

	omode = openmode(omode);
	o = up->env;
	switch(c->qid.path){
	case Qrtc:
		if(strcmp(o->user, eve)!=0 && omode!=OREAD)
			error(Eperm);
		break;
	case Qnvram:
		if(strcmp(o->user, eve)!=0)
			error(Eperm);
		break;
	case Qrtcid:
		if(omode!=OREAD)
			error(Eperm);
		break;
	}
	return devopen(c, omode, rtcdir, nelem(rtcdir), devgen);
}

static void	 
rtcclose(Chan*)
{
}

#define GETBCD(o) ((bcdclock[o]&0xf) + 10*(bcdclock[o]>>4))

static long	 
_rtctime(void)
{
	uchar bcdclock[Nbcd];
	Rtc rtc;
	int i;

	/* don't do the read until the clock is no longer busy */
	for(i = 0; i < 10000; i++){
		outb(Paddr, Status);
		if(inb(Pdata) & UIP)
			continue;

		/* read clock values */
		outb(Paddr, Seconds);	bcdclock[0] = inb(Pdata);
		outb(Paddr, Minutes);	bcdclock[1] = inb(Pdata);
		outb(Paddr, Hours);	bcdclock[2] = inb(Pdata);
		outb(Paddr, Mday);	bcdclock[3] = inb(Pdata);
		outb(Paddr, Month);	bcdclock[4] = inb(Pdata);
		outb(Paddr, Year);	bcdclock[5] = inb(Pdata);

		outb(Paddr, Status);
		if((inb(Pdata) & UIP) == 0)
			break;
	}

	outb(Paddr, Ctl);
	if((inb(Pdata)&Bin) == 0){
		/*
		 *  convert from BCD
		 */
		rtc.sec = GETBCD(0);
		rtc.min = GETBCD(1);
		rtc.hour = GETBCD(2);
		rtc.mday = GETBCD(3);
		rtc.mon = GETBCD(4);
		rtc.year = GETBCD(5);
	}else{
		rtc.sec = bcdclock[0];
		rtc.min = bcdclock[1];
		rtc.hour = bcdclock[2];
		rtc.mday = bcdclock[3];
		rtc.mon = bcdclock[4];
		rtc.year = bcdclock[5];
	}

	/*
	 *  the world starts jan 1 1970
	 */
	if(rtc.year < 70)
		rtc.year += 2000;
	else
		rtc.year += 1900;
	return rtc2sec(&rtc);
}

static Lock rtlock;

long
rtctime(void)
{
	int i;
	long t, ot;

	ilock(&rtlock);

	/* loop till we get two reads in a row the same */
	t = _rtctime();
	for(i = 0; i < 100; i++){
		ot = t;
		t = _rtctime();
		if(ot == t)
			break;
	}
	if(i == 100) print("we are boofheads\n");

	iunlock(&rtlock);
	
	return t;
}

#define PUTBCD(n,o) bcdclock[o] = (n % 10) | (((n / 10) % 10)<<4)

void
setrtc(ulong secs)
{
	Rtc rtc;
	int ctl, status, bcdclock[Nbcd+1], cent;

	/*
	 *  convert to bcd if required
	 */
	sec2rtc(secs, &rtc);
	cent = rtc.year/100;
	qlock(&rtclock);
	outb(Paddr, Ctl);
	if(BINMODE == 0 && (inb(Pdata) & Bin) == 0){
		PUTBCD(rtc.sec, 0);
		PUTBCD(rtc.min, 1);
		PUTBCD(rtc.hour, 2);
		PUTBCD(rtc.mday, 3);
		PUTBCD(rtc.mon, 4);
		PUTBCD(rtc.year, 5);
		PUTBCD(cent, 6);
	}else{
		bcdclock[0] = rtc.sec;
		bcdclock[1] = rtc.min;
		bcdclock[2] = rtc.hour;
		bcdclock[3] = rtc.mday;
		bcdclock[4] = rtc.mon;
		bcdclock[5] = rtc.year%100;
		bcdclock[6] = cent;
	}

	/*
	 *  write the clock
	 */
	outb(Paddr, Ctl);
	ctl = inb(Pdata) | M24;
	if(BINMODE)
		ctl |= Bin;
	outb(Pdata, Set | ctl);	/* stop update */
	outb(Paddr, Status);
	outb(Pdata, inb(Pdata)|Bank1|DV1|DV2);	/* reset divide chain, set bank 1 */
	outb(Paddr, Seconds);	outb(Pdata, bcdclock[0]);
	outb(Paddr, Minutes);	outb(Pdata, bcdclock[1]);
	outb(Paddr, Hours);	outb(Pdata, bcdclock[2]);
	outb(Paddr, Mday);	outb(Pdata, bcdclock[3]);
	outb(Paddr, Month);	outb(Pdata, bcdclock[4]);
	outb(Paddr, Year);	outb(Pdata, bcdclock[5]);
	outb(Paddr, Century); outb(Pdata, bcdclock[6]);
	outb(Paddr, Ctl); outb(Pdata, ctl);
	outb(Paddr, Status);
	status = inb(Pdata) & ~UIP;
	outb(Pdata, status | DV1);
	qunlock(&rtclock);
}

static long	 
rtcread(Chan* c, void* buf, long n, ulong offset)
{
	ulong t;
	char *a;
	uchar id[Nserial+1];
	char str[64];
	int i;
	uvlong sid;

	if(c->qid.path & CHDIR)
		return devdirread(c, buf, n, rtcdir, nelem(rtcdir), devgen);

	switch(c->qid.path){
	case Qrtc:
		qlock(&rtclock);
		t = rtctime();
		qunlock(&rtclock);
		n = readnum(offset, buf, n, t, 12);
		return n;

	case Qrtcid:
		qlock(&rtclock);
		outb(Paddr, Status);
		outb(Pdata, DV1|Bank1);
		for(i=0; i<Nserial+1; i++){	/* include model ID but not CRC */
			outb(Paddr, Model+i);
			id[i] = inb(Pdata);
		}
		qunlock(&rtclock);
		sid = 0;
		for(i=nelem(id); --i>=0;)
			sid = (sid<<8) | id[i];
		snprint(str, sizeof(str), "%.lld", sid);
		return readstr(offset, buf, n, str);

	case Qnvram:
		a = buf;
		if(waserror()){
			qunlock(&rtclock);
			nexterror();
		}
		qlock(&rtclock);
		outb(Paddr, Status);
		outb(Pdata, DV1|Bank1);
		for(t = offset; t < offset + n; t++){
			if(t >= Nvsize)
				break;
			outb(Paddr, Nvaddr);
			outb(Pdata, Nvoff+t);
			outb(Paddr, Nvdata);
			*a++ = inb(Pdata);
		}
		qunlock(&rtclock);
		poperror();
		return t - offset;
	}
	error(Ebadarg);
	return 0;
}

static long	 
rtcwrite(Chan* c, void* buf, long n, ulong offset)
{
	int t;
	char *a;
	ulong secs;
	char *cp, sbuf[32];

	switch(c->qid.path){
	case Qrtc:
		/*
		 *  set the time
		 */
		if(offset != 0 || n >= sizeof(sbuf)-1)
			error(Ebadarg);
		memmove(sbuf, buf, n);
		sbuf[n] = '\0';
		cp = sbuf;
		while(*cp){
			if(*cp>='0' && *cp<='9')
				break;
			cp++;
		}
		secs = strtoul(cp, 0, 0);
		setrtc(secs);
		return n;

	case Qnvram:
		a = buf;
		if(waserror()){
			qunlock(&rtclock);
			nexterror();
		}
		qlock(&rtclock);
		outb(Paddr, Status);
		outb(Pdata, DV1|Bank1);
		for(t = offset; t < offset + n; t++){
			if(t >= Nvsize)
				break;
			outb(Paddr, Nvaddr);
			outb(Pdata, Nvoff+t);
			outb(Paddr, Nvdata);
			outb(Pdata, *a++);
		}
		qunlock(&rtclock);
		poperror();
		return t - offset;
	}
	error(Ebadarg);
	return 0;
}

Dev rtcdevtab = {
	'r',
	"rtc",

	devreset,
	devinit,
	rtcattach,
	devdetach,
	devclone,
	rtcwalk,
	rtcstat,
	rtcopen,
	devcreate,
	rtcclose,
	rtcread,
	devbread,
	rtcwrite,
	devbwrite,
	devremove,
	devwstat,
};

#define SEC2MIN 60L
#define SEC2HOUR (60L*SEC2MIN)
#define SEC2DAY (24L*SEC2HOUR)

/*
 *  days per month plus days/year
 */
static	int	dmsize[] =
{
	365, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};
static	int	ldmsize[] =
{
	366, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
};

/*
 *  return the days/month for the given year
 */
static int*
yrsize(int yr)
{
	if((yr % 4 == 0)&&((yr % 100!=0)||(yr % 400==0)))
		return ldmsize;
	else
		return dmsize;
}

/*
 *  compute seconds since Jan 1 1970
 */
static ulong
rtc2sec(Rtc *rtc)
{
	ulong secs;
	int i;
	int *d2m;

	secs = 0;

	/*
	 *  seconds per year
	 */
	for(i = 1970; i < rtc->year; i++){
		d2m = yrsize(i);
		secs += d2m[0] * SEC2DAY;
	}

	/*
	 *  seconds per month
	 */
	d2m = yrsize(rtc->year);
	for(i = 1; i < rtc->mon; i++)
		secs += d2m[i] * SEC2DAY;

	secs += (rtc->mday-1) * SEC2DAY;
	secs += rtc->hour * SEC2HOUR;
	secs += rtc->min * SEC2MIN;
	secs += rtc->sec;

	return secs;
}

/*
 *  compute rtc from seconds since Jan 1 1970
 */
static void
sec2rtc(ulong secs, Rtc *rtc)
{
	int d;
	long hms, day;
	int *d2m;

	/*
	 * break initial number into days
	 */
	hms = secs % SEC2DAY;
	day = secs / SEC2DAY;
	if(hms < 0) {
		hms += SEC2DAY;
		day -= 1;
	}

	/*
	 * generate hours:minutes:seconds
	 */
	rtc->sec = hms % 60;
	d = hms / 60;
	rtc->min = d % 60;
	d /= 60;
	rtc->hour = d;

	/*
	 * year number
	 */
	if(day >= 0)
		for(d = 1970; day >= *yrsize(d); d++)
			day -= *yrsize(d);
	else
		for (d = 1970; day < 0; d--)
			day += *yrsize(d-1);
	rtc->year = d;

	/*
	 * generate month
	 */
	d2m = yrsize(rtc->year);
	for(d = 1; day >= d2m[d]; d++)
		day -= d2m[d];
	rtc->mday = day + 1;
	rtc->mon = d;

	return;
}

uchar
nvramread(int addr)
{
	uchar data;

	qlock(&rtclock);
	outb(Paddr, Nvaddr);
	outb(Pdata, Nvoff+addr);
	outb(Paddr, Nvdata);
	data = inb(Pdata);
	qunlock(&rtclock);
	return data;
}

void
nvramwrite(int addr, uchar data)
{
	qlock(&rtclock);
	outb(Paddr, Nvaddr);
	outb(Pdata, Nvoff+addr);
	outb(Paddr, Nvdata);
	outb(Pdata, data);
	qunlock(&rtclock);
}
