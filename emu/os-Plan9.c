#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	KSTACK	= 32*1024,
	DELETE	= 0x7F,
};

Proc	**Xup;

extern	void	killrefresh(void);
extern	void	tramp(char*, void (*)(void*), void*);
extern	void	vstack(void*);

ulong	ustack;
extern	int	dflag;

extern Dev	rootdevtab, srvdevtab, fsdevtab, mntdevtab,
		condevtab, ssldevtab, drawdevtab, cmddevtab,
		progdevtab, pipedevtab, kfsdevtab, envdevtab,
		profdevtab, memdevtab;

Dev*	devtab[] =
{
	&rootdevtab,
	&condevtab,
	&srvdevtab,
	&fsdevtab,
	&mntdevtab,
	&ssldevtab,
	&drawdevtab,
	&cmddevtab,
	&progdevtab,
	&pipedevtab,
	&kfsdevtab, 
	&envdevtab,
	&profdevtab,
#ifdef USEDEVMEM
	&memdevtab,
#endif
	nil
};

ulong
erendezvous(void *a, ulong b)
{
	return rendezvous((ulong)a, b);
}

void
pexit(char *msg, int t)
{
	Osenv *e;

	USED(t);
	USED(msg);

	lock(&procs.l);
	if(up->prev) 
		up->prev->next = up->next;
	else
		procs.head = up->next;

	if(up->next)
		up->next->prev = up->prev;
	else
		procs.tail = up->prev;
	unlock(&procs.l);

/*	print("pexit: %s: %s\n", up->text, msg);	/**/
	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
	}
	free(up->prog);
	free(up);
	_exits("");
}

// static int kpn;

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	int pid;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;

// print("%d: kproc %s\n", ++kpn, name);
	p = newproc();
	p->kstack = mallocz(KSTACK, 0);
	if(p == nil || p->kstack == nil)
		panic("kproc: no memory");

	if(flags & KPDUPPG) {
		pg = up->env->pgrp;
		incref(&pg->r);
		p->env->pgrp = pg;
	}
	if(flags & KPDUPFDG) {
		fg = up->env->fgrp;
		incref(&fg->r);
		p->env->fgrp = fg;
	}
	if(flags & KPDUPENVG) {
		eg = up->env->egrp;
		incref(&eg->r);
		p->env->egrp = eg;
	}

	p->env->uid = up->env->uid;
	p->env->gid = up->env->gid;
	memmove(p->env->user, up->env->user, NAMELEN);

	strcpy(p->text, name);

	p->func = func;
	p->arg = arg;

	lock(&procs.l);
	if(procs.tail != nil) {
		p->prev = procs.tail;
		procs.tail->next = p;
	}
	else {
		procs.head = p;
		p->prev = nil;
	}
	procs.tail = p;
	unlock(&procs.l);

	/*
	 * switch back to the unshared stack to do the fork
	 * only the parent returns from kproc
	 */
	up->kid = p;
	up->kidsp = p->kstack;
	pid = setjmp(up->sharestack);
	if(!pid)
		longjmp(up->privstack, 1);
	return pid;
}

void
traphandler(void *reg, char *msg)
{
	int intwait = up->intwait;
	up->intwait = 0;
	/* Ignore pipe writes from devcmd */
	if(strstr(msg, "write on closed pipe") != nil)
		noted(NCONT);

	if (sflag) {
		if (intwait && strcmp(msg, Eintr) == 0)
			noted(NCONT);
		else
			noted(NDFLT);
	}
	if(intwait == 0)
		disfault(reg, msg);
	noted(NCONT);
}

int
readfile(char *path, char *buf, int n)
{
	int fd;

	fd = open(path, OREAD);
	if(fd >= 0) {
		n = read(fd, buf, n-1);
		if(n > 0)			/* both calls to readfile() have a ``default'' */
			buf[n] = '\0';
		close(fd);
	}
	return n;
}

static void
dobinds(void)
{
	char dir[MAXROOT+9];

	snprint(dir, sizeof(dir), "%s/net", rootdir);
	bind("/net", dir, MREPL);

	snprint(dir, sizeof(dir), "%s/net.alt", rootdir);
	bind("/net.alt", dir, MREPL);

	snprint(dir, sizeof(dir), "%s/dev", rootdir);
	bind("#t", dir, MAFTER);
	bind("#A", dir, MAFTER);
}

void
libinit(char *imod)
{
	char *sp;
	Proc *xup, *p;
	int fd, n, pid;

	/*
	 * setup personality
	 */
	readfile("/dev/user", eve, NAMELEN);
	readfile("/dev/sysname", ossysname, 3*NAMELEN);

	/*
	 * guess at a safe stack for vstack
	 */
	ustack = (ulong)&fd;

	rfork(RFNAMEG|RFREND);

	if(!dflag){
		fd = open("/dev/consctl", OWRITE);
		if(fd < 0)
			fprint(2, "libinit: open /dev/consctl: %r\n");
		n = write(fd, "rawon", 5);
		if(n != 5)
			fprint(2, "keyboard rawon (n=%d, %r)\n", n);
	}

	osmillisec();	/* set the epoch */
	dobinds();

//	if(sflag == 0)
		notify(traphandler);

	Xup = &xup;

	/*
	 * dummy up a up and stack so the first proc
	 * calls emuinit after setting up his private jmp_buf
	 */
	p = newproc();
	p->kstack = mallocz(KSTACK, 0);
	if(p == nil || p->kstack == nil)
		panic("libinit: no memory");
	sp = p->kstack;
	p->func = emuinit;
	p->arg = imod;

	/*
	 * set up a stack for forking kids on separate stacks.
	 * longjmp back here from kproc.
	 */
	while(setjmp(p->privstack)){
		p = up->kid;
		sp = up->kidsp;
		switch(pid = rfork(RFPROC|RFMEM)){
		case 0:
			/*
			 * send the kid around the loop to set up his private jmp_buf
			 */
			break;
		default:
			/*
			 * parent just returns to his shared stack in kproc
			 */
			longjmp(up->sharestack, pid);
			panic("longjmp failed");
		}
	}

	/*
	 * you get here only once per Proc
	 * go to the shared memory stack
	 */
	up = p;
	up->sigid = getpid();
	tramp(sp+KSTACK, up->func, up->arg);
	panic("tramp returned");
}

