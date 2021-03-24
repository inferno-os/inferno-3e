#define		FPinit() fpinit() /* remove this if math lib is linked */
void		FPrestore(void*);
void		FPsave(void*);
void		addclock0link(void (*)(void));
void		addprog(Proc*);
void		addrootfile(char*, uchar*, ulong);
Block*		adjustblock(Block*, int);
Block*		allocb(int);
int	anyhigher(void);
int	anyready(void);
#define	assert(x)	if((x)){}else _assert("x")
void	_assert(char*);
int		blocklen(Block*);
int	breakhit(Ureg *ur, Proc*);
int		canlock(Lock*);
int		canqlock(QLock*);
int		capwritehash(uchar*, int);
int		capwriteuse(uchar*, int);
void		cclose(Chan*);
int		canrlock(RWlock*);
void		chandevinit(void);
void		chandevreset(int);
void		chanfree(Chan*);
void		checkalarms(void);
Chan*		cclone(Chan*, Chan*);
void		closeegrp(Egrp*);
void		closefgrp(Fgrp*);
void		closepgrp(Pgrp*);
int		cmount(Chan*, Chan*, int, char*);
void		cnameclose(Cname*);
Block*		concatblock(Block*);
void		confinit(void);
Block*		copyblock(Block*, int);
Chan*		createdir(Chan*);
void		cunmount(Chan*, Chan*);
void		cursorenable(void);
void		cursordisable(void);
void		cursoron(void);
void		cursoroff(void);
void		debugkey(Rune, char *, void(*)(), int);
int		decref(Ref*);
Chan*		devattach(int, char*);
void		devdetach(void);
Block*		devbread(Chan*, long, ulong);
long		devbwrite(Chan*, Block*, ulong);
Chan*		devclone(Chan*, Chan*);
void		devcreate(Chan*, char*, int, ulong);
void		devdir(Chan*, Qid, char*, long, char*, long, Dir*);
long		devdirread(Chan*, char*, long, Dirtab*, int, Devgen*);
Devgen		devgen;
void		devinit(void);
int		devno(int, int);
Chan*		devopen(Chan*, int, Dirtab*, int, Devgen*);
void		devremove(Chan*);
void		devreset(void);
void		devstat(Chan*, char*, Dirtab*, int, Devgen*);
int		devwalk(Chan*, char*, Dirtab*, int, Devgen*);
void		devwstat(Chan*, char*);
void		disinit(void*);
void		disfault(void*, char*);
Chan*		domount(Chan*);
void		drawactive(int);
void		dumpstack(void);
Fgrp*		dupfgrp(Fgrp*);
void		egrpcpy(Egrp*, Egrp*);
int		eqchan(Chan*, Chan*, int);
int		eqqid(Qid, Qid);
void		error(char*);
void		errstr(char*);
void		exhausted(char*);
void		exit(int);
void		reboot(void);
void		halt(void);
int		export(int, char*, int);
void		fdclose(Fgrp*, int);
Chan*		fdtochan(Fgrp*, int, int, int, int);
void		free(void*);
void		freeb(Block*);
void		freeblist(Block*);
void		getcolor(ulong, ulong*, ulong*, ulong*);
ulong	getmalloctag(void*);
ulong	getrealloctag(void*);
void		gotolabel(Label*);
void		hnputl(void*, ulong);
void		hnputs(void*, ushort);
Block*		iallocb(int);
void		ilock(Lock*);
int		incref(Ref*);
void		isdir(Chan*);
int		iseve(void);
int		islo(void);
void		iunlock(Lock*);
void		ixsummary(void);
void		kbdclock(void);
int		kbdcr2nl(Queue*, int);
int		kbdputc(Queue*, int);
void		kbdrepeat(int);
void		kproc(char*, void(*)(void*), void*, int);
int		kfgrpclose(Fgrp*, int);
void		kprocchild(Proc*, void (*)(void*), void*);
int		kprint(char*, ...);
void		ksetenv(char*, char*);
long		latin1(uchar*, int);
void		lock(Lock*);
void		machinit(void);
extern void	machbreakinit(void);
extern Instr	machinstr(ulong addr);
extern void	machbreakset(ulong addr);
extern void	machbreakclear(ulong addr, Instr i);
extern ulong	machnextaddr(Ureg *ur);
void*		malloc(ulong);
void*		mallocz(ulong, int);
void		microdelay(int);
long		mntread9p(Chan*, void*, long, ulong);
long		mntwrite9p(Chan*, void*, long, ulong);
void		modinit(void);
void		mountfree(Mount*);
Pointer	mouseconsume(void);
void		mouseproduce(Pointer);
void		mousetrack(int, int, int);
ulong		msize(void*);
Chan*		namec(char*, int, int, ulong);
void		nameok(char*);
Chan*		newchan(void);
Egrp*		newegrp(void);
Fgrp*		newfgrp(Fgrp*);
Mount*		newmount(Mhead*, Chan*, int, char*);
Pgrp*		newpgrp(void);
Proc*		newproc(void);
char*		nextelem(char*, char*);
void		nexterror(void);
ulong		nhgetl(void*);
ushort		nhgets(void*);
Cname*	newcname(char*);
int		notify(Ureg*);
void	notkilled(void);
int		nrand(int);
int		okaddr(ulong, ulong, int);
int		openmode(ulong);
Block*		packblock(Block*);
Block*		padblock(Block*, int);
void		panic(char*, ...);
Cmdbuf*		parsecmd(char*, int);
void		pexit(char*, int);
void		pgrpcpy(Pgrp*, Pgrp*);
#define		poperror()		up->nerrlab--
int		poolread(char*, int, ulong);
void		poolsize(Pool *, int, int);
int		postnote(Proc *, int, char *, int);
int		pprint(char*, ...);
void		printinit(void);
void		procctl(Proc*);
void		procdump(void);
void		procinit(void);
Proc*		proctab(int);
int		pullblock(Block**, int);
Block*		pullupblock(Block*, int);
void		putmhead(Mhead*);
void		putstrn(char*, int);
Block*		qbread(Queue*, int);
long		qbwrite(Queue*, Block*);
int		qcanread(Queue*);
void		qclose(Queue*);
int		qconsume(Queue*, void*, int);
Block*		qcopy(Queue*, int, ulong);
int	qdiscard(Queue*, int);
void		qflush(Queue*);
void		qfree(Queue*);
int		qfull(Queue*);
Block*		qget(Queue*);
void		qhangup(Queue*, char*);
int		qisclosed(Queue*);
int		qiwrite(Queue*, void*, int);
int		qlen(Queue*);
void		qlock(QLock*);
void		qnoblock(Queue*, int);
Queue*		qopen(int, int, void (*)(void*), void*);
int		qpass(Queue*, Block*);
int		qpassnolim(Queue*, Block*);
int		qproduce(Queue*, void*, int);
long		qread(Queue*, void*, int);
void		qreopen(Queue*);
void		qsetlimit(Queue*, int);
void		qunlock(QLock*);
int		qwindow(Queue*);
int		qwrite(Queue*, void*, int);
int		readnum(ulong, char*, ulong, ulong, int);
int		readnum_vlong(ulong, char*, ulong, vlong, int);
int		readstr(ulong, char*, ulong, char*);
void		ready(Proc*);
void		renameuser(char*, char*);
void		resrcwait(char*);
int		return0(void*);
void		rlock(RWlock*);
void		runlock(RWlock*);
Proc*		runproc(void);
void		sched(void);
void		schedinit(void);
long		seconds(void);
int		setcolor(ulong, ulong, ulong, ulong);
int		setlabel(Label*);
void		setmalloctag(void*, ulong);
int		setpri(int);
void		setrealloctag(void*, ulong);
char*		skipslash(char*);
void		sleep(Rendez*, int(*)(void*), void*);
void*		smalloc(ulong);
int		splhi(void);
int		spllo(void);
void		splx(int);
void	_splx(int);
void		swiproc(Proc*, int);
int		tas(void*);
int		tready(void*);
Block*		trimblock(Block*, int, int);
void 		tsleep(Rendez*, int (*)(void*), void*, int);
long		unionread(Chan*, void*, long);
void		unlock(Lock*);
void		userinit(void);
ulong		userpc(void);
void		wakeup(Rendez*);
int		walk(Chan**, char*, int);
void		werrstr(char*, ...);
void		wlock(RWlock*);
void		wunlock(RWlock*);
void*		xalloc(ulong);
void		xfree(void*);
void		xhole(ulong, ulong);
void		xinit(void);
int		xmerge(void*, void*);
void*		xspanalloc(ulong, int, ulong);
void		xsummary(void);
 
