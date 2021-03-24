#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

typedef	struct Fid	Fid;
typedef	struct Export	Export;
typedef	struct Exq	Exq;
typedef	struct Uqid Uqid;

enum
{
	Nfidhash	= 32,
	Nqidhash = 32,
	QIDGENBASE = (1<<26)-1,
	MAXRPC		= MAXMSG+MAXFDATA,
	MAXDIRREAD	= (MAXFDATA/DIRLEN)*DIRLEN
};

struct Export
{
	Ref	r;
	Exq*	work;
	QLock	fidlock;
	Fid*	fid[Nfidhash];
	QLock	qidlock;
	Uqid*	qids[Nqidhash];
	ulong	pathgen;
	Chan*	io;
	Chan*	root;
	Pgrp*	pgrp;
	Fgrp*	fgrp;
	Egrp*	egrp;
	int	async;
	char	user[NAMELEN];
	int	npart;
	char	part[MAXRPC];
};

struct Fid
{
	Fid*	next;
	Fid**	last;
	Chan*	chan;
	ulong	offset;
	int	fid;
	int	ref;		/* fcalls using the fid; locked by Export.Lock */
	int	attached;	/* fid attached or cloned but not clunked */
	int	isroot;	/* fid represents exported root */
	Uqid*	qid;	/* generated qid */
};

struct Uqid
{
	Ref;
	int	type;
	int	dev;
	ulong	oldpath;
	ulong	newpath;
	Uqid*	next;
};

struct Exq
{
	Exq*	next;
	int	shut;		/* has been noted for shutdown */
	int	flushtag;	/* !=NOTAG if flushed */
	Export*	export;
	Proc*	slave;
	Fcall	rpc;
	char	buf[MAXRPC];
};

struct
{
	Lock	l;
	QLock	qwait;
	Rendez	rwait;
	Exq*	head;		/* work waiting for a slave */
	Exq*	tail;
}exq;

static void	exshutdown(Export*);
static int	exflushed(Export*, int, int);
static void	exslave(void*);
static void	exfree(Export*);
static void	exportproc(void*);
static void	exreply(Exq*, char*);
static Uqid* uqidalloc(Export*, Chan*);
static void freeuqid(Export*, Uqid*);

static char*	Exattach(Export*, Fcall*);
static char*	Exclone(Export*, Fcall*);
static char*	Exclunk(Export*, Fcall*);
static char*	Excreate(Export*, Fcall*);
static char*	Exnop(Export*, Fcall*);
static char*	Exopen(Export*, Fcall*);
static char*	Exread(Export*, Fcall*);
static char*	Exremove(Export*, Fcall*);
static char*	Exstat(Export*, Fcall*);
static char*	Exwalk(Export*, Fcall*);
static char*	Exwrite(Export*, Fcall*);
static char*	Exwstat(Export*, Fcall*);

static char	*(*fcalls[Tmax])(Export*, Fcall*);

static char	Enofid[]   = "no such fid";
static char	Eseekdir[] = "can't seek on a directory";
static char	Eopen[]	= "walk of open fid";
static char	Emode[] = "open/create -- unknown mode";
static char	Edupfid[]	= "fid in use";
static char	Ereaddir[] = "unaligned read of a directory";
static char	Eaccess[] = "read/write -- not open in suitable mode";
static char	Ecount[] = "read/write -- count too big";
int	exdebug = 0;

