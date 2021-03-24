/*
 * Unix file system interface
 */
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	<sys/stat.h>
#include	<sys/types.h>
#include	<sys/fcntl.h>
#include	<utime.h>
#include	"styx.h"
#include	"stdio.h"
#include	"pwd.h"
#include 	"grp.h"

#define NIL(s)	((s) == nil || *(s) == '\0')

#define	FS(c)	(&(c)->u.uif)

enum
{
	IDSHIFT	= 8,
	NID	= 1 << IDSHIFT,
	IDMASK	= NID - 1,
	MAXPATH	= 1024,
	MAXCOMP	= 128
};

typedef struct Pass Pass;
struct Pass
{
	int	id;
	int	gid;
	char*	name;
	Pass*	next;
};

char	rootdir[MAXROOT] = "/usr/inferno/";

static	Pass*	uid[NID];
static	Pass*	gid[NID];
static	Pass*	member[NID];
static	RWlock	idl;

static	Qid	fsqid(struct stat *);
static	void	fspath(Cname*, char*, char*);
static	Cname*	fswalkpath(Cname*, char*, int);
static	char*	fslastelem(Cname*);
static	void	id2name(Pass**, int, char*);
static	int ingroup(int id, int gid);
static	void	fsperm(Chan*, int);
static	ulong	fsdirread(Chan*, uchar*, int, ulong);
static	int	fsomode(int);
static	Pass*	name2pass(Pass**, char*);
static	void	getpwdf(void);
static	void	getgrpf(void);

/* Unix libc */

extern	struct passwd *getpwent(void);
extern	struct group *getgrent(void);

static void
fsfree(Chan *c)
{
	cnameclose(FS(c)->name);
}

void
fsinit(void)
{
}

Chan*
fsattach(char *spec)
{
	Chan *c;
	struct stat stbuf;
	static int devno;
	char err[ERRLEN];
	static Lock l;

	getpwdf();
	getgrpf();

	if(stat(rootdir, &stbuf) < 0) {
		oserrstr(err, sizeof err);
		error(err);
	}
	if (!NIL(spec) && (!globfs || strcmp(spec, "*") != 0))
		error(Ebadspec);

	c = devattach('U', spec);
	c->qid = fsqid(&stbuf);
	FS(c)->gid = stbuf.st_gid;
	FS(c)->uid = stbuf.st_uid;
	FS(c)->mode = stbuf.st_mode;
	lock(&l);
	c->dev = devno++;
	unlock(&l);
	if (!NIL(spec))
		FS(c)->spec = "/";
	FS(c)->name = newcname(NIL(spec)? rootdir: "/");

	return c;
}

Chan*
fsclone(Chan *c, Chan *nc)
{
	nc = devclone(c, nc);
	FS(nc)->spec = FS(c)->spec;
	FS(nc)->name = FS(c)->name;
	if(FS(nc)->name)
		incref(&FS(nc)->name->r);
	return nc;
}

int
fswalk(Chan *c, char *name)
{
	struct stat stbuf;
	char path[MAXPATH];

	fspath(FS(c)->name, name, path);
/*
	print("** ufs walk '%s' -> %s\n", path, name);
*/
	if(stat(path, &stbuf) < 0)
		return 0;

	FS(c)->gid = stbuf.st_gid;
	FS(c)->uid = stbuf.st_uid;
	FS(c)->mode = stbuf.st_mode;

	c->qid = fsqid(&stbuf);

	FS(c)->name = fswalkpath(FS(c)->name, name, 0);

	return 1;
}

void
fsstat(Chan *c, char *buf)
{
	Dir d;
	struct stat stbuf;
	char err[ERRLEN], *p;

	if(stat(FS(c)->name->s, &stbuf) < 0) {
		oserrstr(err, sizeof err);
		error(err);
	}

	p = fslastelem(FS(c)->name);
	if(*p == 0)
		p = ".";
	strncpy(d.name, p, NAMELEN);
	rlock(&idl);
	id2name(uid, stbuf.st_uid, d.uid);
	id2name(gid, stbuf.st_gid, d.gid);
	runlock(&idl);
	d.qid = c->qid;
	d.mode = (c->qid.path&CHDIR)|(stbuf.st_mode&0777);
	d.atime = stbuf.st_atime;
	d.mtime = stbuf.st_mtime;
	if(S_ISREG(stbuf.st_mode))
		d.length = stbuf.st_size;
	else
		d.length = 0;
	if(d.mode&CHDIR)
		d.length = 0;
	d.type = 'U';
	d.dev = c->dev;
	convD2M(&d, buf);
}

