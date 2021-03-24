#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include 	<pwd.h>
#include	<sys/ipc.h>
#include	<sys/sem.h>
#include	<sched.h>
#define _USE_BSD
#include	<sys/types.h>
#include	<sys/resource.h>
#include	<sys/wait.h>

/* according to X/OPEN we have to define union semun ourselves */
union semun {
       int val;                    /* value for SETVAL */
       struct semid_ds *buf;       /* buffer for IPC_STAT, IPC_SET */
       unsigned short int *array;  /* array for GETALL, SETALL */
       struct seminfo *__buf;      /* buffer for IPC_INFO */
};

#include	<asm/unistd.h>
#include	<sys/time.h>

#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	DELETE	= 0x7f,
	CTRLC	= 'C'-'@',
	NSEMA	= 20,
	NSTACKSPERALLOC = 16,
};

extern Dev	rootdevtab, srvdevtab, fsdevtab, mntdevtab,
		condevtab, ssldevtab, drawdevtab, cmddevtab,
		progdevtab, ipdevtab, pipedevtab,
		audiodevtab, eiadevtab, kfsdevtab, envdevtab,
		profdevtab;

Dev*    devtab[] =
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
	&ipdevtab,
	&pipedevtab,
/*	&audiodevtab,*/
	&eiadevtab,
	&kfsdevtab,
	&envdevtab,
	&profdevtab,
#ifdef USEDEVMEM
	&memdevtab,
#endif
	nil
};

static void *stackalloc(Proc *p, void **tos);
static void stackfreeandexit(void *stack);

static char	progname[] = "emu";

extern int dflag;

/* information about the allocated semaphore blocks */
typedef	struct sem_block sem_block;
struct sem_block
{
	int		semid;
	int		cnt;
	sem_block	*next;
};
static sem_block *sema = NULL;

int	gidnobody = -1;
int	uidnobody = -1;
struct 	termios tinit;

void
pexit(char *msg, int t)
{
	Osenv *e;
	void *kstack;

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

	print("pexit: %s: %s\n", up->text, msg);

	e = up->env;
	if(e != nil) {
		closefgrp(e->fgrp);
		closepgrp(e->pgrp);
		closeegrp(e->egrp);
	}
	kstack = up->kstack;
	free(up->prog);
	free(up);
	stackfreeandexit(kstack);
}

void
tramp(void *arg)
{
	Proc *p;
	p = arg;
	p->sigid = getpid();
	(*p->func)(p->arg);
	pexit("{Tramp}", 0);
}

int
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	int pid;
	Proc *p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	void *tos;

	p = newproc();
#ifdef DEBUG
	print("start %s:%.8lx\n", name, p);
#endif
	if(p == nil) {
		print("kproc(%s): no memory", name);
		return;
	}

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

	p->kstack = stackalloc(p, &tos);

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

	if (__clone(tramp, tos, CLONE_VM|CLONE_FS|CLONE_FILES|SIGCHLD, p) <= 0)
		panic("kproc: clone failed");

	return 0;
}

/* To get pc on trap
     Declare trap handlers as
	void trapILL(int signo, int code, struct sigcontext *scp)
     Then
	pc = scp->sp_pc
     Send disfault a string of the form "error: pc=0x....."
     See <signal.h>
*/

/*
void
diserr(char *s, int pc)
{
	char buf[ERRLEN];

	snprint(buf, sizeof(buf), "%s: pc=0x%lux", s, pc);
	disfault(nil, buf);
}
*/

void
trapILL(int signal_number)
{
	(void)signal_number;
	disfault(nil, "Illegal instruction");
}

void
trapBUS(int signal_number)
{
	(void)signal_number;
	disfault(nil, "Bus error");
}

void
trapSEGV(int signal_number)
{
	(void)signal_number;
	disfault(nil, "Segmentation violation");
}

#include <fpuctl.h>
void
trapFPE(int signal_number)
{
	(void)signal_number;

	print("FPU status=0x%.4lux", getfsr());
	disfault(nil, "Floating exception");
}