int
export(int fd, char *dir, int async)
{
	Chan *c, *dc;
	Pgrp *pg;
	Egrp *eg;
	Export *fs;

	if(waserror())
		return -1;
	c = fdtochan(up->env->fgrp, fd, ORDWR, 1, 1);
	poperror();

	pg = up->env->pgrp;
	if(waserror()){
		cclose(c);
		return -1;
	}
	if(dir == nil){
		dc = pg->slash;
		incref(dc);
		dc = domount(dc);	/* this insulates the export from subsequent changes to / */
	}else
		dc = namec(dir, Atodir, 0, 0);
	poperror();


	fs = malloc(sizeof(Export));
	if(fs == nil){
		cclose(c);
		cclose(dc);
		error(Enomem);
	}
	fs->r.ref = 1;

	fs->pgrp = pg;
	incref(pg);
	eg = up->env->egrp;
	fs->egrp = eg;
	if(eg != nil)
		incref(eg);
	fs->fgrp = newfgrp(nil);
	memmove(fs->user, up->env->user, sizeof(fs->user));
	fs->root = dc;
	fs->io = c;
	fs->pathgen = QIDGENBASE;
	c->flag |= CMSG;
	fs->async = async;
	if(async)
		kproc("exportfs", exportproc, fs, 0);
	else
		exportproc(fs);

	return 0;
}

static void
exportinit(void)
{
	lock(&exq.l);
	if(fcalls[Tnop] != nil) {
		unlock(&exq.l);
		return;
	}

	fcalls[Tnop] = Exnop;
	fcalls[Tattach] = Exattach;
	fcalls[Tclone] = Exclone;
	fcalls[Twalk] = Exwalk;
	fcalls[Topen] = Exopen;
	fcalls[Tcreate] = Excreate;
	fcalls[Tread] = Exread;
	fcalls[Twrite] = Exwrite;
	fcalls[Tclunk] = Exclunk;
	fcalls[Tremove] = Exremove;
	fcalls[Tstat] = Exstat;
	fcalls[Twstat] = Exwstat;
	unlock(&exq.l);
}

static void
exportproc(void *v)
{
	Export *fs;
	Exq *q;
	int async;
	char *buf;
	int n, cn, len;

	exportinit();

	fs = v;
	for(;;){
		q = smalloc(sizeof(Exq));
		q->rpc.data = q->buf + MAXMSG;

		buf = q->buf;
		len = MAXRPC;
		if(fs->npart) {
			memmove(buf, fs->part, fs->npart);
			buf += fs->npart;
			len -= fs->npart;
			goto chk;
		}
		for(;;) {
			if(waserror())
				goto bad;

			n = devtab[fs->io->type]->read(fs->io, buf, len, 0);
			poperror();

			if(n <= 0)
				goto bad;

			buf += n;
			len -= n;
	chk:
			n = buf - q->buf;

			/* convM2S returns size of correctly decoded message */
			cn = convM2S(q->buf, &q->rpc, n);
			if(cn < 0){
				print("bad message type %d in exportproc\n", q->rpc.type);
				goto bad;
			}
			if(cn > 0) {
				n -= cn;
				if(n < 0){
					print("negative size in exportproc\n");
					goto bad;
				}
				fs->npart = n;
				if(n != 0)
					memmove(fs->part, q->buf+cn, n);
				break;
			}
		}
		if(exdebug)
			print("export <- %F\n", &q->rpc);

		q->flushtag = NOTAG;
		q->shut = 0;
		q->slave = nil;

		q->export = fs;
		incref(&fs->r);

		if(q->rpc.type == Tflush){
			if(exflushed(fs, q->rpc.oldtag, q->rpc.tag)){ /* exflushed replied, or slave will reply */
				exfree(fs);
				free(q);
			}else
				exreply(q, "exportproc");
			continue;
		}

		lock(&exq.l);
		if(exq.head == nil)
			exq.head = q;
		else
			exq.tail->next = q;
		q->next = nil;
		exq.tail = q;
		unlock(&exq.l);
		if(exq.qwait.head == nil)
			kproc("exslave", exslave, nil, 0);
		wakeup(&exq.rwait);
	}
bad:
	async = fs->async;

	free(q);
	exshutdown(fs);
	exfree(fs);

	if(async == 0)
		return;

	pexit("mount shut down", 0);
}