Chan*
fsopen(Chan *c, int mode)
{
	int m, trunc, isdir;
	char err[ERRLEN];

	m = mode & (OTRUNC|3);
	switch(m) {
	case 0:
		fsperm(c, 4);
		break;
	case 1:
	case 1|16:
		fsperm(c, 2);
		break;
	case 2:	
	case 0|16:
	case 2|16:
		fsperm(c, 4);
		fsperm(c, 2);
		break;
	case 3:
		fsperm(c, 1);
		break;
	default:
		error(Ebadarg);
	}

	isdir = c->qid.path & CHDIR;

	if(isdir && mode != OREAD)
		error(Eperm);

	m = fsomode(m & 3);
	c->mode = openmode(mode);

	if(isdir) {
		FS(c)->dir = opendir(FS(c)->name->s);
		if(FS(c)->dir == 0) {
			oserrstr(err, sizeof err);
			error(err);
		}
	}	
	else {
		if(mode & OTRUNC)
			m |= O_TRUNC;
		FS(c)->fd = open(FS(c)->name->s, m, 0666);
		if(FS(c)->fd < 0) {
			oserrstr(err, sizeof err);
			error(err);
		}
	}

	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
	return c;
}

void
fscreate(Chan *c, char *name, int mode, ulong perm)
{
	int fd, m;
	struct stat stbuf;
	char path[MAXPATH], err[ERRLEN];

	fsperm(c, 2);

	m = fsomode(mode&3);

	fspath(FS(c)->name, name, path);

	if(perm & CHDIR) {
		if(m)
			error(Eperm);

		if(mkdir(path, 0777) < 0) {
    Error:
			oserrstr(err, sizeof err);
			error(err);
		}

		fd = open(path, 0);
		if(fd >= 0) {
			fchmod(fd, FS(c)->mode & perm & 0777);
			fchown(fd, up->env->uid, FS(c)->gid);
		}
		close(fd);
		FS(c)->dir = opendir(path);
		if(FS(c)->dir == 0)
			goto Error;
	}
	else {
		fd = creat(path, 0666);
		if(fd >= 0) {
			if(m != 1) {
				close(fd);
				fd = open(path, m);
			}
			fchmod(fd, (perm & 0111) | (FS(c)->mode & perm & 0666));
			fchown(fd, up->env->uid, FS(c)->gid);
		}
		if(fd < 0)
			goto Error;
		FS(c)->fd = fd;
	}
	if(stat(path, &stbuf) < 0) {
		close(fd);
		goto Error;
	}
	c->qid = fsqid(&stbuf);
	FS(c)->gid = stbuf.st_gid;
	FS(c)->uid = stbuf.st_uid;
	FS(c)->mode = stbuf.st_mode;
	c->mode = openmode(mode);
	c->offset = 0;
	FS(c)->offset = 0;
	c->flag |= COPEN;
	FS(c)->name = fswalkpath(FS(c)->name, name, 0);
}

void
fsclose(Chan *c)
{
	if((c->flag & COPEN) != 0){
		if(c->qid.path & CHDIR)
			closedir(FS(c)->dir);
		else
			close(FS(c)->fd);
	}
	if(c->flag & CRCLOSE) {
		if(!waserror()) {
			fsremove(c);
			poperror();
		}
		return;
	}
	fsfree(c);
}

