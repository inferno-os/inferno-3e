#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

struct Mntrpc
{
	Chan*	c;		/* Channel for whom we are working */
	Mntrpc*	list;		/* Free/pending list */
	Fcall	request;	/* Outgoing file system protocol message */
	Fcall	reply;		/* Incoming reply */
	Mnt*	m;		/* Mount device during rpc */
	Rendez	r;		/* Place to hang out */
	char*	rpc;		/* I/O Data buffer */
	char	done;		/* Rpc completed */
	char	flushed;	/* Flush was sent */
	ushort	flushtag;	/* Tag flush sent on */
	char	flush[MAXMSG];	/* Somewhere to build flush */
};

struct Mntalloc
{
	Lock;
	Mnt*	list;		/* Mount devices in use */
	Mnt*	mntfree;	/* Free list */
	Mntrpc*	rpcfree;
	ulong	id;
	int	rpctag;
}mntalloc;

#define MAXRPC		(16*1024+MAXMSG)
#define limit(n, max)	(n > max ? max : n)

void	mattach(Mnt*, Chan*, char*);
void	mntauth(Mnt*, Mntrpc*, char*, ushort);
Mnt*	mntchk(Chan*);
void	mntdirfix(uchar*, Chan*);
int	mntflush(Mnt*, Mntrpc*);
void	mntfree(Mntrpc*);
void	mntgate(Mnt*);
void	mntpntfree(Mnt*);
void	mntqrm(Mnt*, Mntrpc*);
Mntrpc*	mntralloc(Chan*);
long	mntrdwr(int, Chan*, void*, long, ulong);
long	mnt9prdwr(int, Chan*, void*, long, ulong);
void	mntrpcread(Mnt*, Mntrpc*);
void	mountio(Mnt*, Mntrpc*);
void	mountmux(Mnt*, Mntrpc*);
void	mountrpc(Mnt*, Mntrpc*);
int	rpcattn(void*);
void	mclose(Mnt*);
Chan*	mntchan(void);

int defmaxmsg = MAXFDATA;
int	mntdebug;

enum
{
	Tagspace	= 1,
	Tagfls		= 0x8000,
	Tagend		= 0xfffe,
};

static void
mntreset(void)
{
	mntalloc.id = 1;
	mntalloc.rpctag = Tagspace;
}

static void
mntinit(void)
{
	fmtinstall('F', fcallconv);
}

static Chan*
mntattach(char *muxattach)
{
	Mnt *m;
	Chan *c, *mc;
	struct bogus{
		Chan	*chan;
		char	*spec;
		int	flags;
	}bogus;

	bogus = *((struct bogus *)muxattach);
	c = bogus.chan;

	lock(&mntalloc);
	for(m = mntalloc.list; m; m = m->list) {
		if(m->c == c && m->id) {
			lock(m);
			if(m->id && m->ref > 0 && m->c == c) {
				m->ref++;
				unlock(m);
				unlock(&mntalloc);
				c = mntchan();
				if(waserror()) {
					chanfree(c);
					nexterror();
				}
				mattach(m, c, bogus.spec);
				poperror();
				return c;
			}
			unlock(m);	
		}
	}

	m = mntalloc.mntfree;
	if(m != 0)
		mntalloc.mntfree = m->list;	
	else {
		m = malloc(sizeof(Mnt)+MAXRPC);
		if(m == 0) {
			unlock(&mntalloc);
			exhausted("mount devices");
		}
		m->flushbase = Tagfls;
		m->flushtag = Tagfls;
	}
	m->list = mntalloc.list;
	mntalloc.list = m;
	m->id = mntalloc.id++;
	unlock(&mntalloc);

	lock(m);
	m->ref = 1;
	m->npart = 0;
	m->queue = 0;
	m->rip = 0;
	m->c = c;
	m->c->flag |= CMSG;
	if(strcmp(bogus.spec, "16k") == 0) {
		m->blocksize = 16*1024;
		bogus.spec = "";
	}
	else
		m->blocksize = defmaxmsg;
	m->flags = bogus.flags & ~MCACHE;

	incref(m->c);

	unlock(m);

	c = mntchan();
	if(waserror()) {
		mclose(m);
		/* Close must not be called since it will
		 * call mnt recursively
		 */
		chanfree(c);
		nexterror();
	}

	mattach(m, c, bogus.spec);
	poperror();

	/*
	 * Detect a recursive mount for a mount point served by exportfs.
	 * If CHDIR is clear in the returned qid, the foreign server is
	 * requesting the mount point be folded into the connection
	 * to the exportfs. In this case the remote mount driver does
	 * the multiplexing.
	 */
	mc = m->c;
	if(mc->type == devno('M', 0) && (c->qid.path&CHDIR) == 0) {
		mclose(m);
		c->qid.path |= CHDIR;
		c->mntptr = mc->mntptr;
		c->mchan = c->mntptr->c;
		c->mqid = c->qid;
		incref(c->mntptr);
	}

	return c;
}

