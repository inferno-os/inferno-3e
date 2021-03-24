#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"
#include	"kernel.h"
#include	"image.h"
#include	"version.h"

int		rebootargc = 0;
char**		rebootargv;
static	char	imod[128] = "/dis/emuinit.dis";
static	char	dmod[128] = "/dis/lib/srv.dis";
extern	char*	tkfont;
extern	int	mflag;
	int	dflag;
	Ref	pgrpid;
	Ref	mountid;
	ulong	kerndate;
	Procs	procs;
	char	eve[NAMELEN] = "inferno";
	int	Xsize	= 640;
	int	Ysize	= 480;
	int	sflag;
	int	qflag;
	int	xtblbit;
	int	globfs;
	int	greyscale;
char *cputype;

static void
savestartup(int argc, char *argv[])
{
	int i;

	rebootargc = argc;
	rebootargv = (char**) malloc((argc+1)*sizeof(char*));
	if(!rebootargv)
		panic("alloc failed saving startup");

	for(i = 0; i < argc; i++) {
		rebootargv[i] = strdup(argv[i]);
		if(!rebootargv[i])
			panic("alloc failed saving startup arg");
	}
	rebootargv[i] = nil;
}

static void
usage(void)
{
	fprint(2, "Usage: emu [options...] [file.dis]\n"
		"\t-gXxY\n"
		"\t-c[0-9]\n"
		"\t-d[012]\n"
		"\t-m[0-9]\n"
		"\t-s\n"
		"\t-p<poolname>=maxsize\n"
		"\t-f<fontpath>\n"
		"\t-r<rootpath>\n"
		"\t-7\n"
		"\t-G\n"
		"\t-2\n");

	exits("usage");
}

static void
geom(char *val)
{
	char *p;

	if (val == '\0') 
		usage();
	Xsize = strtoul(val, &p, 0);
	if(Xsize < 64) 
		Xsize = 640;
	if (p == '\0') {
		Ysize = 480;
		return;
	}
	Ysize = strtoul(p+1, 0, 0);
	if(Ysize < 48)
		Ysize = 480;
}

static void
poolopt(char *str)
{
	char *var;

	var = str;
	while(*str && *str != '=')
		str++;
	if(*str != '=')
		usage();
	*str++ = '\0';
	if(poolsetsize(var, atoi(str)) == 0)
		usage();
}

void
ksetenv(char *var, char *val)
{
	Chan *c;
	char buf[2*NAMELEN];

	sprint(buf, "#e/%s", var);
	c = namec(buf, Acreate, OWRITE, 0600);
	devtab[c->type]->write(c, val, strlen(val), 0);
	cclose(c);
}

static int
option(char *str)
{
	int c, i, done;

	while(*str == ' ')
		str++;
	if(*str == '\0')
		return 0;
	if(str[0] != '-') {
		/*
		 * ignore any non-option arguments; to be interpreted later
		 * by emuinit.dis
		 */
		return 0;
	}

	done = 0;
	for(i = 1; str[i] != '\0' && !done; i++) {
		switch(str[i]) {
		default:
			usage();
		case 'g':		/* Window geometry */
			done = 1;
			geom(&str[i+1]);
			break;
		case 'c':		/* Compile on the fly */
			done = 1;
			c = str[i+1];
			if(c < '0' || c > '9')
				usage();
			cflag = atoi(&str[i+1]);
			break;
		case 'd':		/* run as a daemon */
			done = 1;
			c = str[i+1];
			if(c < '0' || c > '2')
				usage();
			dflag = atoi(&str[i+1]);
			strncpy(imod, dmod, sizeof(imod));
			break;
		case 's':		/* No trap handling */
			sflag++;
			break;
		case 'm':		/* gc mark and sweep */
			done = 1;
			c = str[i+1];
			if(c < '0' || c > '9')
				usage();
			mflag = atoi(&str[i+1]);
			break;
		case 'p':		/* pool option */
			done = 1;
			poolopt(&str[i+1]);
			break;
		case 'f':		/* Set font path */
			done = 1;
			if(str[i+1] == '\0')
				usage();
			tkfont = &str[i+1];
			break;
		case 'r':		/* Set inferno root */
			done = 1;
			if(str[i+1] == '\0')
				usage();
			strncpy(rootdir, &str[i+1], sizeof(rootdir)-1);
			break;
		case '7':		/* use 7 bit colormap in X */
			xtblbit = 1;
			break;
		case 'G':		/* allow global access to file system */
			globfs = 1;
			break;
		case	'2':
			greyscale = 1;	/* on Windows */
			break;
		}
	}
	return 1;
}