static int
exflushed(Export *fs, int tag, int flushtag)
{
	Exq *q, **last;
	Proc *p;

	lock(&exq.l);
	for(last = &exq.head; (q = *last) != nil; last = &q->next)
		if(q->export == fs && q->rpc.tag == tag){
			*last = q->next;
			unlock(&exq.l);
			q->rpc.type = Rflush;
			q->rpc.tag = flushtag;
			exreply(q, "exflush");
			return 1;
		}
	unlock(&exq.l);

	lock(&fs->r);
	for(q = fs->work; q != nil; q = q->next){
		if(q->rpc.tag == tag){
			q->flushtag = flushtag;
			p = q->slave;
			unlock(&fs->r);
			swiproc(p, 0);
			return 1;
		}
	}
	unlock(&fs->r);

	return 0;
}

static void
exshutdown(Export *fs)
{
	Exq *q, **last;
	Proc *p;

	lock(&exq.l);
	for(last = &exq.head; (q = *last) != nil;){
		if(q->export == fs){
			*last = q->next;
			exfree(fs);
			free(q);
			continue;
		}
		last = &q->next;
	}
	unlock(&exq.l);

	lock(&fs->r);
	q = fs->work;
	while(q != nil){
		if(q->shut){
			q = q->next;
			continue;
		}
		q->shut = 1;
		p = q->slave;
		unlock(&fs->r);
		swiproc(p, 0);
		lock(&fs->r);
		q = fs->work;
	}
	unlock(&fs->r);
}

static void
exfreefids(Export *fs)
{
	Fid *f, *n;
	int i;

	for(i = 0; i < Nfidhash; i++){
		for(f = fs->fid[i]; f != nil; f = n){
			n = f->next;
			f->attached = 0;
			if(f->ref == 0) {
				if(f->chan != nil)
					cclose(f->chan);
				freeuqid(fs, f->qid);
				free(f);
			}
		}
	}
}

static void
exfree(Export *fs)
{
	if(decref(&fs->r) != 0)
		return;
	closepgrp(fs->pgrp);
	closeegrp(fs->egrp);
	closefgrp(fs->fgrp);
	cclose(fs->root);
	cclose(fs->io);
	exfreefids(fs);
	free(fs);
}

static int
exwork(void*)
{
	return exq.head != nil;
}

static void
exslave(void*)
{
	Export *fs;
	Exq *q, *t, **last;
	char *err;

	for(;;){
		qlock(&exq.qwait);
		if(waserror()){
			qunlock(&exq.qwait);
			continue;
		}
		sleep(&exq.rwait, exwork, nil);
		poperror();

		lock(&exq.l);
		q = exq.head;
		if(q == nil) {
			unlock(&exq.l);
			qunlock(&exq.qwait);
			continue;
		}
		exq.head = q->next;
		q->slave = up;
		unlock(&exq.l);

		qunlock(&exq.qwait);

		fs = q->export;
		lock(&fs->r);
		q->next = fs->work;
		fs->work = q;
		q->shut = 0;
		unlock(&fs->r);

		up->env->pgrp = q->export->pgrp;
		up->env->egrp = q->export->egrp;
		up->env->fgrp = q->export->fgrp;
		memmove(up->env->user, q->export->user, sizeof(up->env->user));

		if(exdebug > 1)
			print("exslave dispatch %F\n", &q->rpc);

		if(q->rpc.type >= Tmax || !fcalls[q->rpc.type])
			err = "bad fcall type";
		else
			err = (*fcalls[q->rpc.type])(fs, &q->rpc);

		lock(&fs->r);
		notkilled();
		for(last = &fs->work; (t = *last) != nil; last = &t->next)
			if(t == q){
				*last = q->next;
				break;
			}
		unlock(&fs->r);

		if(q->shut) {
			exfree(q->export);
			free(q);
			continue;
		}

		if(q->flushtag == NOTAG){
			q->rpc.type++;
			if(err){
				q->rpc.type = Rerror;
				strncpy(q->rpc.ename, err, ERRLEN);
			}
		}else{
			q->rpc.type = Rflush;
			q->rpc.tag = q->flushtag;
		}
		exreply(q, "exslave");
	}
	print("exslave shut down");
	pexit("exslave shut down", 0);
}