void
trapUSR1(int signal_number)
{
	(void)signal_number;

	if(up->type != Interp)		/* Used to unblock pending I/O */
		return;

	if(up->intwait == 0)		/* Not posted so its a sync error */
		disfault(nil, Eintr);	/* Should never happen */

	up->intwait = 0;		/* Clear it so the proc can continue */
}

/* called to wake up kproc blocked on a syscall */
void
oshostintr(Proc *p)
{
	kill(p->sigid, SIGUSR1);
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	siglongjmp(env, val);
}

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

	if(dflag == 0)
		termrestore();
	
	/* clean up the semaphores */
	{
		sem_block *s = sema;
		while (s) {
			union semun su;
			semctl(s->semid, 0, IPC_RMID, su);
			s = s->next;
		}
	}

	kill(0, SIGKILL);
	exit(0);
}

void
osreboot(char *file, char **argv)
{
	if(dflag == 0)
		termrestore();
	execvp(file, argv);
	panic("reboot failure");
}

void
libinit(char *imod)
{
	struct termios t;
	struct sigaction act;
	struct passwd *pw;
	Proc *p;
	void *tos;

	setsid();

	gethostname(ossysname, sizeof(ossysname));
	pw = getpwnam("nobody");
	if(pw != nil) {
		uidnobody = pw->pw_uid;
		gidnobody = pw->pw_gid;
	}

	if(dflag == 0)
		termset();

	memset(&act, 0 , sizeof(act));
	act.sa_handler=trapUSR1;
	sigaction(SIGUSR1, &act, nil);

	act.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &act, nil);

	/* For the correct functioning of devcmd in the
	 * face of exiting slaves
	 */
	signal(SIGPIPE, SIG_IGN);

	if(sflag == 0) {
		act.sa_handler=trapBUS;
		sigaction(SIGBUS, &act, nil);
		act.sa_handler=trapILL;
		sigaction(SIGILL, &act, nil);
		act.sa_handler=trapSEGV;
		sigaction(SIGSEGV, &act, nil);
		act.sa_handler = trapFPE;
		sigaction(SIGFPE, &act, nil);

		signal(SIGINT, cleanexit);
	}

	p = newproc();
	p->kstack = stackalloc(p, &tos);

	pw = getpwuid(getuid());
	if(pw != nil) {
		if (strlen(pw->pw_name) + 1 <= NAMELEN)
			strcpy(eve, pw->pw_name);
		else
			print("pw_name too long\n");
	} else
		print("cannot getpwuid\n");

	p->env->uid = getuid();
	p->env->gid = getgid();

	executeonnewstack(tos, emuinit, imod);
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
		buf[0] = 'H' - '@';
		break;
	case CTRLC:
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
	Tag*	hash;
	Tag*	free;
	int	semid;		/* id of semaphore block */
	int	sema;		/* offset into semaphore block */
};

static	Tag*	ht[NHASH];
static	Tag*	ft;
static	Lock	hlock;

ulong
erendezvous(void *tag, ulong value)
{
	int h;
	ulong rval;
	Tag *t, *f, **l;
	union semun sun;
	struct sembuf sop;

	sop.sem_flg = 0;

	h = (ulong)tag & (NHASH-1);

	lock(&hlock);
	l = &ht[h];
	for(t = *l; t; t = t->hash) {
		if(t->tag == tag) {
			rval = t->val;
			t->val = value;
			t->tag = 0;
			unlock(&hlock);

			sop.sem_num = t->sema;
			sop.sem_op = 1;
			semop(t->semid, &sop, 1);
			return rval;		
		}
	}

	/* create a tag if there is none in the free list */
	t = ft;
	if(t == nil) {

		/* create a new block of semaphores if needed */
		if (!sema || sema->cnt >= (NSEMA-1)) {
			sem_block *s;

			s = malloc(sizeof(sem_block));
			if(s == nil)
				panic("rendezvous: no memory");
			s->semid = semget(IPC_PRIVATE, NSEMA, IPC_CREAT|0700);
			if(s->semid < 0)
				panic("rendezvous: failed to allocate %d semaphores from semaphore pool: %r", NSEMA);
			s->cnt = 0;

			s->next = sema;
			sema = s;
		}

		/* create the tag */
		t = malloc(sizeof(Tag));
		if(t == nil)
			panic("rendezvous: no memory");
		t->semid = sema->semid;
		t->sema = sema->cnt++;		/* allocate next from block */

	} else
		ft = t->free;			/* get tag from free list */

	/* setup tag */
	t->tag = tag;
	t->val = value;
	t->hash = *l;
	*l = t;

	sun.val = 0;
	if(semctl(t->semid, t->sema, SETVAL, sun) < 0)
		panic("semctl: %r");
	unlock(&hlock);

	/* wait on semaphore ignoring all EINTR's */
	sop.sem_num = t->sema;
	sop.sem_op = -1;
	while (t->tag) {
		if (semop(t->semid, &sop, 1) < 0) {
			if(errno == EIDRM)
				exit(0);
			if(errno != EINTR)
				panic("semctl: %r"); 
		}
	}

	lock(&hlock);
	rval = t->val;
	for(f = *l; f; f = f->hash) {
		if(f == t) {
			*l = f->hash;
			break;
		}
		l = &f->hash;
	}

	/* add tag to free list */
	t->free = ft;
	ft = t;

	unlock(&hlock);

	return rval;
}