Chan*
mntchan(void)
{
	Chan *c;

	c = devattach('M', 0);
	lock(&mntalloc);
	c->dev = mntalloc.id++;
	unlock(&mntalloc);

	return c;
}

void
mattach(Mnt *m, Chan *c, char *spec)
{
	Mntrpc *r;
	Osenv *o;

	r = mntralloc(0);
	c->mntptr = m;

	if(waserror()) {
		mntfree(r);
		nexterror();
	}

	r->request.type = Tattach;
	r->request.fid = c->fid;
	o = up->env;
	memmove(r->request.uname, o->user, NAMELEN);
	strncpy(r->request.aname, spec, NAMELEN);

	mountrpc(m, r);

	c->qid = r->reply.qid;

	c->mchan = m->c;
	c->mqid = c->qid;

	poperror();
	mntfree(r);
}

static Chan*
mntclone(Chan *c, Chan *nc)
{
	Mnt *m;
	Mntrpc *r;
	int alloc = 0;

	m = mntchk(c);
	r = mntralloc(c);
	if(nc == 0) {
		nc = newchan();
		alloc = 1;
	}
	if(waserror()) {
		mntfree(r);
		if(alloc)
			cclose(nc);
		nexterror();
	}

	r->request.type = Tclone;
	r->request.fid = c->fid;
	r->request.newfid = nc->fid;
	mountrpc(m, r);

	devclone(c, nc);
	nc->mqid = c->qid;
	incref(m);

	USED(alloc);
	poperror();
	mntfree(r);
	return nc;
}

static int	 
mntwalk(Chan *c, char *name)
{
	Mnt *m;
	Mntrpc *r;

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		return 0;
	}
	r->request.type = Twalk;
	r->request.fid = c->fid;
	strncpy(r->request.name, name, NAMELEN);
	mountrpc(m, r);

	c->qid = r->reply.qid;

	poperror();
	mntfree(r);
	return 1;
}

static void	 
mntstat(Chan *c, char *dp)
{
	Mnt *m;
	Mntrpc *r;

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		nexterror();
	}
	r->request.type = Tstat;
	r->request.fid = c->fid;
	mountrpc(m, r);

	memmove(dp, r->reply.stat, DIRLEN);
	mntdirfix((uchar*)dp, c);
	poperror();
	mntfree(r);
}

static Chan*
mntopen(Chan *c, int omode)
{
	Mnt *m;
	Mntrpc *r;

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		nexterror();
	}
	r->request.type = Topen;
	r->request.fid = c->fid;
	r->request.mode = omode;
	mountrpc(m, r);

	c->qid = r->reply.qid;
	c->offset = 0;
	c->mode = openmode(omode);
	c->flag |= COPEN;
	poperror();
	mntfree(r);

	return c;
}

static void	 
mntcreate(Chan *c, char *name, int omode, ulong perm)
{
	Mnt *m;
	Mntrpc *r;

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		nexterror();
	}
	r->request.type = Tcreate;
	r->request.fid = c->fid;
	r->request.mode = omode;
	r->request.perm = perm;
	strncpy(r->request.name, name, NAMELEN);
	mountrpc(m, r);

	c->qid = r->reply.qid;
	c->flag |= COPEN;
	c->mode = openmode(omode);
	poperror();
	mntfree(r);
}