void
main(int argc, char *argv[])
{
	int i, done;
	char *opt, *p;

	savestartup(argc, argv);
	opt = getenv("EMU");
	if(opt != nil && *opt != '\0') {
		done = 0;
		while(done == 0) {
			p = opt;
			while(*p && *p != ' ')
				p++;
			if(*p != '\0')
				*p = '\0';
			else
				done = 1;
			if(!option(opt))
				break;
			opt = p+1;
		}
	}
	for(i = 1; i < argc; i++)
		if(!option(argv[i]))
			break;

	kerndate = time(0);

	opt = "interp";
	if(cflag)
		opt = "compile";

	print("Inferno %s main (pid=%d) %s\n", VERSION, getpid(), opt);

	libinit(imod);
}

void
emuinit(void *imod)
{
	Osenv *e;

	e = up->env;
	e->pgrp = newpgrp();
	e->fgrp = newfgrp();
	e->egrp = newegrp();

	chandevinit();

	if(waserror())
		panic("setting root and dot");

	e->pgrp->slash = namec("#/", Atodir, 0, 0);
	cnameclose(e->pgrp->slash->name);
	e->pgrp->slash->name = newcname("/");
	e->pgrp->dot = cclone(e->pgrp->slash, nil);
	poperror();

	strcpy(up->text, "main");

	if(kopen("#c/cons", OREAD) != 0)
		fprint(2, "failed to make fd0 from #c/cons: %r\n");
	kopen("#c/cons", OWRITE);
	kopen("#c/cons", OWRITE);

	/* the setid cannot precede the bind of #U */
	kbind("#U", "/", MAFTER|MCREATE);
	setid(eve);
	kbind("#c", "/dev", MBEFORE);
	kbind("#p", "/prog", MREPL);
	kbind("#I", "/net", MAFTER);	/* will fail on Plan 9 */

	/* BUG: we actually only need to do these on Plan 9 */
	kbind("#U/dev", "/dev", MAFTER);
	kbind("#U/net", "/net", MAFTER);
	kbind("#U/net.alt", "/net.alt", MAFTER);

	if (cputype != nil)
		ksetenv("cputype", cputype);

	kproc("main", disinit, imod, KPDUPFDG|KPDUPPG|KPDUPENVG);

	for(;;)
		ospause(); 
}

void
modinit(void)
{
	sysmodinit();
	drawmodinit();
	prefabmodinit();
	tkmodinit();
	mathmodinit();
	srvrtinit();
	keyringmodinit();
	loadermodinit();
}

void
error(char *err)
{
	strncpy(up->env->error, err, ERRLEN);
	nexterror();
}

void
exhausted(char *resource)
{
	char buf[ERRLEN];

	snprint(buf, sizeof(buf), "no free %s", resource);
	error(buf);
}

void
nexterror(void)
{
	oslongjmp(nil, up->estack[--up->nerr], 1);
}

/* for dynamic modules - functions not macros */

void*
waserr(void)
{
	up->nerr++;
	return up->estack[up->nerr-1];
}

void
poperr(void)
{
	up->nerr--;
}

char*
enverror(void)
{
	return up->env->error;
}

Pgrp*
newpgrp(void)
{
	Pgrp *p;

	p = malloc(sizeof(Pgrp));
	if(p == nil)
		error(Enomem);
	p->r.ref = 1;
	p->pgrpid = incref(&pgrpid);
	p->pin = Nopin;
	p->progmode = 0644;
	return p;
}

Fgrp*
newfgrp(void)
{
	Fgrp *f;

	f = malloc(sizeof(Fgrp));
	if(f == nil)
		error(Enomem);
	f->r.ref = 1;

	return f;
}

Egrp*
newegrp(void)
{
	Egrp	*e;

	e = malloc(sizeof(Egrp));
	if (e == nil)
		error(Enomem);
	e->r.ref = 1;
	return e;
}

void
closepgrp(Pgrp *p)
{
	Mhead **h, **e, *f, *next;

	if(p == nil || decref(&p->r) != 0)
		return;

	wlock(&p->ns);
	p->pgrpid = -1;
	e = &p->mnthash[MNTHASH];
	for(h = p->mnthash; h < e; h++) {
		for(f = *h; f; f = next) {
			wlock(&f->lock);
			cclose(f->from);
			mountfree(f->mount);
			f->mount = nil;
			next = f->hash;
			wunlock(&f->lock);
			putmhead(f);
		}
	}
	wunlock(&p->ns);
	cclose(p->slash);
	cclose(p->dot);
	free(p);
}

void
closeegrp(Egrp *e)
{
	Evalue *el, *nl;

	if(e == nil || decref(&e->r) != 0)
		return;
	for (el = e->entries; el != nil; el = nl) {
		free(el->var);
		if (el->val)
			free(el->val);
		nl = el->next;
		free(el);
	}
	free(e);
}