static void
exreply(Exq *q, char *who)
{
	Export *fs;
	int n;

	n = convS2M(&q->rpc, q->buf);
	if(n < 0)
		panic("bad message type in %s", who);

	if(exdebug)
		print("%s -> %F\n", who, &q->rpc);

	fs = q->export;
	if(!waserror()){
		devtab[fs->io->type]->write(fs->io, q->buf, n, 0);
		poperror();
	}
	if(exdebug > 1)
		print("%s written %d\n", who, q->rpc.tag);

	exfree(fs);
	free(q);
}

static int
uqidhash(ulong path)
{
	return ((path>>16) ^ (path>>8) ^ path) & (Nqidhash-1);
}

static Uqid **
uqidlook(Uqid **tab, Chan *c, ulong path)
{
	Uqid **hp, *q;

	for(hp = &tab[uqidhash(path)]; (q = *hp) != nil; hp = &q->next)
		if(q->type == c->type && q->dev == c->dev && q->oldpath == path)
			break;
	return hp;
}

static int
uqidexists(Uqid **tab, ulong path)
{
	int i;
	Uqid *q;

	for(i=0; i<Nqidhash; i++)
		for(q = tab[i]; q != nil; q = q->next)
			if(q->newpath == path)
				return 1;
	return 0;
}

static Uqid *
uqidalloc(Export *fs, Chan *c)
{
	Uqid **hp, *q;

	qlock(&fs->qidlock);
	hp = uqidlook(fs->qids, c, c->qid.path);
	if((q = *hp) != nil){
		incref(q);
		qunlock(&fs->qidlock);
		return q;
	}
	q = mallocz(sizeof(*q), 1);
	if(q == nil){
		qunlock(&fs->qidlock);
		error(Enomem);
	}
	q->ref = 1;
	q->type = c->type;
	q->dev = c->dev;
	q->oldpath = c->qid.path;
	q->newpath = c->qid.path;
	while(uqidexists(fs->qids, q->newpath)){
		if(fs->pathgen == 0)
			fs->pathgen = QIDGENBASE;
		q->newpath = fs->pathgen | (c->qid.path & CHDIR);
		fs->pathgen--;
	}
	q->next = nil;
	*hp = q;
	qunlock(&fs->qidlock);
	return q;
}

static void
freeuqid(Export *fs, Uqid *q)
{
	Uqid **hp;

	if(q == nil)
		return;
	qlock(&fs->qidlock);
	if(decref(q) == 0){
		hp = &fs->qids[uqidhash(q->oldpath)];
		for(; *hp != nil; hp = &(*hp)->next)
			if(*hp == q){
				*hp = q->next;
				free(q);
				break;
			}
	}
	qunlock(&fs->qidlock);
}

static Qid
Exrmtqid(Chan *c, Uqid *qid)
{
	Qid q;

	q.path = qid->newpath;
	q.vers = c->qid.vers;
	return q;
}

static Fid*
Exmkfid(Export *fs, int fid)
{
	ulong h;
	Fid *f, *nf;

	nf = malloc(sizeof(Fid));
	if(nf == nil)
		return nil;
	qlock(&fs->fidlock);
	h = fid % Nfidhash;
	for(f = fs->fid[h]; f != nil; f = f->next){
		if(f->fid == fid){
			qunlock(&fs->fidlock);
			free(nf);
			return nil;
		}
	}

	nf->next = fs->fid[h];
	if(nf->next != nil)
		nf->next->last = &nf->next;
	nf->last = &fs->fid[h];
	fs->fid[h] = nf;

	nf->fid = fid;
	nf->ref = 1;
	nf->attached = 1;
	nf->isroot = 0;
	nf->offset = 0;
	nf->chan = nil;
	qunlock(&fs->fidlock);
	return nf;
}