static void	 
mntclunk(Chan *c, int t)
{
	Mnt *m;
	Mntrpc *r;
		
	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()){
		mntfree(r);
		mclose(m);
		nexterror();
	}

	r->request.type = t;
	r->request.fid = c->fid;
	mountrpc(m, r);
	mntfree(r);
	mclose(m);
	poperror();
}

void
mclose(Mnt *m)
{
	Mntrpc *q, *r;

	if(decref(m) != 0)
		return;

	for(q = m->queue; q; q = r) {
		r = q->list;
		q->flushed = 0;
		mntfree(q);
	}
	m->id = 0;
	cclose(m->c);
	mntpntfree(m);
}

void
mntpntfree(Mnt *m)
{
	Mnt *f, **l;

	lock(&mntalloc);
	l = &mntalloc.list;
	for(f = *l; f; f = f->list) {
		if(f == m) {
			*l = m->list;
			break;
		}
		l = &f->list;
	}

	m->list = mntalloc.mntfree;
	mntalloc.mntfree = m;
	unlock(&mntalloc);
}

static void
mntclose(Chan *c)
{
	mntclunk(c, Tclunk);
}

static void	 
mntremove(Chan *c)
{
	mntclunk(c, Tremove);
}

static void
mntwstat(Chan *c, char *dp)
{
	Mnt *m;
	Mntrpc *r;

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		nexterror();
	}
	r->request.type = Twstat;
	r->request.fid = c->fid;
	memmove(r->request.stat, dp, DIRLEN);
	mountrpc(m, r);
	poperror();
	mntfree(r);
}

long	 
mntread9p(Chan *c, void *buf, long n, ulong offset)
{
	return mnt9prdwr(Tread, c, buf, n, offset);
}

static long	 
mntread(Chan *c, void *buf, long n, ulong offset)
{
	int isdir;
	uchar *p, *e;

	isdir = 0;
	if(c->qid.path & CHDIR)
		isdir = 1;

	p = buf;
	n = mntrdwr(Tread, c, buf, n, offset);
	if(isdir) {
		for(e = &p[n]; p < e; p += DIRLEN)
			mntdirfix(p, c);
	}

	return n;
}

long	 
mntwrite9p(Chan *c, void *buf, long n, ulong offset)
{
	return mnt9prdwr(Twrite, c, buf, n, offset);
}

static long	 
mntwrite(Chan *c, void *buf, long n, ulong offset)
{
	return mntrdwr(Twrite, c, buf, n, offset);
}

long
mnt9prdwr(int type, Chan *c, void *buf, long n, ulong offset)
{
	Mnt *m;
 	ulong nr;
	Mntrpc *r;

	if(n > MAXRPC-32) {
		if(type == Twrite)
			error("write9p too long");
		n = MAXRPC-32;
	}

	m = mntchk(c);
	r = mntralloc(c);
	if(waserror()) {
		mntfree(r);
		nexterror();
	}
	r->request.type = type;
	r->request.fid = c->fid;
	r->request.offset = offset;
	r->request.data = buf;
	r->request.count = n;
	mountrpc(m, r);
	nr = r->reply.count;
	if(nr > r->request.count)
		nr = r->request.count;

	if(type == Tread)
		memmove(buf, r->reply.data, nr);

	poperror();
	mntfree(r);
	return nr;
}

long
mntrdwr(int type, Chan *c, void *buf, long n, ulong offset)
{
	Mnt *m;
 	Mntrpc *r;
	char *uba;
	ulong cnt, nr;

	m = mntchk(c);
	uba = buf;
	cnt = 0;
	for(;;) {
		r = mntralloc(c);
		if(waserror()) {
			mntfree(r);
			nexterror();
		}
		r->request.type = type;
		r->request.fid = c->fid;
		r->request.offset = offset;
		r->request.data = uba;
		r->request.count = limit(n, m->blocksize);
		mountrpc(m, r);
		nr = r->reply.count;
		if(nr > r->request.count)
			nr = r->request.count;

		if(type == Tread)
			memmove(uba, r->reply.data, nr);

		poperror();
		mntfree(r);
		offset += nr;
		uba += nr;
		cnt += nr;
		n -= nr;
		if(nr != r->request.count || n == 0 || up->swipend)
			break;
	}
	return cnt;
}