void
oshostintr(Proc *p)
{
	postnote(PNPROC, p->sigid, Eintr);
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	if (regs != nil)
		notejmp(regs, env, val);
	else
		longjmp(env, val);
}

void
osreboot(char*, char**)
{
}

void
cleanexit(int x)
{
	USED(x);
	killrefresh();
	postnote(PNGROUP, getpid(), "interrupt");
	exits("interrupt");
}

int
readkbd(void)
{
	int n;
	char buf[1];

	n = read(0, buf, sizeof(buf));
	if(n != 1) {
		print("keyboard close (n=%d, %r)\n", n);
		pexit("keyboard", 0);
	}
	switch(buf[0]) {
	case DELETE:
		cleanexit(0);
	case '\r':
		buf[0] = '\n';
	}
	return buf[0];
}

typedef struct Targ Targ;
struct Targ
{
	int	fd;
	int*	spin;
	char*	cmd;
};

void
exectramp(Targ *targ)
{
	int fd, i, nfd;
	char *argv[4], buf[KSTACK];

	fd = targ->fd;
	strncpy(buf, targ->cmd, sizeof(buf)-1);
	*targ->spin = 0;

	argv[0] = "/bin/rc";
	argv[1] = "-c";
	argv[2] = buf;
	argv[3] = nil;

	nfd = NFD;
	for(i = 0; i < nfd; i++)
		if(i != fd)
			close(i);

	dup(fd, 0);
	dup(fd, 1);
	dup(fd, 2);
	close(fd);
	exec(argv[0], argv);
	exits("");
}

int
oscmd(char *cmd, int *rfd, int *sfd)
{
	Targ targ;
	int spin, *spinptr, fd[2];

	if(pipe(fd) < 0)
		return -1;

	spinptr = &spin;
	spin = 1;

	targ.fd = fd[0];
	targ.cmd = cmd;
	targ.spin = spinptr;

	switch(rfork(RFMEM|RFPROC|RFFDG|RFENVG|RFREND)) {	/* RFNAMEG? RFNOTEG? */
	case -1:
		return -1;
	case 0:
		vstack(&targ);			/* Never returns */
	default:
		while(*spinptr)
			;
		break;
	}
	close(fd[0]);

	*rfd = fd[1];
	*sfd = fd[1];
	return 0;
}

static vlong
b2v(uchar *p)
{
	int i;
	vlong v;

	v = 0;
	for(i=0; i<sizeof(uvlong); i++)
		v = (v<<8)|p[i];
	return v;
}

long
osmillisec(void)
{
	int n;
	static vlong nsec0 = 0;
	static int nsecfd = -1;
	uchar buf[sizeof(uvlong)];

	if(nsec0 == 0){
		nsecfd = open("/dev/bintime",OREAD);  /* never closed */
		if(nsecfd<0){
			fprint(2,"can't open /dev/bintime: %r\n");
			return(0);
		}
		n = read(nsecfd,buf,sizeof(buf));
		if(n != sizeof(buf)){
			fprint(2,"read err on /dev/bintime: %r\n");
			return(0);
		}
		nsec0 = b2v(buf);
		return(0);
	}
	n = read(nsecfd, buf, sizeof(buf));
	if(n!=sizeof(buf)) {
		fprint(2,"read err on /dev/bintime: %r\n");
		return(0);
	}
	return ((b2v(buf)-nsec0)/1000000);
}

/*
 * Return the time since the epoch in microseconds
 * The epoch is defined at 1 Jan 1970
 */
vlong
osusectime(void)
{
	return nsec()/1000;
}

int
osmillisleep(ulong milsec)
{
	sleep(milsec);
	return 0;
}

void
osyield(void)
{
	sleep(0);
}

void
ospause(void)
{
	for(;;)
		sleep(1000000);
}

void
lopri(void)
{
	int fd;
	char buf[sizeof("/proc/99999999/ctl")];
	sprint(buf, "/proc/%d/ctl", getpid());
	if ((fd = open(buf, OWRITE)) != -1) {
		fprint(fd, "pri 8");
		close(fd);
	}
}

static Rb rb;
extern int rbnotfull(void*);

void
osspin(Rendez *prod)
{
	lopri();
	for(;;){
		if((rb.randomcount & 0xffff) == 0 && !rbnotfull(0)) {
			Sleep(prod, rbnotfull, 0);
 		}
		rb.randomcount++;
	}
}

Rb*
osraninit(void)
{
	return &rb;
}

void
oswakeupproducer(Rendez *rendez)
{
	Wakeup(rendez);
}

void
srvrtinit(void)
{
}