static Fid*
Exgetfid(Export *fs, int fid)
{
	Fid *f;
	ulong h;

	qlock(&fs->fidlock);
	h = fid % Nfidhash;
	for(f = fs->fid[h]; f; f = f->next) {
		if(f->fid == fid){
			if(f->attached == 0)
				break;
			f->ref++;
			qunlock(&fs->fidlock);
			return f;
		}
	}
	qunlock(&fs->fidlock);
	return nil;
}

static void
Exputfid(Export *fs, Fid *f)
{
	Chan *c;

	qlock(&fs->fidlock);
	f->ref--;
	if(f->ref == 0 && f->attached == 0){
		c = f->chan;
		f->chan = nil;
		*f->last = f->next;
		if(f->next != nil)
			f->next->last = f->last;
		qunlock(&fs->fidlock);
		if(c != nil)
			cclose(c);
		freeuqid(fs, f->qid);
		free(f);
		return;
	}
	qunlock(&fs->fidlock);
}

static char*
Exnop(Export *, Fcall *)
{
	return nil;
}

static char*
Exattach(Export *fs, Fcall *rpc)
{
	Fid *f;

	f = Exmkfid(fs, rpc->fid);
	if(f == nil)
		return Edupfid;
	if(waserror()){
		f->attached = 0;
		Exputfid(fs, f);
		return up->env->error;
	}
	f->chan = cclone(fs->root, nil);
	f->isroot = 1;
	f->qid = uqidalloc(fs, f->chan);
	poperror();
	rpc->qid = Exrmtqid(f->chan, f->qid);
	Exputfid(fs, f);
	return nil;
}

static char*
Exclone(Export *fs, Fcall *rpc)
{
	Fid *f, *nf;

	if(rpc->fid == rpc->newfid)
		return Einuse;
	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	nf = Exmkfid(fs, rpc->newfid);
	if(nf == nil){
		Exputfid(fs, f);
		return Einuse;
	}
	if(waserror()){
		Exputfid(fs, f);
		Exputfid(fs, nf);
		return up->env->error;
	}
	nf->chan = cclone(f->chan, nil);
	nf->isroot = f->isroot;
	nf->qid = f->qid;
	incref(nf->qid);
	poperror();
	Exputfid(fs, f);
	Exputfid(fs, nf);
	return nil;
}

static char*
Exclunk(Export *fs, Fcall *rpc)
{
	Fid *f;

	f = Exgetfid(fs, rpc->fid);
	if(f != nil){
		f->attached = 0;
		Exputfid(fs, f);
	}
	return nil;
}

static char*
Exwalk(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;
	char *name;
	Uqid *qid;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	name = rpc->name;
	if(f->isroot && strcmp(name, "..") == 0)
		name = "";
	c = f->chan;
	if(c->flag & COPEN)
		error(Eopen);
	if(walk(&f->chan, name, 1) < 0)
		error(Enonexist);
	poperror();

	if(f->isroot && c != f->chan)
		f->isroot = 0;
	c = f->chan;
	qid = uqidalloc(fs, c);
	freeuqid(fs, f->qid);
	f->qid = qid;
	rpc->qid = Exrmtqid(c, f->qid);
	Exputfid(fs, f);
	return nil;
}

static char*
Exopen(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;
	Uqid *qid;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	c = f->chan;
	if(c->flag & COPEN)
		error(Emode);
	c = devtab[c->type]->open(c, rpc->mode);
	if(rpc->mode & ORCLOSE)
		c->flag |= CRCLOSE;
	poperror();

	qid = uqidalloc(fs, c);
	freeuqid(fs, f->qid);
	f->qid = qid;
	f->chan = c;
	f->offset = 0;
	rpc->qid = Exrmtqid(c, f->qid);
	Exputfid(fs, f);
	return nil;
}