void
mountrpc(Mnt *m, Mntrpc *r)
{
	int t;

	r->reply.tag = 0;
	r->reply.type = 4;

	mountio(m, r);

	t = r->reply.type;
	switch(t) {
	case Rerror:
		error(r->reply.ename);
	case Rflush:
		error(Eintr);
	default:
		if(t == r->request.type+1)
			break;
		print("mnt: proc %s %lud: mismatch rep 0x%lux T%d R%d rq %d fls %d rp %d\n",
			up->text, up->pid,
			r, r->request.type, r->reply.type, r->request.tag, 
			r->flushtag, r->reply.tag);
		error(Emountrpc);
	}
}

void
mountio(Mnt *m, Mntrpc *r)
{
	int n;

	lock(m);
	r->flushed = 0;
	r->m = m;
	r->list = m->queue;
	m->queue = r;
	unlock(m);

	/* Transmit a file system rpc */
	n = convS2M(&r->request, r->rpc);
	if(n < 0)
		panic("bad message type in mountio");
	if(mntdebug)
		print("mnt: <- %F\n", &r->request);
	if(waserror()) {
		if(mntflush(m, r) == 0)
			nexterror();
	}
	else {
		if(devtab[m->c->type]->dc == L'M'){
			if(mnt9prdwr(Twrite, m->c, r->rpc, n, 0) != n)
				error(Emountrpc);
		}else{
			if(devtab[m->c->type]->write(m->c, r->rpc, n, 0) != n)
				error(Emountrpc);
		}
		poperror();
	}

	/* Gate readers onto the mount point one at a time */
	for(;;) {
		lock(m);
		if(m->rip == 0)
			break;
		unlock(m);
		if(waserror()) {
			if(mntflush(m, r) == 0)
				nexterror();
			continue;
		}
		sleep(&r->r, rpcattn, r);
		poperror();
		if(r->done)
			return;
	}
	m->rip = up;
	unlock(m);
	while(r->done == 0) {
		mntrpcread(m, r);
		mountmux(m, r);
	}
	mntgate(m);
}

void
mntrpcread(Mnt *m, Mntrpc *r)
{
	char *buf;
	int n, x, len;

	buf = r->rpc;
	len = MAXRPC;
	n = m->npart;
	if(n > 0) {
		memmove(buf, m->part, n);
		buf += n;
		len -= n;
		m->npart = 0;
		goto chk;
	}

	for(;;) {
		if(waserror()) {
			if(mntflush(m, r) == 0) {
				mntgate(m);
				nexterror();
			}
			continue;
		}
		r->reply.type = 0;
		r->reply.tag = 0;
		if(devtab[m->c->type]->dc == L'M')
			n = mnt9prdwr(Tread, m->c, buf, len, 0);
		else
			n = devtab[m->c->type]->read(m->c, buf, len, 0);
		poperror();
		if(n == 0)
			continue;

		buf += n;
		len -= n;
	chk:
		n = buf - r->rpc;
		x = convM2S(r->rpc, &r->reply, n);
		if(x < 0)
			error("bad message type in devmnt");
		if(x > 0) {
			n -= x;
			if(n < 0)
				panic("negative size in devmnt");
			m->npart = n;
			if(n != 0)
				memmove(m->part, r->rpc+x, n);
			if(mntdebug)
				print("mnt: %s:%lud: <- %F\n", up->env->user, up->pid, &r->reply);
			break;
		}
	}
}

void
mntgate(Mnt *m)
{
	Mntrpc *q;

	lock(m);
	m->rip = 0;
	for(q = m->queue; q; q = q->list) {
		if(q->done == 0) {
			lock(&q->r);
			if(q->r.p) {
				unlock(&q->r);
				unlock(m);
				wakeup(&q->r);
				return;
			}
			unlock(&q->r);
		}
	}
	unlock(m);
}