long
fsread(Chan *c, void *va, long n, ulong offset)
{
	int fd, r;
	char err[ERRLEN];

	qlock(&FS(c)->oq);
	if(waserror()) {
		qunlock(&FS(c)->oq);
		nexterror();
	}

	if(c->qid.path & CHDIR)
		n = fsdirread(c, va, n, offset);
	else {
		fd = FS(c)->fd;
		if(FS(c)->offset != offset) {
			r = lseek(fd, offset, 0);
			if(r < 0) {
				oserrstr(err, sizeof err);
				error(err);
			}
			FS(c)->offset = offset;
		}

		n = read(fd, va, n);
		if(n < 0) {
			oserrstr(err, sizeof err);
			error(err);
		}
		FS(c)->offset += n;
	}

	qunlock(&FS(c)->oq);
	poperror();

	return n;
}

long
fswrite(Chan *c, void *va, long n, ulong offset)
{
	int fd, r;
	char err[ERRLEN];

	qlock(&FS(c)->oq);
	if(waserror()) {
		qunlock(&FS(c)->oq);
		nexterror();
	}
	fd = FS(c)->fd;
	if(FS(c)->offset != offset) {
		r = lseek(fd, offset, 0);
		if(r < 0) {
			oserrstr(err, sizeof err);
			error(err);
		}
		FS(c)->offset = offset;
	}

	n = write(fd, va, n);
	if(n < 0) {
		oserrstr(err, sizeof err);
		error(err);
	}

	FS(c)->offset += n;
	qunlock(&FS(c)->oq);
	poperror();

	return n;
}

void
fswchk(Cname *c)
{
	struct stat stbuf;
	char err[ERRLEN];

	if(stat(c->s, &stbuf) < 0) {
		oserrstr(err, sizeof err);
		error(err);
	}

	if(stbuf.st_uid == up->env->uid)
		stbuf.st_mode >>= 6;
	else
	if(stbuf.st_gid == up->env->gid || ingroup(up->env->uid, stbuf.st_gid))
		stbuf.st_mode >>= 3;

	if(stbuf.st_mode & S_IWOTH)
		return;

	error(Eperm);
}

void
fsremove(Chan *c)
{
	int n;
	char err[ERRMAX];
	volatile struct { Cname *dir; } dir;

	dir.dir = fswalkpath(FS(c)->name, "..", 1);
	if(waserror()){
		if(dir.dir != nil)
			cnameclose(dir.dir);
		fsfree(c);
		nexterror();
	}
	fswchk(dir.dir);		
	cnameclose(dir.dir);
	dir.dir = nil;
	if(c->qid.path & CHDIR)
		n = rmdir(FS(c)->name->s);
	else
		n = remove(FS(c)->name->s);
	if(n < 0) {
		oserrstr(err, sizeof err);
		error(err);
	}
	poperror();
	fsfree(c);
}

void
fswstat(Chan *c, char *buf)
{
	Dir d;
	Pass *p;
	volatile struct { Cname *ph; } ph;
	struct stat stbuf;
	struct utimbuf utbuf;
	char dir[MAXPATH], err[ERRLEN];

	convM2D(buf, &d);
	
	if(stat(FS(c)->name->s, &stbuf) < 0) {
    Error:
		oserrstr(err, sizeof err);
		error(err);
	}

	if(strcmp(d.name, fslastelem(FS(c)->name)) != 0) {
		ph.ph = fswalkpath(FS(c)->name, "..", 1);
		if(waserror()){
			cnameclose(ph.ph);
			nexterror();
		}
		fswchk(ph.ph);
		ph.ph = fswalkpath(ph.ph, d.name, 0);
		if(rename(FS(c)->name->s, ph.ph->s) < 0)
			goto Error;

		cnameclose(FS(c)->name);
		poperror();
		FS(c)->name = ph.ph;
	}

	if((d.mode&0777) != (stbuf.st_mode&0777)) {
		if(up->env->uid != stbuf.st_uid)
			error(Eowner);
		if(chmod(FS(c)->name->s, d.mode&0777) < 0)
			goto Error;
		FS(c)->mode &= ~0777;
		FS(c)->mode |= d.mode&0777;
	}
	if((d.mtime != stbuf.st_mtime) ||
	   (d.atime != stbuf.st_atime) ) {
		if(up->env->uid != stbuf.st_uid)
			error(Eowner);
		utbuf.modtime = d.mtime;
		utbuf.actime  = d.atime;
		if(utime(FS(c)->name->s, &utbuf) < 0)
			goto Error;
	}

	rlock(&idl);
	p = name2pass(gid, d.gid);
	if(p == 0) {
		runlock(&idl);
		error(Eunknown);
	}

	if(p->id != stbuf.st_gid) {
		if(up->env->uid != stbuf.st_uid) {
			runlock(&idl);
			error(Eowner);
		}
		if(chown(FS(c)->name->s, stbuf.st_uid, p->id) < 0) {
			runlock(&idl);
			goto Error;
		}

		FS(c)->gid = p->id;
	}
	runlock(&idl);
}

