#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#undef _POSIX_C_SOURCE
#include	<unistd.h>
#include	<sys/types.h>		/* for pthread.h */
#include	<pthread.h>
#include	<semaphore.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include 	<pwd.h>

/*
#define _BSD_TIME
*/
/* for gettimeofday(), which isn't POSIX,
 * but is fairly common
 */
#include	<sys/time.h>

enum
{
	FILENAME = 256,
	BUNCHES = 0xFFFF,	/* this should be more than enuf */


	DELETE  = 0x7F
};

extern Dev      rootdevtab, srvdevtab, fsdevtab, mntdevtab,
		condevtab, auditdevtab, ssldevtab, drawdevtab,
		cmddevtab, progdevtab, ipdevtab, pipedevtab,
//		audiodevtab,
		kfsdevtab, eiadevtab, envdevtab;

Dev*    devtab[] =
{
	&rootdevtab,
	&condevtab,
	// &auditdevtab,
	&srvdevtab,
	&fsdevtab,
	&mntdevtab,
	&ssldevtab,
	&drawdevtab,
	&cmddevtab,
	&progdevtab,
	&ipdevtab,
	&pipedevtab,
	// &audiodevtab,
	&kfsdevtab,
	&eiadevtab,
	&envdevtab,
	nil
};

static pthread_key_t	prdakey;
static pthread_t active_threads[BUNCHES];
static siginfo_t siginfo;
extern int dflag;

void
pexit(char *msg, int t)
{
	Osenv *e;

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

	/*print("pexit: %s: %s\n", up->text, msg);*/
	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
	}
	free(up->prog);
	free(up);
	pthread_exit(0);
}

static void *
tramp(void *v)
{
	struct Proc *Up;

	if(pthread_setspecific(prdakey,v)) {
		print("set specific data failed in tramp\n");
		pthread_exit(0);
	}
	Up = v;
//	Up->sigid = (ulong)pthread_self();
	Up->sigid = (int)pthread_mach_thread_np(pthread_self());
	Up->func(Up->arg);
	pexit("", 0);
}

static void
threadsleep(ulong secs)
{
	sleep(secs);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	int id;
	pthread_t thread;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;

	p = newproc();

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

#ifdef notdef
	pthread_attr_t attr;
	errno=0;
	pthread_attr_setschedpolicy(&attr,SCHED_OTHER);
	if(errno)
		panic("pthread_attr_setschedpolicy failed");
	if(pthread_create(&thread, &attr, tramp, p))
#endif

	if(pthread_create(&thread, 0, &tramp, p))
		panic("pthread_create failed\n");

	id = (int)pthread_mach_thread_np(thread);
	if (id >= BUNCHES)
		panic("pthread id too big");
	active_threads[id] = thread;

//	pthread_yield();
	return id;
}

// invalidate instruction cache and write back data cache from a to a+n-1, at least.
void
segflush(void *a, ulong n)
{
	ulong *p;

	// paranoia, flush the world
	__asm__("isync\n\t"
		"eieio\n\t"
		: /* no output */
		:
	);
	// cache blocks are often eight words (32 bytes) long, sometimes 16 bytes.
	// need to determine it dynamically?
	for (p = (ulong *)((ulong)a & ~3UL); (char *)p < (char *)a + n; p++)
		__asm__("dcbst	0,%0\n\t"	/* not dcbf, which writes back, then invalidates */
			"icbi	0,%0\n\t"
			: /* no output */
			: "ar" (p)
		);
	__asm__("isync\n\t"
		"eieio\n\t"
		: /* no output */
		:
	);
}

/* to get pc on trap use siginfo.si_pc field and define all trap handlers
	as printILL - have to set sa_sigaction, sa_flags not sa_handler
*/

void
trapUSR1(void)
{
	if(up->type != Interp)		/* Used to unblock pending I/O */
		return;
	if(up->intwait == 0)		/* Not posted so its a sync error */
		disfault(nil, Eintr);	/* Should never happen */

	up->intwait = 0;		/* Clear it so the proc can continue */
}

void
trapILL(void)
{
	disfault(nil, "Illegal instruction");
}

void
printILL(int sig, siginfo_t *siginfo, void *v)
{
	panic(
	"Illegal instruction with code=%d at address=%x, opcode=%x.\n"
	,siginfo->si_code, siginfo->si_addr,*(char*)siginfo->si_addr);
}

void
trapBUS(void)
{
	disfault(nil, "Bus error");
}

void
trapSEGV(void)
{
	disfault(nil, "Segmentation violation");
}