Fgrp*
dupfgrp(Fgrp *f)
{
	int i;
	Chan *c;
	Fgrp *new;

	new = newfgrp();

	lock(&f->r.l);
	new->maxfd = f->maxfd;
	for(i = 0; i <= f->maxfd; i++) {
		if(c = f->fd[i]){
			incref(&c->r);
			new->fd[i] = c;
		}
	}
	unlock(&f->r.l);

	return new;
}

void
closefgrp(Fgrp *f)
{
	int i;
	Chan *c;

	if(f != nil && decref(&f->r) == 0) {
		for(i = 0; i <= f->maxfd; i++)
			if(c = f->fd[i])
				cclose(c);

		free(f);
	}
}

void
pgrpinsert(Mount **order, Mount *m)
{
	Mount *f;

	m->order = 0;
	if(*order == 0) {
		*order = m;
		return;
	}
	for(f = *order; f; f = f->order) {
		if(m->mountid < f->mountid) {
			m->order = f;
			*order = m;
			return;
		}
		order = &f->order;
	}
	*order = m;
}

/*
 * pgrpcpy MUST preserve the mountid allocation order of the parent group
 */
void
pgrpcpy(Pgrp *to, Pgrp *from)
{
	int i;
	Mount *n, *m, **link, *order;
	Mhead *f, **tom, **l, *mh;

	wlock(&from->ns);
	order = 0;
	tom = to->mnthash;
	for(i = 0; i < MNTHASH; i++) {
		l = tom++;
		for(f = from->mnthash[i]; f; f = f->hash) {
			rlock(&f->lock);
			mh = malloc(sizeof(Mhead));
			if(mh == nil) {
				runlock(&f->lock);
				wunlock(&from->ns);
				error(Enomem);
			}
			mh->from = f->from;
			mh->r.ref = 1;
			incref(&mh->from->r);
			*l = mh;
			l = &mh->hash;
			link = &mh->mount;
			for(m = f->mount; m; m = m->next) {
				n = malloc(sizeof(Mount));
				if(n == nil) {
					runlock(&f->lock);
					wunlock(&from->ns);
					error(Enomem);
				}
				n->to = m->to;
				incref(&n->to->r);
				n->head = mh;
				n->flag = m->flag;
				if(m->spec[0] != 0)
					strncpy(n->spec, m->spec, NAMELEN);
				m->copy = n;
				pgrpinsert(&order, m);
				*link = n;
				link = &n->next;	
			}
			runlock(&f->lock);
		}
	}
	/*
	 * Allocate mount ids in the same sequence as the parent group
	 */
	lock(&mountid.l);
	for(m = order; m; m = m->order)
		m->copy->mountid = mountid.ref++;
	unlock(&mountid.l);

	to->pin = from->pin;

	to->slash = cclone(from->slash, nil);
	to->dot = cclone(from->dot, nil);
	to->nodevs = from->nodevs;
	wunlock(&from->ns);
}

void
egrpcpy(Egrp *to, Egrp *from)
{
	Evalue *e, *ne, **last;

	last = &to->entries;
	qlock(&from->l);
	for (e = from->entries; e != nil; e = e->next) {
		ne = malloc(sizeof(Evalue));
		ne->var = malloc(strlen(e->var)+1);
		strcpy(ne->var, e->var);
		if (e->val) {
			ne->val = malloc(e->len);
			memmove(ne->val, e->val, e->len);
			ne->len = e->len;
		}
		ne->qid.path = ++to->path;
		*last = ne;
		last = &ne->next;
	}
	qunlock(&from->l);
}

Mount*
newmount(Mhead *mh, Chan *to, int flag, char *spec)
{
	Mount *m;

	m = malloc(sizeof(Mount));
	if(m == nil)
		error(Enomem);
	m->to = to;
	m->head = mh;
	incref(&to->r);
	m->mountid = incref(&mountid);
	m->flag = flag;
	if(spec != 0)
		strcpy(m->spec, spec);

	return m;
}

void
mountfree(Mount *m)
{
	Mount *f;

	while(m) {
		f = m->next;
		cclose(m->to);
		m->mountid = 0;
		free(m);
		m = f;
	}
}

Proc*
newproc(void)
{
	Proc *p;

	p = malloc(sizeof(Proc));
	if(p == nil)
		return nil;

	p->type = Unknown;
	p->env = &p->defenv;
	addprog(p);

	return p;
}

void
panic(char *fmt, ...)
{
	va_list arg;
	char buf[512];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "panic: %s\n", buf);
	if(sflag)
		abort();

	cleanexit(0);
}