#define	QDEVBITS 4	/* 16 devices should be plenty */
#define MAXDEV (1<<QDEVBITS)
#define	QDEVSHIFT	(32-QDEVBITS)
#define	QINOMASK	((1<<QDEVSHIFT)-1)
#define QPATH(d,i)      (((d)<<QDEVSHIFT)|((i)&QINOMASK))

static Qid
fsqid(struct stat *st)
{
	Qid q;
	ulong dev;
	int idev;
	static int nqdev = 0;
	static ulong qdev[MAXDEV];
	static Lock l;

	q.path = 0;
	if(S_ISDIR(st->st_mode))
		q.path = CHDIR;

	dev = st->st_dev;
	lock(&l);
	for(idev = 0; idev < nqdev; idev++)
		if(qdev[idev] == dev)
			break;
	if(idev == nqdev) {
		if(nqdev == MAXDEV) {
			unlock(&l);
			error("too many devices");
		}
		qdev[nqdev++] = dev;
	}
	unlock(&l);

	if(st->st_ino & ~QINOMASK)
		error("inode number too large");

	q.path |= QPATH(idev, st->st_ino);
//fprint(2, "dev=%ux n=%d ino=%lux path=%8.8lux\n", dev, idev, st->st_ino, q.path);
	q.vers = st->st_mtime;

	return q;
}

static void
fspath(Cname *c, char *name, char *path)
{
	int n, l;

	if(c->len+strlen(name) >= MAXPATH)
		panic("fspath: name too long");
	memmove(path, c->s, c->len);
	n = c->len;
	if(path[n-1] != '/')
		path[n++] = '/';
	strcpy(path+n, name);
	if(isdotdot(name))
		cleanname(path);
/*print("->%s\n", path);*/
}

static Cname *
fswalkpath(Cname *c, char *name, int dup)
{
	if(dup)
		c = newcname(c->s);
	c = addelem(c, name);
	if(isdotdot(name))
		cleancname(c);
	return c;
}

static char *
fslastelem(Cname *c)
{
	char *p;

	p = c->s + c->len;
	while(p > c->s && p[-1] != '/')
		p--;
	return p;
}

/*
 * Assuming pass is one of the static arrays protected by idl, caller must
 * hold idl in writer mode.
 */
static void
freepass(Pass **pass)
{
	int i;
	Pass *p, *np;

	for(i=0; i<NID; i++){
		for(p = pass[i]; p; p = np){
			np = p->next;
			free(p);
		}
		pass[i] = 0; 
	}
}

static void
getpwdf(void)
{
	unsigned i;
	Pass *p;
	static int mtime;		/* serialized by idl */
	struct stat stbuf;
	struct passwd *pw;

	if(stat("/etc/passwd", &stbuf) < 0)
		panic("can't read /etc/passwd");

	/*
	 * Unlocked peek is okay, since the check is a heuristic (as is
	 * the function).
	 */
	if(stbuf.st_mtime <= mtime)
		return;

	wlock(&idl);
	if(stbuf.st_mtime <= mtime) {
		/*
		 * If we lost a race on updating the database, we can
		 * avoid some work.
		 */
		wunlock(&idl);
		return;
	}
	mtime = stbuf.st_mtime;
	freepass(uid);
	setpwent();
	while(pw = getpwent()){
		i = pw->pw_uid;
		i = (i&IDMASK) ^ ((i>>IDSHIFT)&IDMASK);
		p = realloc(0, sizeof(Pass));
		if(p == 0)
			panic("getpwdf");

		p->next = uid[i];
		uid[i] = p;
		p->id = pw->pw_uid;
		p->gid = pw->pw_gid;
		p->name = strdup(pw->pw_name);
		if(p->name == 0)
			panic("no memory");
	}

	wunlock(&idl);
	endpwent();
}