void
trapFPE(void)
{
	disfault(nil, "Floating point exception");
}

void
oshostintr(Proc *p)
{
//	pthread_kill((pthread_t)p->sigid, SIGUSR1);
	if (p->sigid < 0 || p->sigid >= BUNCHES)
		panic("oshostintr: p->sigid out of range");
	pthread_cancel(active_threads[p->sigid]);
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	siglongjmp(env, val);
}

static struct termios tinit;

static void
termset(void)
{
	struct termios t;

	tcgetattr(0, &t);
	tinit = t;
	t.c_lflag &= ~(ICANON|ECHO|ISIG);
	t.c_cc[VMIN] = 1;
	t.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, &t);
}

static void
termrestore(void)
{
	tcsetattr(0, TCSANOW, &tinit);
}

void
cleanexit(int x)
{
	USED(x);

	if(up->intwait) {
		up->intwait = 0;
		return;
	}

	if(!dflag)
		termrestore();
//	kill(0, SIGKILL);
	exit(0);
}

int gidnobody= -1, uidnobody= -1;

void
getnobody(void)
{
	struct passwd *pwd;

	if (pwd=getpwnam("nobody")) {
		uidnobody = pwd->pw_uid;
		gidnobody = pwd->pw_gid;
	}
}

void
osreboot(char *file, char **argv)
{
	termrestore();
	execvp(file, argv);
	panic("reboot failure");
}

static	pthread_mutex_t rendezvouslock;
static	pthread_mutexattr_t	*pthread_mutexattr_default = NULL;

void
libinit(char *imod)
{
	struct Proc *Up;
	struct sigaction act;
	struct passwd *pw;

	setsid();

	if(!dflag)
		termset();

	if(pthread_mutex_init(&rendezvouslock, pthread_mutexattr_default))
		panic("pthread_mutex_init");
	gethostname(ossysname, sizeof(ossysname));
	getnobody();

	memset(&act, 0 , sizeof(act));
	act.sa_handler=trapUSR1;
	sigaction(SIGUSR1, &act, nil);
	/* For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGPIPE, SIG_IGN);
	signal(SIGTERM, cleanexit);
	if(sflag == 0)
	{
		act.sa_handler=trapBUS;
		sigaction(SIGBUS, &act, nil);
		act.sa_sigaction=trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_handler=trapSEGV;
		sigaction(SIGSEGV, &act, nil);
		act.sa_handler=trapFPE;
		sigaction(SIGFPE, &act, nil);
		signal(SIGINT, cleanexit);
	}
	else{
		act.sa_sigaction=printILL;
		act.sa_flags=SA_SIGINFO;
		sigaction(SIGILL, &act, nil);
	}

	if(pthread_key_create(&prdakey,NULL))
		print("key_create failed\n");

	Up = newproc();
	if(pthread_setspecific(prdakey,Up))
		panic("set specific thread data failed\n");

	pw = getpwuid(getuid());
	if(pw != nil)
		if (strlen(pw->pw_name) + 1 <= NAMELEN)
			strcpy(eve, pw->pw_name);
		else
			print("pw_name too long\n");
	else
		print("cannot getpwuid\n");

	up->env->uid = getuid();
	up->env->gid = getgid();
	emuinit(imod);
}

int
readkbd(void)
{
	int n;
	char buf[1];

	n = read(0, buf, sizeof(buf));
	if(n != 1) {
		print("keyboard close (n=%d, %s)\n", n, strerror(errno));
		pexit("keyboard thread", 0);
	}

	switch(buf[0]) {
	case '\r':
		buf[0] = '\n';
		break;
	case DELETE:
		cleanexit(0);
		break;
	}
	return buf[0];
}

enum
{
	NHLOG	= 7,
	NHASH	= (1<<NHLOG)
};

typedef struct Tag Tag;
struct Tag
{
	void*	tag;
	ulong	val;
	int	pid;
	Tag*	hash;
	Tag*	free;
//	sem_t	sema;
	pthread_cond_t cv;
};

static	Tag*	ht[NHASH];
static	Tag*	ft;
// static	Lock	hlock;

ulong
erendezvous(void *tag, ulong value)
{
	int h;
	ulong rval;
	Tag *t, *f, **l;

	h = (ulong)tag & (NHASH-1);

//	lock(&hlock);
	if(pthread_mutex_lock(&rendezvouslock))
		panic("pthread_mutex_lock");
	l = &ht[h];
	for(t = *l; t; t = t->hash) {
		if(t->tag == tag) {
			rval = t->val;
			t->val = value;
			t->tag = 0;
//			unlock(&hlock);
//			sem_post(&t->sema);
			if(pthread_mutex_unlock(&rendezvouslock))
				panic("pthread_mutex_unlock");
			if(pthread_cond_signal(&t->cv))
				panic("pthread_cond_signal");
			return rval;
		}
	}

	t = ft;
	if(t == 0) {
		t = malloc(sizeof(Tag));
		if(t == 0)
			panic("rendezvous: no memory");
		if(pthread_cond_init(&t->cv, NULL)) {
			print("pthread_cond_init (errno: %s)\n",
				strerror(errno));
			panic("pthread_cond_init");
		}
	}
	else {
		ft = t->free;
	}

	t->tag = tag;
	t->val = value;
	t->hash = *l;
	*l = t;

//	sem_open(&t->sema,0);
//	unlock(&hlock);
//	while(sem_wait(&t->sema))
//		; /* sig usr1 may catch us */
//	lock(&hlock);
	while(t->tag)
		pthread_cond_wait(&t->cv, &rendezvouslock);

	rval = t->val;
	for(f = *l; f; f = f->hash) {
		if(f == t) {
			*l = f->hash;
			break;
		}
		l = &f->hash;
	}
	t->free = ft;
	ft = t;
//	unlock(&hlock);
	if(pthread_mutex_unlock(&rendezvouslock))
		panic("pthread_mutex_unlock");

	return rval;
}

