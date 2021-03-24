#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"
#include	<isa.h>
#include	"runt.h"

static void	cpxec(Prog *);
static void memprof(int, Heap*, ulong);

extern	Inst*	pc2dispc(Inst*, Module*);

static	int	interval = 100;	/* Sampling interval in milliseconds */

enum
{
	HSIZE	= 32,
};

#define HASH(m)	((m)%HSIZE)

/* cope with  multiple profilers some day */

typedef struct Record Record;
struct Record
{
	int	id;
	char	name[NAMELEN];
	char*	path;
	Inst*	base;
	int	size;
	// Module*	m;
	ulong	mtime;
	Qid	qid;
	Record*	hash;
	Record*	link;
	ulong	bucket[1];
};

struct
{
	Lock	l;
	vlong	time;
	Record*	hash[HSIZE];
	Record*	list;
} profile;

typedef struct Pmod Pmod;
struct Pmod
{
	char*	name;
	Pmod*	link;
} *pmods;
	
#define QSHIFT	4
#define QID(q)		((ulong)(q).path&0xf)
#define QPID(pid)	(((pid)<<QSHIFT)&~CHDIR)
#define PID(q)		((q).vers)
#define PATH(q)	((ulong)(q).path&~(CHDIR|((1<<QSHIFT)-1)))

enum
{
	Qname,
	Qpath,
	Qhist,
	Qpctl,
	Qctl,
};

Dirtab profdir[] =
{
	"name",		{Qname},	0,			0444,
	"path",		{Qpath},	0,			0444,
	"histogram",	{Qhist},	0,			0444,
	"pctl",		{Qpctl},	0,			0222,
	"ctl",			{Qctl},	0,			0222,
};

enum{
	Pnil,	/* null profiler */
	Psam,	/* sampling profiler */
	Pcov,	/* coverage profiler */
	Pmem,	/* memory profiler */
};

static int profiler = Pnil;

static int ids;
static int samplefn;

static void sampler(void*);

static Record*
getrec(int id)
{
	Record *r;

	for(r = profile.list; r != nil; r = r->link)
		if(r->id == id)
			break;
	return r;
}

static void
addpmod(char *m)
{
	Pmod *p = malloc(sizeof(Pmod));

	if(p == nil)
		return;
	p->name = malloc(strlen(m)+1);
	if(p->name == nil){
		free(p);
		return;
	}
	strcpy(p->name, m);
	p->link = pmods;
	pmods = p;
}

static void
freepmods(void)
{
	Pmod *p, *np;

	for(p = pmods; p != nil; p = np){
		free(p->name);
		np = p->link;
		free(p);
	}
	pmods = nil;
}

static int
inpmods(char *m)
{
	Pmod *p;

	for(p = pmods; p != nil; p = p->link)
		if(strcmp(p->name, m) == 0)
			return 1;
	return 0;
}

static void
freeprof(void)
{
	int i;
	Record *r, *nr;

	ids = 0;
	profiler = Pnil;
	freepmods();
	for(r = profile.list; r != nil; r = nr){
		free(r->path);
		nr = r->link;
		free(r);
	}
	profile.list = nil;
	profile.time = 0;
	for(i = 0; i < HSIZE; i++)
		profile.hash[i] = nil;
}

static int
profgen(Chan *c, Dirtab *d, int nd, int s, Dir *dp)
{
	Qid qid;
	Record *r;
	char buf[NAMELEN];
	ulong path, perm, len;
	Dirtab *tab;

	USED(d);
	USED(nd);

	if(s == DEVDOTDOT) {
		qid.path = CHDIR;
		qid.vers = 0;
		devdir(c, qid, "#P", 0, eve, 0555, dp);
		return 1;
	}

	if(c->qid.path == CHDIR) {
		acquire();
		if(s-- == 0){
			tab = &profdir[Qctl];
			qid.path = PATH(c->qid)|tab->qid.path;
			qid.vers = c->qid.vers;
			devdir(c, qid, tab->name, tab->length, eve, tab->perm, dp);
			release();
			return 1;
		}
		r = profile.list;
		while(s-- && r != nil)
			r = r->link;
		if(r == nil) {
			release();
			return -1;
		}
		sprint(buf, "%.8lux", (ulong)r->id);
		qid.path = CHDIR|(r->id<<QSHIFT);
		qid.vers = r->id;
		devdir(c, qid, buf, 0, eve, CHDIR|0555, dp);
		release();
		return 1;
	}
	if(s >= nelem(profdir)-1)
		error(Enonexist);	/* was return -1; */
	tab = &profdir[s];
	path = PATH(c->qid);

	acquire();
	r = getrec(PID(c->qid));
	if(r == nil) {
		release();
		error(Enonexist);	/* was return -1; */
	}

	perm = tab->perm;
	len = tab->length;
	qid.path = path|tab->qid.path;
	qid.vers = c->qid.vers;
	devdir(c, qid, tab->name, len, eve, perm, dp);
	release();
	return 1;
}