static char*
Excreate(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;
	Uqid *qid;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	nameok(rpc->name);
	c = f->chan;
	if(c->flag & COPEN)
		error(Emode);
	if(c->mh != nil && !(c->flag&CCREATE))
		c = createdir(c);
	devtab[c->type]->create(c, rpc->name, rpc->mode, rpc->perm);
	poperror();

	qid = uqidalloc(fs, c);
	freeuqid(fs, f->qid);
	f->qid = qid;
	f->chan = c;
	rpc->qid = Exrmtqid(c, f->qid);
	Exputfid(fs, f);
	return nil;
}

static char*
Exread(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;
	long off;
	int dir, n, seek;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	c = f->chan;
	if((c->flag & COPEN) == 0)
		error(Emode);
	if(c->mode != OREAD && c->mode != ORDWR)
		error(Eaccess);
	if(rpc->count < 0 || rpc->count > MAXFDATA)
		error(Ecount);
	dir = c->qid.path & CHDIR;
	if(dir){
		rpc->count -= rpc->count%DIRLEN;
		if(rpc->offset%DIRLEN || rpc->count==0){
			Exputfid(fs, f);
			return Ereaddir;
		}
		if(f->offset > rpc->offset){
			Exputfid(fs, f);
			return Eseekdir;
		}
	}

	if(waserror()) {
		Exputfid(fs, f);
		return up->env->error;
	}

	for(;;){
		n = rpc->count;
		seek = 0;
		off = rpc->offset;
		if(dir && f->offset != off){
			off = f->offset;
			n = rpc->offset - off;
			if(n > MAXDIRREAD)
				n = MAXDIRREAD;
			seek = 1;
		}
		if(dir && c->mh != nil)
			n = unionread(c, rpc->data, n);
		else {
			c->offset = off;
			n = devtab[c->type]->read(c, rpc->data, n, off);
			lock(c);
			c->offset += n;
			unlock(c);
		}
		f->offset = off + n;
		if(n == 0 || !seek)
			break;
	}
	rpc->count = n;
	poperror();
	Exputfid(fs, f);
	return nil;
}

static char*
Exwrite(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	c = f->chan;
	if((c->flag & COPEN) == 0)
		error(Emode);
	if(c->mode != OWRITE && c->mode != ORDWR)
		error(Eaccess);
	if(c->qid.path & CHDIR)
		error(Eisdir);
	if(rpc->count < 0 || rpc->count > MAXFDATA)
		error(Ecount);
	rpc->count = devtab[c->type]->write(c, rpc->data, rpc->count, rpc->offset);
	c->offset += rpc->count;
	poperror();
	Exputfid(fs, f);
	return nil;
}

static char*
Exstat(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	c = f->chan;
	devtab[c->type]->stat(c, rpc->stat);
	poperror();
	Exputfid(fs, f);
	return nil;
}

static char*
Exwstat(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		Exputfid(fs, f);
		return up->env->error;
	}
	nameok(rpc->stat);	/* name is known to be first member */
	c = f->chan;
	devtab[c->type]->wstat(c, rpc->stat);
	poperror();
	Exputfid(fs, f);
	return nil;
}

static char*
Exremove(Export *fs, Fcall *rpc)
{
	Fid *f;
	Chan *c;

	f = Exgetfid(fs, rpc->fid);
	if(f == nil)
		return Enofid;
	if(waserror()){
		f->attached = 0;
		Exputfid(fs, f);
		return up->env->error;
	}
	c = f->chan;
	devtab[c->type]->remove(c);
	poperror();

	/*
	 * chan is already clunked by remove.
	 * however, we need to recover the chan,
	 * and follow sysremove's lead in making to point to root.
	 */
	c->type = 0;

	f->attached = 0;
	Exputfid(fs, f);
	return nil;
}
