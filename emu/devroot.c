#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	Qdir,
	Qdev,
	Qenv,
	Qprog,
	Qnet,
	Qnetdotalt,
	Qchan,
	Qnvfs
};

static
Dirtab slashdir[] =
{
	"dev",		{CHDIR|Qdev},		0,	0555,
	"prog",		{CHDIR|Qprog},		0,	0555,
	"net",		{CHDIR|Qnet},		0,	0555,
	"net.alt",		{CHDIR|Qnetdotalt},		0,	0555,
	"chan",		{CHDIR|Qchan},		0,	0555,
	"nvfs",		{CHDIR|Qnvfs},		0,	0555,
	"env",		{CHDIR|Qenv},		0,	0555,
};

static Chan *
rootattach(char *spec)
{
	return devattach('/', spec);
}

static int
rootwalk(Chan *c, char *name)
{
	if(strcmp(name, "..") == 0){
		c->qid.path = Qdir|CHDIR;
		return 1;
	}
	if((c->qid.path & ~CHDIR) != Qdir)
		return 0;

	return devwalk(c, name, slashdir, nelem(slashdir), devgen);
}

static void
rootstat(Chan *c, char *db)
{
	devstat(c, db, slashdir, nelem(slashdir), devgen);
}

static Chan *
rootopen(Chan *c, int omode)
{
	return devopen(c, omode, slashdir, nelem(slashdir), devgen);
}

static void
rootclose(Chan *c)
{
	USED(c);
}

static long
rootread(Chan *c, void *a, long n, ulong offset)
{
	USED(offset);
	switch((ulong)c->qid.path & ~CHDIR) {
	default:
		return 0;
	case Qdir:
		return devdirread(c, a, n, slashdir, nelem(slashdir), devgen);
	}	
}

static long
rootwrite(Chan *ch, void *a, long n, ulong offset)
{
	USED(ch);
	USED(a);
	USED(n);
	USED(offset);
	error(Eperm);
	return -1;
}

Dev rootdevtab = {
	'/',
	"root",

	devinit,
	rootattach,
	devclone,
	rootwalk,
	rootstat,
	rootopen,
	devcreate,
	rootclose,
	rootread,
	devbread,
	rootwrite,
	devbwrite,
	devremove,
	devwstat
};