static void
getgrpf(void)
{
	static int mtime;		/* serialized by idl */
	struct stat stbuf;
	struct group *pw;
	unsigned i;
	int j;
	Pass *p, *q;

	if(stat("/etc/group", &stbuf) < 0)
		panic("can't read /etc/group");

	/*
	 * Unlocked peek is okay, since the check is a heuristic (as is
	 * the function).
	 */
	if(stbuf.st_mtime <= mtime)
		return;

	wlock(&idl);
	if(stbuf.st_mtime <= mtime) {
		/*
		 * If we lost a race on updating the database, we can
		 * avoid some work.
		 */
		wunlock(&idl);
		return;
	}
	mtime = stbuf.st_mtime;
	freepass(gid);
	freepass(member);
	/*
	 *	Pass one -- group name to gid mapping.
	 */
	setgrent();
	while(pw = getgrent()){
		i = pw->gr_gid;
		i = (i&IDMASK) ^ ((i>>IDSHIFT)&IDMASK);
		p = realloc(0, sizeof(Pass));
		if(p == 0)
			panic("getpwdf");
		p->next = gid[i];
		gid[i] = p;
		p->id = pw->gr_gid;
		p->gid = 0;
		p->name = strdup(pw->gr_name);
		if(p->name == 0)
			panic("no memory");
	}
	/*
	 *	Pass two -- group memberships.
	 */
	setgrent();
	while(pw = getgrent()){
		for (j = 0;; j++) {
			if (pw->gr_mem[j] == nil)
				break;
			q = name2pass(gid, pw->gr_mem[j]);
			if (q == nil)
				continue;
			i = q->id + pw->gr_gid;
			i = (i&IDMASK) ^ ((i>>IDSHIFT)&IDMASK);
			p = realloc(0, sizeof(Pass));
			if(p == 0)
				panic("getpwdf");
			p->next = member[i];
			member[i] = p;
			p->id = q->id;
			p->gid = pw->gr_gid;
		}
	}

	wunlock(&idl);
	endgrent();
}

/* Caller must hold idl.  Does not raise an error. */
static Pass*
name2pass(Pass **pw, char *name)
{
	int i;
	static Pass *p;
	static Pass **pwdb;

	if(p && (pwdb == pw) && (strcmp(name, p->name) == 0))
		return p;

	for(i=0; i<NID; i++)
		for(p = pw[i]; p; p = p->next)
			if(strcmp(name, p->name) == 0) {
				pwdb = pw;
				return p;
			}

	return 0;
}

/* Caller must hold idl.  Does not raise an error. */
static void
id2name(Pass **pw, int id, char *name)
{
	int i;
	Pass *p;
	char *s;

	s = nil;
	/* use last on list == first in file */
	i = (id&IDMASK) ^ ((id>>IDSHIFT)&IDMASK);
	for(p = pw[i]; p; p = p->next)
		if(p->id == id)
			s = p->name;
	if(s != nil)
		strncpy(name, s, NAMELEN);
	else
		snprint(name, NAMELEN, "%d", id);
}

/* Caller must hold idl.  Does not raise an error. */
static int
ingroup(int id, int gid)
{
	int i;
	Pass *p;

	i = id+gid;
	i = (id&IDMASK) ^ ((id>>IDSHIFT)&IDMASK);
	for(p = member[i]; p; p = p->next)
		if(p->id == id && p->gid == gid)
			return 1;
	return 0;
}