static Chan*
profattach(char *spec)
{
	return devattach('P', spec);
}

static int
profwalk(Chan *c, char *name)
{
	if(strcmp(name, "..") == 0) {
		c->qid.path = CHDIR;
		return 1;
	}
	return devwalk(c, name, 0, 0, profgen);
}

static void
profstat(Chan *c, char *db)
{
	devstat(c, db, 0, 0, profgen);
}

static Chan*
profopen(Chan *c, int omode)
{
	int qid;
	Record *r;

	if(c->qid.path & CHDIR) {
		if(omode != OREAD)
			error(Eisdir);
		c->mode = openmode(omode);
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	if(omode&OTRUNC)
		error(Eperm);

	qid = QID(c->qid);
	if(qid == Qctl || qid == Qpctl){
		if (omode != OWRITE)
			error(Eperm);
	}
	else{
		if(omode != OREAD)
			error(Eperm);
	}

	if(qid != Qctl){
		acquire();
		r = getrec(PID(c->qid));
		release();
		if(r == nil)
			error(Ethread);
	}

	c->offset = 0;
	c->flag |= COPEN;
	c->mode = openmode(omode);
	if(QID(c->qid) == Qhist)
		c->u.aux = (void*)0;
	return c;
}

static void
profwstat(Chan *c, char *dp)
{
	Dir d;
	Record *r;

	if(strcmp(up->env->user, eve))
		error(Eperm);
	if(CHDIR & c->qid.path)
		error(Eperm);
	acquire();
	r = getrec(PID(c->qid));
	release();
	if(r == nil)
		error(Ethread);
	convM2D(dp, &d);
	d.mode &= 0777;
}

static void
profclose(Chan *c)
{
	USED(c);
}

static long
profread(Chan *c, void *va, long n, ulong offset)
{
	int i;
	Record *r;
	char *a = va;
	char buf[128];

	if(c->qid.path & CHDIR)
		return devdirread(c, a, n, 0, 0, profgen);
	acquire();
	r = getrec(PID(c->qid));
	release();
	if(r == nil)
		error(Ethread);
	switch(QID(c->qid)){
	case Qname:
		snprint(buf, sizeof(buf), "%s", r->name);
		return readstr(offset, va, n, buf);
	case Qpath:
		snprint(buf, sizeof(buf), "%s", r->path);
		return readstr(offset, va, n, buf);
	case Qhist:
		i = (int)c->u.aux;
		while(i < r->size && r->bucket[i] == 0)
			i++;
		if(i >= r->size)
			return 0;
		c->u.aux = (void*)(i+1);
		if(n < 20)
			error(Etoosmall);
		return sprint(a, "%d %lud", i, r->bucket[i]);
	case Qctl:
		error(Eperm);
	}
	return 0;
}

static long
profwrite(Chan *c, void *va, long n, ulong offset)
{
	int i;
	char *a = va;
	char buf[128], *fields[128];

	USED(va);
	USED(n);
	USED(offset);

	if(c->qid.path & CHDIR)
		error(Eisdir);
	switch(QID(c->qid)){
	case Qctl:
		if(n > sizeof(buf)-1)
			n = sizeof(buf)-1;
		memmove(buf, a, n);
		buf[n] = 0;
		i = getfields(buf, fields, nelem(fields), 1, " \t\n");
		if(i > 0 && strcmp(fields[0], "module") == 0){
			freepmods();
			while(--i > 0)
				addpmod(fields[i]);
			return n;
		}
		if(i == 1){
			if(strcmp(fields[0], "start") == 0){
				if(profiler == Pnil) {
					profiler = Psam;
					if(!samplefn){
						samplefn = 1;
						kproc("prof", sampler, 0, 0);
					}
				}
			}
			else if(strcmp(fields[0], "startmp") == 0){
				if(profiler == Pnil){
					profiler = Pmem;
					heapmonitor = memprof;
				}
			}
			else if(strcmp(fields[0], "stop") == 0)
				profiler = Pnil;
			else if(strcmp(fields[0], "end") == 0){
				profiler = Pnil;
				freeprof();
				interval = 100;
			}
			else
				error(Ebadarg);
		}
		else if (i == 2){
			if(strcmp(fields[0], "interval") == 0)
				interval = strtoul(fields[1], nil, 0);
			else if(strcmp(fields[0], "startcp") == 0){
				Prog *p;

				acquire();
				p = progpid(strtoul(fields[1], nil, 0));
				if(p == nil){
					release();
					return -1;
				}
				if(profiler == Pnil){
					profiler = Pcov;
					p->xec = cpxec;
				}
				release();
			}
			else
				error(Ebadarg);
		}
		else
			error(Ebadarg);
		return n;
	default:
		error(Eperm);
	}
	return 0;
}

static Record*
newmodule(Module *m, int vm, int scale, int origin)
{
	int dsize;
	Record *r, **l;

	if(!vm)
		acquire();
	if((m->compiled && m->pctab == nil) || m->prog == nil) {
		if(!vm)
			release();
		return nil;
	}
/* print("newmodule %x %s %s %d %d %d\n", m, m->name, m->path, m->mtime, m->qid.path, m->qid.vers); */
	if(m->compiled)
		dsize = m->nprog * sizeof(r->bucket[0]);
	else
		dsize = (msize(m->prog)/sizeof(Inst)) * sizeof(r->bucket[0]);
	dsize *= scale;
	dsize += origin;
	r = malloc(sizeof(Record)+dsize);
	if(r == nil) {
		if(!vm)
			release();
		return nil;
	}

	r->id = ++ids;
	if(ids == (1<<16)-1)
		ids = 0;
	strcpy(r->name, m->name);
	r->path = strdup(m->path);
	r->base = m->prog;
	r->size = dsize/sizeof(r->bucket[0]);
	// r->m = m;
	r->mtime = m->mtime;
	r->qid.path = m->qid.path;
	r->qid.vers = m->qid.vers;
	memset(r->bucket, 0, dsize);
	r->link = profile.list;
	profile.list = r;

	l = &profile.hash[HASH(m->mtime)];
	r->hash = *l;
	*l = r;

	if(!vm)
		release();
	return r;
}

static Record*
mlook(Module *m, int vm, int scale, int origin)
{
	Record *r;

	for(r = profile.hash[HASH(m->mtime)]; r; r = r->hash){
		// if(r->m == m){	/* bug - r->m could be old exited module */
		if(r->mtime == m->mtime && r->qid.path == m->qid.path && r->qid.vers == m->qid.vers && strcmp(r->name, m->name) == 0 && strcmp(r->path, m->path) == 0){
			r->base = m->prog;
			return r;
		}
	}
	if(pmods == nil || inpmods(m->name) || inpmods(m->path)){
		if(0 && profiler == Pmem)
			heapmonitor = nil;
		r = newmodule(m, vm, scale, origin);
		if(0 && profiler == Pmem)
			heapmonitor = memprof;
		return r;
	}
	return nil;
}

static void
sampler(void* a)
{
	int i;
	Module *m;
	Modlink *ml;
	uchar *fp;
	Frame *f;
	Record *r;
	Inst *p;

	USED(a);
	for(;;) {
		osmillisleep(interval);
		if(profiler != Psam)
			break;
		lock(&profile.l);
		profile.time += interval;
if(1){	/* make this an option or permanent ? */
		r = nil;
		m = nil;
		ml = R.M;
		p = R.PC;
		fp = R.FP;
		while(fp != nil){
			if(ml != nil && (m = ml->m) != nil && (r = mlook(m, 0, 1, 0)) != nil)
				break;
			f = (Frame*)fp;
			if(f->mr != nil)
				ml = f->mr;
			p = f->lr;
			fp = f->fp;
		}
		if(fp != nil){
			if(m->compiled && m->pctab != nil)
				p = pc2dispc(p, m);
			if((i = p-r->base) >= 0 && i < r->size)
				r->bucket[i]++;
		}
}
		unlock(&profile.l);
	}
	samplefn = 0;
	pexit("", 0);
}

/*
 *	coverage profiling
 */

static void
cpxec(Prog *p)
{
	int op, i;
	Module *m;
	Record *r;
	Prog *n;

	R = p->R;
	R.MP = R.M->MP;
	R.IC = p->quanta;

	if(p->kill != nil){
		char *m;
		m = p->kill;
		p->kill = nil;
		error(m);
	}

	if(R.M->compiled)
		comvec();
	else{
		m = R.M->m;
		r = profiler == Pcov ? mlook(m, 1, 1, 0) : nil;
		do{
			dec[R.PC->add]();
			op = R.PC->op;
			if(r != nil){
				i = R.PC-r->base;
				if(i >= 0 && i < r->size)
					r->bucket[i]++;
			}
			R.PC++;
			optab[op]();
			if(op == ISPAWN || op == IMSPAWN){
				n = delruntail(Pdebug);	// any state will do
				n->xec = cpxec;
				addrun(n);
			}
			if(m != R.M->m){
				m = R.M->m;
				r = profiler == Pcov ? mlook(m, 1, 1, 0) : nil;
			}
		}while(--R.IC != 0);
	}

	p->R = R;
}

/* memory profiling */

enum{
	Halloc,
	Hfree,
	Hgcfree,
};

static void
memprof(int c, Heap *h, ulong n)
{
	int i, j;
	ulong k, *b;
	Module *m;
	Record *r;
	Inst *p;

/* print("%d %x %uld\n", c, h, n); */
	USED(h);
	if(profiler != Pmem){
		heapmonitor = nil;
		return;
	}
	lock(&profile.l);
	m = nil;
	if(c != Hgcfree && (R.M == nil || (m = R.M->m) == nil)){
		unlock(&profile.l);
		return;
	}
	j = n;
	if(c == 0){		/* allocation */
		p = R.PC;
		if(m->compiled && m->pctab != nil)
			p = pc2dispc(p, m);
		if((r = mlook(m, 1, 2, 2)) == nil){
			unlock(&profile.l);
			return;
		}
		i = p-r->base;
		h->pad = (r->id<<24) | i;
		/* 31 is pool quanta - dependency on alloc.c */
		j = ((j+sizeof(Heap)+BHDRSIZE+31)&~31) - (sizeof(Heap)+BHDRSIZE);
	}
	else{
		/* c == 1 is ref count free */
		/* c == 2 is gc free */
		if((r = getrec(h->pad>>24)) == nil){
			unlock(&profile.l);
			return;
		}
		i = h->pad&0xffffff;
		j = hmsize(h)-sizeof(Heap);
		j = -j;
	}
	i = 2*(i+1);
	b = r->bucket;
	if(i >= 0 && i < r->size){
		if(0){
			if(c == 1){
				b[0] -= j;
				b[i] -= j;
			}
			else if(c == 2){
				b[1] -= j;
				b[i+1] -= j;
			}
		}
		else{
			b[0] += j;
			if((int)b[0] < 0)
				b[0] = 0;
			b[i] += j;
			if((int)b[i] < 0)
				b[i] = 0;
			if(j > 0){
				if((k = b[0]) > b[1])
					b[1] = k;
				if((k = b[i]) > b[i+1])
					b[i+1] = k;
			}
		}
	}
	unlock(&profile.l);
}

Dev profdevtab = {
	'P',
	"prof",

	devinit,
	profattach,
	devclone,
	profwalk,
	profstat,
	profopen,
	devcreate,
	profclose,
	profread,
	devbread,
	profwrite,
	devbwrite,
	devremove,
	profwstat
};
