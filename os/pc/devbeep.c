/*
 *  Speaker Interface
 */
#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

/* write frequency in HZ and duration in millisecs to beep file to cause sound.
  * frequency of 0 gives silence for requested interval
  */

enum{
	Qdir,
	Qbeep,
};

static Dirtab beeptab[]={
	"beep",		{Qbeep, 0}, 		0,	0222,
};

QLock beeplock;
Rendez beeprend;

static void
beepreset(void)
{
	/* switch off speaker */
	outb(0x61, inb(0x61)&0xfc);
}

static Chan*
beepattach(char* spec)
{
	return devattach('a', spec);
}

static int
beepwalk(Chan* c, char* name)
{
	return devwalk(c, name, beeptab, nelem(beeptab), devgen);
}

static void
beepstat(Chan* c, char* db)
{
	devstat(c, db, beeptab, nelem(beeptab), devgen);
}

static Chan*
beepopen(Chan* c, int omode)
{
	return devopen(c, omode, beeptab, nelem(beeptab), devgen);
}

static void
beepclose(Chan*)
{
}

static long
beepread(Chan* c, void* buf, long n, ulong offset)
{
	USED(offset);

	switch(c->qid.path & ~CHDIR) {
	case Qdir:
		return devdirread(c, buf, n, beeptab, nelem(beeptab), devgen);
	case Qbeep:
		error(Eperm);
		return 0;
	default:
		return 0;
	}
	return n;
}

static long
beepwrite(Chan* c, void* buf, long n, ulong offset)
{
	int f, d, nf;
	char *cp;
	char cmd[32];
	char *fields[3];

	USED(offset);
	switch(c->qid.path & ~CHDIR){
	case Qbeep:
		qlock(&beeplock);
		if(waserror()){
			outb(0x61, inb(0x61)&0xfc);	/* switch off */
			qunlock(&beeplock);
			nexterror();
		}
		if (n > sizeof(cmd)-1)
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		nf = getfields(cmd, fields, nelem(fields), 1, " \t\n");	
		if (nf < 2)
			error(Ebadarg);
		f = strtoul(fields[0], &cp, 0);
		if (*cp || f < 0)
			error(Ebadarg);
		d = strtoul(fields[1], &cp, 0);
		if (*cp || d < 0)
			error(Ebadarg);
		if (f != 0) {
			f = 1193180/f;			/* HZ -> counter */
			outb(0x43, 0xb6);
			outb(0x42, f);
			outb(0x42, f>>8);
			outb(0x61, inb(0x61)|3);	/* enable counter 2 */
		}
		tsleep(&beeprend, return0, 0, d);
		outb(0x61, inb(0x61)&0xfc);
		poperror();
		qunlock(&beeplock);
		return n;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev beepdevtab = {				/* defaults in dev.c */
	'a',
	"beep",

	beepreset,					/* devreset */
	devinit,						/* devinit */
	beepattach,
	devdetach,
	devclone,						/* devclone */
	beepwalk,
	beepstat,
	beepopen,
	devcreate,					/* devcreate */
	beepclose,
	beepread,
	devbread,						/* devbread */
	beepwrite,
	devbwrite,					/* devbwrite */
	devremove,					/* devremove */
	devwstat,						/* devwstat */
};