static void
fsperm(Chan *c, int mask)
{
	int m;

	m = FS(c)->mode;
/*
	print("fsperm: %o %o uuid %d ugid %d cuid %d cgid %d\n",
		m, mask, up->env->uid, up->env->gid, FS(c)->uid, FS(c)->gid);
*/
	if(FS(c)->uid == up->env->uid)
		m >>= 6;
	else
	if(FS(c)->gid == up->env->gid || ingroup(up->env->uid, FS(c)->gid))
		m >>= 3;

	m &= mask;
	if(m == 0)
		error(Eperm);
}

static int
isdots(char *name)
{
	if(name[0] != '.')
		return 0;
	if(name[1] == '\0')
		return 1;
	if(name[1] != '.')
		return 0;
	if(name[2] == '\0')
		return 1;
	return 0;
}

static ulong
fsdirread(Chan *c, uchar *va, int count, ulong offset)
{
	int i;
	Dir d;
	long n, o;
	DIRTYPE *de;
	struct stat stbuf;
	char path[MAXPATH];
	int sf;

	count = (count/DIRLEN)*DIRLEN;

	i = 0;

	if(FS(c)->offset != offset) {
		seekdir(FS(c)->dir, 0);
		for(n=0; n<offset; ) {
			de = readdir(FS(c)->dir);
			if(de == 0) {
				/* EOF, so stash offset and return 0 */
				FS(c)->offset = n;
				return 0;
			}
			if(de->d_ino==0 || de->d_name[0]==0 || isdots(de->d_name))
				continue;
			n += DIRLEN;
		}
		FS(c)->offset = offset;
	}

	/*
	 * Take idl on behalf of id2name.  Stalling attach, which is a
	 * rare operation, until the readdir completes is probably
	 * preferable to adding lock round-trips.
	 */
	rlock(&idl);
	while(i < count) {
		de = readdir(FS(c)->dir);
		if(de == 0)
			break;

		if(de->d_ino==0 || de->d_name[0]==0 || isdots(de->d_name))
			continue;

		strncpy(d.name, de->d_name, NAMELEN-1);
		d.name[NAMELEN-1] = 0;
		fspath(FS(c)->name, de->d_name, path);
		memset(&stbuf, 0, sizeof stbuf);

		sf = 1;
		if(stat(path, &stbuf) < 0) {
			fprintf(stderr, "dir: bad path %s\n", path);
			sf = 0;
			/* but continue... probably a bad symlink */
		}
		id2name(uid, stbuf.st_uid, d.uid);
		id2name(gid, stbuf.st_gid, d.gid);
		d.qid = fsqid(&stbuf);
		d.mode = (d.qid.path&CHDIR)|(stbuf.st_mode&0777);
		d.atime = stbuf.st_atime;
		d.mtime = stbuf.st_mtime;
		if(sf && S_ISREG(stbuf.st_mode))
			d.length = stbuf.st_size;
		else
			d.length = 0;
		if(d.mode&CHDIR)
			d.length = 0;
		d.type = 'U';
		d.dev = c->dev;
		convD2M(&d, va+i);
		i += DIRLEN;
		FS(c)->offset += DIRLEN;
	}
	runlock(&idl);
	return i;
}

static int
fsomode(int m)
{
	switch(m) {
	case 0:			/* OREAD */
	case 3:			/* OEXEC */
		return 0;
	case 1:			/* OWRITE */
		return 1;
	case 2:			/* ORDWR */
		return 2;
	}
	error(Ebadarg);
	return 0;
}

void
setid(char *name)
{
	Pass *p;

	strncpy(up->env->user, name, NAMELEN-1);
	up->env->user[NAMELEN-1] = 0;

	rlock(&idl);
	p = name2pass(uid, name);
	if(p == nil){
		runlock(&idl);
		up->env->uid = -1;
		up->env->gid = -1;
		return;
	}

	up->env->uid = p->id;
	up->env->gid = p->gid;
	runlock(&idl);
}

Dev fsdevtab = {
	'U',
	"fs",

	fsinit,
	fsattach,
	fsclone,
	fswalk,
	fsstat,
	fsopen,
	fscreate,
	fsclose,
	fsread,
	devbread,
	fswrite,
	devbwrite,
	fsremove,
	fswstat
};