typedef struct Targ Targ;
struct Targ
{
	int     fd;
	int*    spin;
	char*   cmd;
};

int
exectramp(Targ *targ)
{
	int fd, i, nfd, error, uid, gid;
	char *argv[4], buf[MAXDEVCMD];

	fd = targ->fd;

	strncpy(buf, targ->cmd, sizeof(buf)-1);
	buf[sizeof(buf)-1] = '\0';

	argv[0] = "/bin/sh";
	argv[1] = "-c";
	argv[2] = buf;
	argv[3] = nil;

	print("devcmd: '%s'", buf);
	gid=up->env->gid;
	uid=up->env->gid;

	switch(fork()) {
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
		if(gid != -1)
			error=setgid(gid);
		else
			error=setgid(gidnobody);

		if((error)&&(geteuid()==0)){
			print("devcmd: root can't set gid: %d or gidnobody: %d\n",
				up->env->gid,gidnobody);
			exit(0);
		}
		
		error=0;
		if(uid != -1)
			error=setuid(uid);
		else
			error=setuid(uidnobody);

		if((error)&&(geteuid()==0)){
			print( "devcmd: root can't set uid: %d or uidnobody: %d\n",
				up->env->uid,uidnobody);
			exit(0);
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

//	signal(SIGCLD, SIG_DFL);

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
		return 0;

	if(sec0 == 0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return (t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000;
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
        struct  timespec time, remainder;

        time.tv_sec = milsec/1000;
        time.tv_nsec= (milsec%1000)*1000000;
        while (nanosleep(&time, &remainder) == EINTR)
		time = remainder;

	return 0;
}

static struct {
	Lock l;
	void *free;
} stacklist;

static void
_stackfree(void *stack)
{
	*((void **)stack) = stacklist.free;
	stacklist.free = stack;
}

static void
stackfreeandexit(void *stack)
{
	lock(&stacklist.l);
	_stackfree(stack);
	unlockandexit(&stacklist.l.val);
}

static void *
stackalloc(Proc *p, void **tos)
{
	void *rv;
	lock(&stacklist.l);
	if (stacklist.free == 0) {
		int x;
		/*
		 * obtain some more by using sbrk()
		 */
		void *more = sbrk(KSTACK * (NSTACKSPERALLOC + 1));
		if (more == 0)
			panic("stackalloc: no more stacks");
		/*
		 * align to KSTACK
		 */
		more = (void *)((((unsigned long)more) + (KSTACK - 1)) & ~(KSTACK - 1));
		/*
		 * free all the new stacks onto the freelist
		 */
		for (x = 0; x < NSTACKSPERALLOC; x++)
			_stackfree((char *)more + KSTACK * x);
	}
	rv = stacklist.free;
	stacklist.free = *(void **)rv;
	unlock(&stacklist.l);
	*tos = rv + KSTACK - sizeof(void *);
	*(Proc **)rv = p;
	return rv;
}

void
osyield(void)
{
	sched_yield();
}

void
ospause(void)
{
        for(;;)
                sleep(1000000);
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
