#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	"io.h"
#include	"archipe.h"

#define	MB	(1024*1024)
#define	FPGASIZE	(8*MB)
#define	FPGATMR	(2-1)	/* timer number: origin 0 */
#define	TIMERSH	(FPGATMR*4)	/* field shift */

/*
 * provisional FPGA interface for testing
 */

enum{
	Qmemb = 1,
	Qprog,
	Qctl,
	Qcfg,
	Qclk,
	Qstatus,
};

static struct {
	QLock;
	int	status;
} fpga;

static void resetfpga(void);
static void	startfpga(int);
static int endfpga(void);
static void vclkenable(int);

static Dirtab fpgadir[]={
	"fpgamem",		{Qmemb, 0},	FPGASIZE,	0666,
	"fpgaprog",	{Qprog, 0},	0,	0666,
	"fpgastat",	{Qstatus, 0},	0,	0444,
	"fpgactl",		{Qctl, 0},		0,	0666,
	"fpgacfg",		{Qcfg, 0},		1,	0666,
	"fpgaclk",		{Qclk, 0},		1,	0666,
};

static void
fpgareset(void)
{
	vclkenable(1);
	resetfpga();
}

static Chan*
fpgaattach(char *spec)
{
	return devattach('G', spec);
}

static int	 
fpgawalk(Chan *c, char *name)
{
	return devwalk(c, name, fpgadir, nelem(fpgadir), devgen);
}

static void	 
fpgastat(Chan *c, char *dp)
{
	devstat(c, dp, fpgadir, nelem(fpgadir), devgen);
}

static Chan*
fpgaopen(Chan *c, int omode)
{
	return devopen(c, omode, fpgadir, nelem(fpgadir), devgen);
}

static void
fpgaclose(Chan *c)
{
	if(c->flag & COPEN && c->qid.path == Qprog)
		fpga.status = endfpga();
}

static long	 
fpgaread(Chan *c, void *buf, long n, ulong offset)
{
	if(c->qid.path & CHDIR)
		return devdirread(c, buf, n, fpgadir, nelem(fpgadir), devgen);

	switch(c->qid.path){
	case Qmemb:
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmove(buf, (uchar*)KADDR(FPGAMEM)+offset, n);
		return n;
	case Qclk:
		if(offset >= 1)
			return 0;
		*(uchar*)buf = *(uchar*)KADDR(CLOCKCR);
		return 1;
	case Qcfg:
		if(offset >= 1)
			return 0;
		*(uchar*)buf = *(uchar*)KADDR(FPGACR);
		return 1;
	case Qstatus:
		return readnum(offset, buf, n, fpga.status, 2);
	case Qctl:
	case Qprog:
		return 0;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static long	 
fpgawrite(Chan *c, void *buf, long n, ulong offset)
{
	int i, j, v;
	char *cfg, *cp, sbuf[32];

	switch(c->qid.path){
	case Qmemb:
		if(offset >= FPGASIZE)
			return 0;
		if(offset+n >= FPGASIZE)
			n = FPGASIZE-offset;
		memmove((uchar*)KADDR(FPGAMEM)+offset, buf, n);
		return n;
	case Qctl:
		if(n > sizeof(sbuf)-1)
			n = sizeof(sbuf)-1;
		memmove(sbuf, buf, n);
		sbuf[n] = 0;
		if(strcmp(sbuf, "reset") == 0)
			resetfpga();
		else if(strcmp(sbuf, "start") == 0)
			startfpga(1);
		else
			error(Ebadarg);
		return n;
	case Qprog:
		if(offset == 0)
			resetfpga();
		cfg = KADDR(FPGACR);
		cp = buf;
		for(i=0; i<n; i++){
			v = *cp++;
			for(j=0; j<8; j++){
				*cfg = v&1;
				v >>= 1;
			}
		}
		return n;
	}
	error(Egreg);
	return 0;		/* not reached */
}

static void
resetfpga(void)
{
	IMM *io;

	io = ioplock();
	io->pcpar &= ~nCONFIG;
	io->pcdir |= nCONFIG;
	io->pcdat &= ~nCONFIG;
	microdelay(500);
	io->pcdat |= nCONFIG;
	fpga.status = (io->pipr & 0xC000)>>12;
	iopunlock();
}

static int
endfpga(void)
{
	int j;
	char *p;

	p = KADDR(FPGACR);
	for(j=0; j<20; j++)
		*p = 0;
	delay(1);
print("pipr=%8.8lux endfpga=%8.8lux\n", &m->iomem->pipr, m->iomem->pipr);
	return (m->iomem->pipr & 0xC000)>>12;
}

static void
startfpga(int scale)
{
	IMM *io;

	io = ioplock();
	io->tgcr &= ~(0xF<<TIMERSH);
	io->tmr2 = ((scale&0xFF)<<8) | 0x2A;
	io->tcn2 = 0;
	io->trr2 = 0;
	io->ter2 = 0xFFFF;
	io->tgcr |= 0x1<<TIMERSH;
	io->padir |= BCLK;
	io->papar |= BCLK;
	io->pbpar &= ~EnableVCLK;
	io->pbdir |= EnableVCLK;
	io->pbdat |= EnableVCLK;
	iopunlock();
}

static void
vclkenable(int i)
{
	IMM *io;

	io = ioplock();
	io->pbpar &= ~EnableVCLK;
	io->pbdir |= EnableVCLK;
	if(i)
		io->pbdat |= EnableVCLK;
	else
		io->pbdat &= ~EnableVCLK;
	iopunlock();
}

Dev fpgadevtab = {
	'G',
	"fpga",

	fpgareset,
	devinit,
	fpgaattach,
	devdetach,
	devclone,
	fpgawalk,
	fpgastat,
	fpgaopen,
	devcreate,
	fpgaclose,
	fpgaread,
	devbread,
	fpgawrite,
	devbwrite,
	devremove,
	devwstat,
};
