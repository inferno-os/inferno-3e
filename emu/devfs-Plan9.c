/*
 * Plan 9 file system interface
 */
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#undef	Dir
#undef	Qid
#undef	dirstat
#undef	dirfstat
#undef	dirfwstat
#undef	dirwstat
#undef	convD2M
#undef	convM2D

#define NIL(s)	((s) == nil || *(s) == '\0')

char	rootdir[MAXROOT] = ROOT;
static	int	rootdirlen;
static	void	fspath(Cname*, char*, char*);
static	Cname*	fswalkpath(Cname*, char*);

/* 9P2000 versions: */
extern	uint	convD2M(Dir*, uchar*, uint);
extern	uint	convM2D(uchar*, uint, Dir*, char*);

enum
{
	MAXPATH	= 1024,
	MAXCOMP	= 128
};

static Qid9p1
qid9p1(Qid q)
{
	Qid9p1 q1;

	q1.path = q.path & ~CHDIR;
	if(q.type & QTDIR)
		q1.path |= CHDIR;
	q1.vers = q.vers;
	return q1;
}

static void
namecpy(char *t, char *f)
{
	strncpy(t, f, NAMELEN);
	t[NAMELEN-1] = 0;
}

static void
conv9p1D(Dir9p1 *d1, Dir *d)
{
	d1->type = d->type;
	d1->dev = d->dev;
	d1->qid = qid9p1(d->qid);
	d1->mode = d->mode;
	d1->atime = d->atime;
	d1->mtime = d->mtime;
	d1->length = d->length;
	namecpy(d1->name, d->name);
	namecpy(d1->uid, d->uid);
	namecpy(d1->gid, d->gid);
}

void
fsinit(void)
{
	if (strcmp(rootdir,"/") == 0)
		rootdirlen = 1;
	else
		rootdirlen = strlen(rootdir)+1;	/* +1 for slash */
}

Chan*
fsattach(char *spec)
{
	Chan *c;
	char ebuf[ERRLEN];
	Dir *d;
	static int devno;
	static Lock l;

	d = dirstat(rootdir);
	if(d == nil) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	free(d);

	if (!NIL(spec) && (!globfs || strcmp(spec, "*") != 0))
		error(Ebadspec);

	c = devattach('U', spec);
	lock(&l);
	c->dev = devno++;
	unlock(&l);
	if (!NIL(spec))
		c->u.uif.spec = "/";
	c->u.uif.name = newcname(NIL(spec)? rootdir: "/");

	return c;
}

Chan*
fsclone(Chan *c, Chan *nc)
{
	nc = devclone(c, nc);
	nc->u.uif.spec = c->u.uif.spec;
	nc->u.uif.name = c->u.uif.name;
	if(nc->u.uif.name)
		incref(&nc->u.uif.name->r);
	return nc;
}

int
fswalk(Chan *c, char *name)
{
	Dir *dir;
	char path[MAXPATH];

	fspath(c->u.uif.name, name, path);
/*
	print("** ufs walk '%s' -> %s\n", path, name);
*/
	dir = dirstat(path);
	if(dir == nil)
		return 0;

	c->qid = qid9p1(dir->qid);
	free(dir);

	c->u.uif.name = fswalkpath(c->u.uif.name, name);

	return 1;
}

void
fsstat(Chan *c, char *buf)
{
	char ebuf[ERRLEN];
	Dir9p1 d1;
	Dir *d;

	d = dirstat(c->u.uif.name->s);
	if(d == nil) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	conv9p1D(&d1, d);
	free(d);
	I3convD2M(&d1, buf);
}