static char*
month[] =
{
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

int
timeconv(va_list *arg, Fconv *f)
{
	struct tm *tm;
	time_t t;
	struct tm rtm;
	char buf[64];

	t = va_arg(*arg, long);
	tm =localtime_r(&t, &rtm);

	sprint(buf, "%s %2d %-.2d:%-.2d",
		month[tm->tm_mon], tm->tm_mday, tm->tm_hour, tm->tm_min);

	strconv(buf, f);
	return sizeof(long);
}

static char*
modes[] =
{
	"---",
	"--x",
	"-w-",
	"-wx",
	"r--",
	"r-x",
	"rw-",
	"rwx",
};

static void
rwx(long m, char *s)
{
	strncpy(s, modes[m], 3);
}

int
dirmodeconv(va_list *arg, Fconv *f)
{
	static char buf[16];
	ulong m;

	m = va_arg(*arg, ulong);

	if(m & CHDIR)
		buf[0]='d';
	else if(m & CHAPPEND)
		buf[0]='a';
	else
		buf[0]='-';
	if(m & CHEXCL)
		buf[1]='l';
	else
		buf[1]='-';
	rwx((m>>6)&7, buf+2);
	rwx((m>>3)&7, buf+5);
	rwx((m>>0)&7, buf+8);
	buf[11] = 0;

	strconv(buf, f);
	return(sizeof(ulong));
}

typedef struct Targ Targ;
struct Targ
{
	int     fd;
	int*    spin;
	char*   cmd;
};

/* because of differences between the Irix and Solaris multi-threading
 * environments this routine must differ from its Irix counter part.
 * In irix sprocsp() starts this routine as a seperate process, so the
 * parent must spin waiting for the command to be copy out of targ->cmd.
 * In Solaris the exec cannot be done from within a thread because
 * they all share the process, so it has to fork1() first.
 * vfork() is not MT safe and so cannot be used here.
 */
int
exectramp(Targ *targ)
{
	int fd, i, nfd;
	char *argv[4], buf[2+MAXROOT+2+MAXDEVCMD];
	extern char rootdir[MAXROOT];

	fd = targ->fd;

	sprint(buf, "r=%s; ", rootdir);
	i = strlen(rootdir);
	strncpy(buf+2+i+2, targ->cmd, sizeof(buf)-2-i-2-1);
	buf[sizeof(buf)-1] = '\0';

	argv[0] = "/bin/sh";
	argv[1] = "-c";
	argv[2] = buf;
	argv[3] = nil;

	print("devcmd: '%s'", buf);

	switch(fork()) {
	int error;
	case -1:
		print("%s\n",strerror(errno));
		return -1;
	default:
		print(" pid %d\n", getpid());
		return 0;
	case 0:
		nfd = getdtablesize();
		for(i = 0; i < nfd; i++)
			if(i != fd)
				close(i);

		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		close(fd);
		error=0;
		if(up->env->gid != -1)
			error = setgid(up->env->gid);
		else
			error = setgid(gidnobody);

		if((error)&&(geteuid()==0)){
			print(
			"devcmd: root can't set gid: %d or gidnobody: %d\n",
			up->env->gid,gidnobody);
			_exit(0);
		}

		error=0;
		if(up->env->uid != -1)
			error=setuid(up->env->uid);
		else
			error=setuid(uidnobody);

		if((error)&&(geteuid()==0)){
			print(
			"devcmd: root can't set uid: %d or uidnobody: %d\n",
                        up->env->uid,uidnobody);
			_exit(0);
                }

		execv(argv[0], argv);
		print("%s\n",strerror(errno));
		/* don't flush buffered i/o twice */
		_exit(0);
	}
}

int
oscmd(char *cmd, int *rfd, int *sfd)
{
	Dir dir;
	Targ targ;
	int r, fd[2];

	if(bipipe(fd) < 0)
		return -1;

#ifndef SIGCLD
#define SIGCLD SIGCHLD
#endif
//	signal(SIGCLD, SIG_IGN);

	targ.fd = fd[0];
	targ.cmd = cmd;

	r = 0;
	if (exectramp(&targ) < 0) {
		r = -1;
	}

	close(fd[0]);
	*rfd = fd[1];
	*sfd = fd[1];
	return r;
}

/*
 * Return an abitrary millisecond clock time
 */
long
osmillisec(void)
{
	static long sec0 = 0, usec0;
	struct timeval t;

	if(gettimeofday(&t,(struct timezone*)0)<0)
		return(0);
	if(sec0==0){
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return((t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000);
}

/*
 * Return the time since the epoch in microseconds
 * The epoch is defined at 1 Jan 1970
 */
vlong
osusectime(void)
{
	struct timeval t;

	gettimeofday(&t, nil);
	return (vlong)t.tv_sec * 1000000 + t.tv_usec;
}

int
osmillisleep(ulong milsec)
{
        struct  timespec time;

        time.tv_sec = milsec/1000;
        time.tv_nsec= (milsec%1000)*1000000;
        nanosleep(&time,nil);

	return 0;
}

Proc *
getup(void)
{
	return pthread_getspecific(prdakey);
}

ulong
getcallerpc(void *arg)
{
//	return (ulong)arg;
	return 0;
}

void
osyield(void)
{
//	pthread_yield();
	sched_yield();
}

void
ospause(void)
{
	for(;;)
//		sleep(1000000);
		threadsleep(3600);
}

static Rb rb;
extern int rbnotfull(void*);

void
osspin(Rendez *prod)
{
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

/*
 * first argument (l) is in r3 at entry.
 * r3 contains return value upon return.
 */
int
canlock(Lock *l)
{
	int     v;

	/*
	 * this __asm__ works with gcc 2.95.2 (mac os x 10.1).
	 * this assembly language destroys r0 (0), some other register (v),
	 * r4 (&l->key) and r5 (temp).
	 */
	__asm__("\n	sync\n"
	"	li	r0,0\n"
	"	mr	r4,%1		/* &l->key */\n"
	"	lis	r5,0xdead	/* assemble constant 0xdeaddead */\n"
	"	ori	r5,r5,0xdead	/* \" */\n"
	"tas1:\n"
	"	dcbf	r4,r0	/* cache flush; \"fix for 603x bug\" */\n"
	"	lwarx	%0,r4,r0	/* v = l->key with reservation */\n"
	"	cmp	cr0,0,%0,r0	/* v == 0 */\n"
	"	bne	tas0\n"
	"	stwcx.	r5,r4,r0   /* if (l->key same) l->key = 0xdeaddead */\n"
	"	bne	tas1\n"
	"tas0:\n"
	"	sync\n"
	"	isync\n"
	: "=r" (v)
	: "r"  (&l->key)
	: "cc", "memory", "r0", "r4", "r5"
	);
	switch(v) {
	case 0:		return 1;
	case 0xdeaddead: return 0;
	default:	print("canlock: corrupted 0x%lux\n", v);
	}
	return 0;
}

// TODO: gotta save and register 32 fp regs too, see lib9.h
void
FPrestore(void *fcrp)
{
	double fr;

	__asm__("sync\n\t"
		"lfd	%1,%0\n\t"
		"mtfs	%1\n\t"
		"isync\n\t"
		: /* no output */
		: "m"	(*fcrp),
		  "fr"	(fr)
	);
}

void
FPsave(void *fcrp)
{
	uvlong fcr;
	double fr;

	__asm__("mffs	%1\n\t"
		"stfd	%1,%0\n\t"
		: "=m"  (fcr)
		: "fr"	(fr)
	);
	*(uvlong *)fcrp = fcr;
}