void		validaddr(void*, ulong, int);
void*	vmemchr(void*, int, int);

#define	scsialloc(n)	mallocz((n)+512, 0)
int		scsierrstr(int);
#define	scsifree(p)	free(p)

#pragma	varargck	argpos	print	1
#pragma	varargck	argpos	snprint	3
#pragma	varargck	argpos	seprint	3
#pragma	varargck	argpos	sprint	2
#pragma	varargck	argpos	fprint	2
#pragma	varargck	argpos	panic	1
#pragma	varargck	argpos	kwerrstr	1
#pragma	varargck	argpos	kprint	1

#pragma	varargck	type	"lld"	vlong
#pragma	varargck	type	"llx"	vlong
#pragma	varargck	type	"lld"	uvlong
#pragma	varargck	type	"llx"	uvlong
#pragma	varargck	type	"lx"	void*
#pragma	varargck	type	"ld"	long
#pragma	varargck	type	"lx"	long
#pragma	varargck	type	"ld"	ulong
#pragma	varargck	type	"lx"	ulong
#pragma	varargck	type	"d"	int
#pragma	varargck	type	"x"	int
#pragma	varargck	type	"c"	int
#pragma	varargck	type	"C"	int
#pragma	varargck	type	"d"	uint
#pragma	varargck	type	"x"	uint
#pragma	varargck	type	"c"	uint
#pragma	varargck	type	"C"	uint
#pragma	varargck	type	"f"	double
#pragma	varargck	type	"e"	double
#pragma	varargck	type	"g"	double
#pragma	varargck	type	"s"	char*
#pragma	varargck	type	"S"	Rune*
#pragma	varargck	type	"r"	void
#pragma	varargck	type	"%"	void
#pragma	varargck	type	"I"	uchar*
#pragma	varargck	type	"V"	uchar*
#pragma	varargck	type	"E"	uchar*
#pragma	varargck	type	"M"	uchar*
#pragma	varargck	type	"N"	void*
#pragma	varargck	type	"N"	long
#pragma	varargck	type	"N"	ulong
#pragma	varargck	type	"p"	void*
#define	parsefields(a,b,c,d) getfields((a),(b),(c),1,(d))