Chan*
fsopen(Chan *c, int mode)
{
	char ebuf[ERRLEN];

	if(c->qid.path & CHDIR) {
		c->u.uif.dir = mallocz(sizeof(DIR), 1);
		if(c->u.uif.dir == nil) {
			oserrstr(ebuf, sizeof ebuf);
			error(ebuf);
		}
	} else
		c->u.uif.dir = nil;
	osenter();
	c->u.uif.fd = open(c->u.uif.name->s, mode);
	osleave();
	if(c->u.uif.fd < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	c->mode = openmode(mode);
	c->offset = 0;
	c->u.uif.offset = 0;
	c->flag |= COPEN;
	return c;
}

void
fscreate(Chan *c, char *name, int mode, ulong perm)
{
	Dir *d;
	char path[MAXPATH], ebuf[ERRLEN];

	fspath(c->u.uif.name, name, path);
	osenter();
	c->u.uif.fd = create(path, mode, perm);
	osleave();
	if(c->u.uif.fd < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	d = dirfstat(c->u.uif.fd);
	if(d == nil) {
		oserrstr(ebuf, sizeof ebuf);
		close(c->u.uif.fd);
		error(ebuf);
	}
	c->qid = qid9p1(d->qid);
	free(d);

	c->u.uif.name = fswalkpath(c->u.uif.name, name);

	c->mode = openmode(mode);
	c->offset = 0;
	c->u.uif.offset = 0;
	c->flag |= COPEN;
}

void
fsclose(Chan *c)
{
	cnameclose(c->u.uif.name);
	if((c->flag & COPEN) == 0)
		return;
	if(c->qid.path & CHDIR && c->u.uif.dir != nil) {
		free(c->u.uif.dir->entries);
		free(c->u.uif.dir);
		c->u.uif.dir = nil;
	}
	osenter();
	close(c->u.uif.fd);
	osleave();
}

static Dir *
fsdirent(Chan *c)
{
	char ebuf[ERRLEN];

	if(c->u.uif.dir->entries == nil || c->u.uif.dir->i >= c->u.uif.dir->n) {
		free(c->u.uif.dir->entries);
		c->u.uif.dir->entries = nil;
		c->u.uif.dir->n = 0;
		c->u.uif.dir->i = 0;
		osenter();
		c->u.uif.dir->n = dirread(c->u.uif.fd, &c->u.uif.dir->entries);
		osleave();
		if(c->u.uif.dir->n < 0) {
			oserrstr(ebuf, sizeof ebuf);
			error(ebuf);
		}
	}
	return &c->u.uif.dir->entries[c->u.uif.dir->i++];
	
}

static long
fsdirread(Chan *c, void *va, long count, ulong offset)
{
	long n, i;
	Dir *de;
	Dir9p1 d1;

	count = (count/DIRLEN)*DIRLEN;

	if(c->u.uif.offset != offset){
		free(c->u.uif.dir->entries);
		c->u.uif.dir->entries = nil;
		c->u.uif.dir->n = 0;
		seek(c->u.uif.fd, 0, 0);
		for(n=0; n<offset;) {
			de = fsdirent(c);
			if(de == nil) {
				c->u.uif.offset = n;
				return 0;
			}
			n += DIRLEN;
		}
		c->u.uif.offset = offset;
	}
	for(i = 0; i < count;) {
		de = fsdirent(c);
		if(de == nil)
			break;
		conv9p1D(&d1, de);
//		d1.type = 'U';
//		d1.dev = c->dev;
		I3convD2M(&d1, va);
		va = (char*)va + DIRLEN;
		i += DIRLEN;
		c->u.uif.offset += DIRLEN;
	}
	return i;
}

long
fsread(Chan *c, void *va, long n, ulong offset)
{
	int r;
	char ebuf[ERRLEN];

	if(c->qid.path & CHDIR){	/* need to maintain offset only for directories */
		qlock(&c->u.uif.oq);
		if(waserror()){
			qunlock(&c->u.uif.oq);
			nexterror();
		}
		r = fsdirread(c, va, n, offset);
		poperror();
		qunlock(&c->u.uif.oq);
	}else{
		osenter();
		r = pread(c->u.uif.fd, va, n, offset);
		osleave();
	}
	if(r < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	return r;
}

long
fswrite(Chan *c, void *va, long n, ulong offset)
{
	int r;
	char ebuf[ERRLEN];

	osenter();
	r = pwrite(c->u.uif.fd, va, n, offset);
	osleave();
	if(r < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
	return r;
}

void
fsremove(Chan *c)
{
	char ebuf[MAXPATH];

	if(remove(c->u.uif.name->s) < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
}

void
fswstat(Chan *c, char *buf)
{
	char ebuf[MAXPATH];
	Dir9p1 d1;
	Dir d;
	int n;

	nulldir(&d);
	I3convM2D(buf, &d1);
	d.type = d1.type;
	d.dev = d1.dev;
	d.qid.type = d1.mode&CHDIR? QTDIR: QTFILE;
	d.qid.path = d1.qid.path & ~CHDIR;
	/*d.qid.vers = d1.qid.vers;*/	/* can't change */
	d.mode = d1.mode;
	d.atime = d1.atime;
	d.mtime = d1.mtime;
	/* d.length = d1.length; */	/* file server doesn't accept it */
	d.name = d1.name;
	d.uid = d1.uid;
	d.gid = d1.gid;
	n = convD2M(&d, (uchar*)ebuf, sizeof(ebuf));
	if(wstat(c->u.uif.name->s, (uchar*)ebuf, n) < 0) {
		oserrstr(ebuf, sizeof ebuf);
		error(ebuf);
	}
}

static void
fspath(Cname *c, char *name, char *path)
{
	int n;

	strcpy(path, c->s);
	n = c->len;
	if(path[n-1] != '/')
		path[n++] = '/';
	strcpy(path+n, name);
}

static Cname *
fswalkpath(Cname *c, char *name)
{
	c = addelem(c, name);
	if(strcmp(name, "..") == 0){
		cleanname(c->s);
		c->len = strlen(c->s);
	}
	return c;
}

static int
checkprefix(char **path, int *pathlen, char *prefix, int prefixlen)
{
	if (prefixlen > *pathlen)
		return 0;
	if (strncmp(*path, prefix, prefixlen) == 0) {
		*path = *path + prefixlen;
		*pathlen = *pathlen - prefixlen;
		return 1;
	}
	return 0;
}

void
setid(char *name)
{
	strncpy(up->env->user, name, NAMELEN-1);
	up->env->user[NAMELEN-1] = 0;
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