void
mountmux(Mnt *m, Mntrpc *r)
{
	char *dp;
	Mntrpc **l, *q;

	lock(m);
	l = &m->queue;
	for(q = *l; q; q = q->list) {
		if(q->request.tag == r->reply.tag
		|| q->flushed && q->flushtag == r->reply.tag) {
			*l = q->list;
			unlock(m);
			if(q != r) {		/* Completed someone else */
				dp = q->rpc;
				q->rpc = r->rpc;
				r->rpc = dp;
				q->reply = r->reply;
				q->done = 1;
				wakeup(&q->r);
			}else
				q->done = 1;
			return;
		}
		l = &q->list;
	}
	unlock(m);
}

int
mntflush(Mnt *m, Mntrpc *r)
{
	int n, l;
	Fcall flush;

	lock(m);
	r->flushtag = m->flushtag++;
	if(m->flushtag == Tagend)
		m->flushtag = m->flushbase;
	r->flushed = 1;
	unlock(m);

	flush.type = Tflush;
	flush.tag = r->flushtag;
	flush.oldtag = r->request.tag;
	n = convS2M(&flush, r->flush);
	if(n < 0)
		panic("bad message type in mntflush");

	if(waserror()) {
		if(strcmp(up->env->error, Eintr) == 0)
			return 1;
		mntqrm(m, r);
		return 0;
	}
	l = devtab[m->c->type]->write(m->c, r->flush, n, 0);
	if(l != n)
		error(Ehungup);
	poperror();
	return 1;
}

Mntrpc*
mntralloc(Chan *c)
{
	Mntrpc *new;

	lock(&mntalloc);
	new = mntalloc.rpcfree;
	if(new != 0)
		mntalloc.rpcfree = new->list;
	else {
		new = malloc(sizeof(Mntrpc)+MAXRPC);
		if(new == 0) {
			unlock(&mntalloc);
			exhausted("mount rpc buffer");
		}
		new->rpc = (char*)new+sizeof(Mntrpc);
		new->request.tag = mntalloc.rpctag++;
	}
	unlock(&mntalloc);
	new->c = c;
	new->done = 0;
	new->flushed = 0;
	new->flushtag = 0;
	return new;
}

void
mntfree(Mntrpc *r)
{
	lock(&mntalloc);
	r->list = mntalloc.rpcfree;
	mntalloc.rpcfree = r;
	unlock(&mntalloc);
}

void
mntqrm(Mnt *m, Mntrpc *r)
{
	Mntrpc **l, *f;

	lock(m);
	r->done = 1;
	r->flushed = 0;

	l = &m->queue;
	for(f = *l; f; f = f->list) {
		if(f == r) {
			*l = r->list;
			break;
		}
		l = &f->list;
	}
	unlock(m);
}

Mnt*
mntchk(Chan *c)
{
	Mnt *m;

	m = c->mntptr;

	/*
	 * Was it closed and reused
	 */
	if(m->id == 0 || m->id >= c->dev)
		error(Eshutdown);

	return m;
}

void
mntdirfix(uchar *dirbuf, Chan *c)
{
	int r;

	r = devtab[c->type]->dc;
	dirbuf[DIRLEN-4] = r>>0;
	dirbuf[DIRLEN-3] = r>>8;
	dirbuf[DIRLEN-2] = c->dev;
	dirbuf[DIRLEN-1] = c->dev>>8;
}

int
rpcattn(void *v)
{
	Mntrpc *r;

	r = v;
	return r->done || r->m->rip == 0;
}

Dev mntdevtab = {
	'M',
	"mnt",

	mntreset,
	mntinit,
	mntattach,
	devdetach,
	mntclone,
	mntwalk,
	mntstat,
	mntopen,
	mntcreate,
	mntclose,
	mntread,
	devbread,
	mntwrite,
	devbwrite,
	mntremove,
	mntwstat,
};
