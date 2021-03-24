#include	"dat.h"
#include	"fns.h"
#include	"error.h"

enum
{
	CNAMESLOP	= 20
};

struct
{
	Lock	l;
	int	fid;
	Chan	*free;
	Chan	*list;
}chanalloc;

#define SEP(c) ((c) == 0 || (c) == '/')
void cleancname(Cname*);

int
isdotdot(char *p)
{
	return p[0]=='.' && p[1]=='.' && p[2]=='\0';
}

int
incref(Ref *r)
{
	int x;

	lock(&r->l);
	x = ++r->ref;
	unlock(&r->l);
	return x;
}

int
decref(Ref *r)
{
	int x;

	lock(&r->l);
	x = --r->ref;
	unlock(&r->l);
	if(x < 0) 
		panic("decref");

	return x;
}

static char isfrog[256]=
{
	/*NUL*/	1, 1, 1, 1, 1, 1, 1, 1,
	/*BKS*/	1, 1, 1, 1, 1, 1, 1, 1,
	/*DLE*/	1, 1, 1, 1, 1, 1, 1, 1,
	/*CAN*/	1, 1, 1, 1, 1, 1, 1, 1
};

void
chandevinit(void)
{
	int i;


/*	isfrog[' '] = 1; */	/* let's see what happens */
	isfrog['/'] = 1;
	isfrog[0x7f] = 1;

	for(i=0; devtab[i] != nil; i++)
		devtab[i]->init();
}

Chan*
newchan(void)
{
	Chan *c;

	lock(&chanalloc.l);
	c = chanalloc.free;
	if(c != 0)
		chanalloc.free = c->next;
	unlock(&chanalloc.l);

	if(c == 0) {
		c = malloc(sizeof(Chan));
		if(c == nil)
			error(Enomem);
		lock(&chanalloc.l);
		c->fid = ++chanalloc.fid;
		c->link = chanalloc.list;
		chanalloc.list = c;
		unlock(&chanalloc.l);
	}

	/* if you get an error before associating with a dev,
	   close calls rootclose, a nop */
	c->type = 0;
	c->flag = 0;
	c->r.ref = 1;
	c->dev = 0;
	c->offset = 0;
	c->mh = 0;
	c->xmh = 0;
	c->uri = 0;
	memset(&c->u, 0, sizeof(c->u));
	c->mchan = 0;
	c->mcp = 0;
	c->mqid.path = 0;
	c->mqid.vers = 0;
	c->name = 0;
	return c;
}

static Ref ncname;

Cname*
newcname(char *s)
{
	Cname *n;
	int i;

	n = malloc(sizeof(Cname));
	i = strlen(s);
	n->len = i;
	n->alen = i+CNAMESLOP;
	n->s = malloc(n->alen);
	memmove(n->s, s, i+1);
	n->r.ref = 1;
	incref(&ncname);
	return n;
}

void
cnameclose(Cname *n)
{
	if(n == 0)
		return;
	if(decref(&n->r))
		return;
	decref(&ncname);
	free(n->s);
	free(n);
}

Cname*
addelem(Cname *n, char *s)
{
	int i, a;
	char *t;
	Cname *new;

	if(s[0]=='.' && s[1]=='\0')
		return n;

	if(n->r.ref > 1){
		/* copy on write */
		new = newcname(n->s);
		cnameclose(n);
		n = new;
	}

	i = strlen(s);
	if(n->len+1+i+1 > n->alen){
		a = n->len+1+i+1 + CNAMESLOP;
		t = malloc(a);
		memmove(t, n->s, n->len+1);
		free(n->s);
		n->s = t;
		n->alen = a;
	}
	if(n->len>0 && n->s[n->len-1]!='/' && s[0]!='/')	/* don't insert extra slash if one is present */
		n->s[n->len++] = '/';
	memmove(n->s+n->len, s, i+1);
	n->len += i;
	return n;
}

void
chanfree(Chan *c)
{
	c->flag = CFREE;

	if(c->mh != nil){
		putmhead(c->mh);
		c->mh = nil;
	}

	cnameclose(c->name);

	lock(&chanalloc.l);
	c->next = chanalloc.free;
	chanalloc.free = c;
	unlock(&chanalloc.l);
}

void
cclose(Chan *c)
{
	if(c == 0)
		return;

	if(c->flag&CFREE)
		panic("close");

	if(decref(&c->r))
		return;

	if(!waserror()) {
		devtab[c->type]->close(c);
		poperror();
	}

	chanfree(c);
}

void
isdir(Chan *c)
{
	if(c->qid.path & CHDIR)
		return;
	error(Enotdir);
}

int
eqqid(Qid a, Qid b)
{
	return a.path==b.path && a.vers==b.vers;
}

int
eqchan(Chan *a, Chan *b, int pathonly)
{
	if(a->qid.path != b->qid.path)
		return 0;
	if(!pathonly && a->qid.vers!=b->qid.vers)
		return 0;
	if(a->type != b->type)
		return 0;
	if(a->dev != b->dev)
		return 0;
	return 1;
}

int
cmount(Chan *new, Chan *old, int flag, char *spec)
{
	Pgrp *pg;
	int order, flg;
	Mhead *m, **l;
	Mount *nm, *f, *um, **h;

	if(CHDIR & (old->qid.path^new->qid.path))
		error(Emount);

	order = flag&MORDER;
	if((old->qid.path&CHDIR)==0 && order != MREPL)
		error(Emount);

	pg = up->env->pgrp;
	wlock(&pg->ns);

	l = &MOUNTH(pg, old);
	for(m = *l; m; m = m->hash) {
		if(eqchan(m->from, old, 1))
			break;

		l = &m->hash;
	}

	if(m == 0) {
		/*
		 *  nothing mounted here yet.  create a mount
		 *  head and add to the hash table.
		 */
		m = malloc(sizeof(Mhead));
		if(m == nil){
			wunlock(&pg->ns);
			error(Enomem);
		}
		m->r.ref = 1;
		m->from = old;
		incref(&old->r);
		m->hash = *l;
		*l = m;

		/*
		 *  if this is a union mount, add the old
		 *  node to the mount chain.
		 */
		if(order != MREPL)
			m->mount = newmount(m, old, 0, 0);
	}
	wlock(&m->lock);
	if(waserror()){
		wunlock(&m->lock);
		nexterror();
	}
	wunlock(&pg->ns);

	nm = newmount(m, new, flag, spec);
	if(new->mh != nil && new->mh->mount != nil) {
		/*
		 *  copy a union when binding it onto a directory
		 */
		flg = order;
		if(order == MREPL)
			flg = MAFTER;
		h = &nm->next;
		um = new->mh->mount;
		for(um = um->next; um; um = um->next) {
			f = newmount(m, um->to, flg, um->spec);
			*h = f;
			h = &f->next;
		}
	}

	if(m->mount && order == MREPL) {
		mountfree(m->mount);
		m->mount = 0;
	}

	if(flag & MCREATE)
		new->flag |= CCREATE;

	if(m->mount && order == MAFTER) {
		for(f = m->mount; f->next; f = f->next)
			;
		f->next = nm;
	}
	else {
		for(f = nm; f->next; f = f->next)
			;
		f->next = m->mount;
		m->mount = nm;
	}

	poperror();
	wunlock(&m->lock);
	return nm->mountid;
}

void
cunmount(Chan *mnt, Chan *mounted)
{
	Pgrp *pg;
	Mhead *m, **l;
	Mount *f, **p;

	pg = up->env->pgrp;
	wlock(&pg->ns);

	l = &MOUNTH(pg, mnt);
	for(m = *l; m; m = m->hash) {
		if(eqchan(m->from, mnt, 1))
			break;
		l = &m->hash;
	}

	if(m == 0) {
		wunlock(&pg->ns);
		error(Eunmount);
	}

	wlock(&m->lock);
	if(mounted == 0) {
		*l = m->hash;
		wunlock(&pg->ns);
		mountfree(m->mount);
		m->mount = nil;
		cclose(m->from);
		wunlock(&m->lock);
		putmhead(m);
		return;
	}
	wunlock(&pg->ns);

	p = &m->mount;
	for(f = *p; f; f = f->next) {
		/* BUG: Needs to be 2 pass */
		if(eqchan(f->to, mounted, 1) ||
		  (f->to->mchan && eqchan(f->to->mchan, mounted, 1))) {
			*p = f->next;
			f->next = 0;
			mountfree(f);
			if(m->mount == nil) {
				*l = m->hash;
				cclose(m->from);
				wunlock(&m->lock);
				putmhead(m);
				return;
			}
			wunlock(&m->lock);
			return;
		}
		p = &f->next;
	}
	wunlock(&m->lock);
	error(Eunion);
}

Chan*
cclone(Chan *c, Chan *nc)
{
	nc = devtab[c->type]->clone(c, nc);
	if(nc != nil){
		nc->name = c->name;
		if(c->name)
			incref(&c->name->r);
	}
	return nc;
}

Chan*
domount(Chan *c)
{
	Chan *nc;
	Mhead *m;
	volatile struct { Pgrp *p; } pg;

	pg.p = up->env->pgrp;
	rlock(&pg.p->ns);
	if(c->mh){
		putmhead(c->mh);
		c->mh = 0;
	}

	for(m = MOUNTH(pg.p, c); m; m = m->hash){
		rlock(&m->lock);
		if(eqchan(m->from, c, 1)) {
			if(waserror()) {
				runlock(&m->lock);
				nexterror();
			}
			runlock(&pg.p->ns);
			nc = cclone(m->mount->to, 0);
			if(nc->mh != nil)
				putmhead(nc->mh);
			nc->mh = m;
			nc->xmh = m;
			incref(&m->r);
			cnameclose(nc->name);
			nc->name = c->name;
			incref(&c->name->r);
			cclose(c);
			c = nc;
			poperror();
			runlock(&m->lock);
			return c;
		}
		runlock(&m->lock);
	}

	runlock(&pg.p->ns);
	return c;
}

Chan*
undomount(Chan *c)
{
	Chan *nc;
	Mount *t;
	Mhead **h, **he, *f;
	volatile struct { Pgrp *p; } pg;

	pg.p = up->env->pgrp;
	rlock(&pg.p->ns);
	if(waserror()) {
		runlock(&pg.p->ns);
		nexterror();
	}

	he = &pg.p->mnthash[MNTHASH];
	for(h = pg.p->mnthash; h < he; h++) {
		for(f = *h; f; f = f->hash) {
			for(t = f->mount; t; t = t->next) {
				if(eqchan(c, t->to, 1)) {
					/*
					 * We want to come out on the left hand side of the mount
					 * point using the element of the union that we entered on.
					 * To do this, find the element that has a from name of
					 * c->name->s.
					 */
					if(strcmp(t->head->from->name->s, c->name->s) != 0)
						continue;
					nc = cclone(t->head->from, 0);
					/* don't need to update nc->name because c->name is same! */
					cclose(c);
					c = nc;
					break;
				}
			}
		}
	}
	poperror();
	runlock(&pg.p->ns);
	return c;
}

Chan *
updatecname(Chan *c, char *name, int dotdot)
{
	if(c->name == nil)
		c->name = newcname(name);
	else
		c->name = addelem(c->name, name);
	
	if(dotdot){
		cleancname(c->name);	/* could be cheaper */
		c = undomount(c);
	}
	return c;
}

int
walk(Chan **cp, char *name, int domnt)
{
	Mount *f;
	int dotdot;
	volatile struct { Chan *c; } c;
	Chan *ac;

	ac = *cp;

	if(name[0] == '\0')
		return 0;

	dotdot = 0;
	if(name[0] == '.' && name[1] == '.' && name[2] == '\0') {
		if(eqchan(up->env->pgrp->slash, ac, 1))
			return 0;
		*cp = ac = undomount(ac);
		dotdot = 1;
	}

	ac->flag &= ~CCREATE;	/* not inherited through a walk */
	if(devtab[ac->type]->walk(ac, name) != 0) {
		/* walk succeeded: update name associated with *cp (ac) */
		*cp = updatecname(*cp, name, dotdot);
		if(domnt)
			*cp = domount(*cp);
		return 0;
	}

	if(ac->mh == nil)
		return -1;

	c.c = nil;

	rlock(&ac->mh->lock);
	if(waserror()) {
		runlock(&ac->mh->lock);
		if(c.c != nil)
			cclose(c.c);
		nexterror();
	}
	for(f = ac->mh->mount; f; f = f->next) {
		c.c = cclone(f->to, 0);
		c.c->flag &= ~CCREATE;	/* not inherited through a walk */
		if(devtab[c.c->type]->walk(c.c, name) != 0)
			break;
		cclose(c.c);
		c.c = 0;
	}
	poperror();
	runlock(&ac->mh->lock);

	if(c.c == nil)
		return -1;

	if(c.c->mh){
		putmhead(c.c->mh);
		c.c->mh = nil;
	}

	/* replace c->name by ac->name */
	cnameclose(c.c->name);
	c.c->name = ac->name;
	if(ac->name)
		incref(&ac->name->r);
	c.c = updatecname(c.c, name, dotdot);
	cclose(ac);
	*cp = c.c;

	if(domnt)
		*cp = domount(c.c);
	return 0;
}

/*
 * c is a mounted non-creatable directory.  find a creatable one.
 */
Chan*
createdir(Chan *c)
{
	Mount *f;
	Chan *nc;

	rlock(&c->mh->lock);
	if(waserror()) {
		runlock(&c->mh->lock);
		nexterror();
	}
	for(f = c->mh->mount; f; f = f->next) {
		if(f->to->flag&CCREATE) {
			nc = cclone(f->to, 0);
			if(nc->mh != nil)
				putmhead(nc->mh);
			nc->mh = c->mh;
			incref(&c->mh->r);
			runlock(&c->mh->lock);
			poperror();
			cclose(c);
			return nc;
		}
	}
	error(Enocreate);
	return 0;
}

/*
 * In place, rewrite name to compress multiple /, eliminate ., and process ..
 */
void
cleancname(Cname *n)
{
	char *p;

	if(n->s[0] == '#'){
		p = strchr(n->s, '/');
		if(p == nil)
			return;
		cleanname(p);

		/*
		 * The correct name is #i rather than #i/,
		 * but the correct name of #/ is #/.
		 */
		if(strcmp(p, "/")==0 && n->s[1] != '/')
			*p = '\0';
	}else
		cleanname(n->s);
	n->len = strlen(n->s);
}

/*
 * Turn a name into a channel.
 * &name[0] is known to be a valid address.  It may be a kernel address.
 */
Chan*
namec(char *name, int amode, int omode, ulong perm)
{
	Rune r;
	char *elem;
	Cname *cname;
	int t, n, newname;
	int mntok, isdot;
	volatile struct { Chan *c; } c;
	Chan *cc;
	char createerr[ERRLEN];

	if(name[0] == 0)
		error(Enonexist);

	if(utfrune(name, '\\') != 0)
		error(Enonexist);

	newname = 1;
	cname = nil;
	if(waserror()){
		cnameclose(cname);
		nexterror();
	}

	elem = up->elem;
	mntok = 1;
	isdot = 0;
	switch(name[0]) {
	case '/':
		cname = newcname(name);	/* save this before advancing */
		name = skipslash(name);
		c.c = cclone(up->env->pgrp->slash, 0);
		if(*name == 0)
			isdot = 1;
		break;
	case '#':
		cname = newcname(name);	/* save this before advancing */
		mntok = 0;
		elem[0] = 0;
		n = 0;
		while(*name && (*name != '/' || n < 2)){
			if(n >= NAMELEN-1)
				error(Efilename);
			elem[n++] = *name++;
		}
		elem[n] = '\0';
		n = chartorune(&r, elem+1)+1;
		if(r == 'M')
			error(Enoattach);
		/*
		 *  the nodevs exceptions are
		 *	|  it only gives access to pipes you create
		 *	e  this process's environment
		 *	s  private file2chan creation space
		 *	D private secure sockets name space
		 */
		if(up->env->pgrp->nodevs && utfrune("|esD", r) == nil)
			error(Enoattach);
		t = devno(r, 1);
		if(t == -1)
			error(Ebadsharp);

		c.c = devtab[t]->attach(elem+n);
		name = skipslash(name);
		break;
	default:
		cname = newcname(up->env->pgrp->dot->name->s);
		cname = addelem(cname, name);
		c.c = cclone(up->env->pgrp->dot, 0);
		name = skipslash(name);
		if(*name == 0)
			isdot = 1;
	}

	if(waserror()){
		cclose(c.c);
		nexterror();
	}

	name = nextelem(name, elem);

	/*
	 *  If mounting, don't follow the mount entry for root or the
	 *  current directory.
	 */
	if(mntok && !isdot && !(amode==Amount && elem[0]==0))
		c.c = domount(c.c);		/* see case Atodir below */

	while(*name) {
		if(walk(&c.c, elem, mntok) < 0)
			error(Enonexist);
		name = nextelem(name, elem);
	}

	switch(amode) {
	case Aaccess:
		if(isdot) {
			c.c = domount(c.c);
			break;
		}
		if(walk(&c.c, elem, mntok) < 0)
			error(Enonexist);
		break;

	case Atodir:
		/*
		 * Directories (e.g. for cd) are left before the mount point,
		 * so one may mount on / or . and see the effect.
		 */
		if(walk(&c.c, elem, 0) < 0)
			error(Enonexist);
		if(!(c.c->qid.path & CHDIR))
			error(Enotdir);
		break;

	case Aopen:
		if(isdot)
			c.c = domount(c.c);
		else {
			if(walk(&c.c, elem, mntok) < 0)
				error(Enonexist);
		}
	Open:
		cc = c.c;
		c.c = devtab[c.c->type]->open(c.c, omode);
		if(cc != c.c)
			newname = 0;

		if(omode & OCEXEC)
			c.c->flag |= CCEXEC;
		if(omode & ORCLOSE)
			c.c->flag |= CRCLOSE;
		break;

	case Amount:
		/*
		 * When mounting on an already mounted upon directory,
		 * one wants subsequent mounts to be attached to the
		 * original directory, not the replacement.
		 */
		if(walk(&c.c, elem, 0) < 0)
			error(Enonexist);
		break;

	case Acreate:
		if(isdot)
			error(Eisdir);

		nameok(elem, 0);
		if(walk(&c.c, elem, 1) == 0){
			omode |= OTRUNC;
			goto Open;
		}

		/*
		 *  the file didn't exist, try the create
		 */
		if(c.c->mh != nil && !(c.c->flag&CCREATE))
			c.c = createdir(c.c);

		/*
		 * protect against the open/create race.
		 * This is not a complete fix. It just reduces the window.
		 */
		if(waserror()) {
			strcpy(createerr, up->env->error);
			if(walk(&c.c, elem, 1) < 0)
				error(createerr);
			omode |= OTRUNC;
			goto Open;
		}
		devtab[c.c->type]->create(c.c, elem, omode, perm);
		if(omode & OCEXEC)
			c.c->flag |= CCEXEC;
		if(omode & ORCLOSE)
			c.c->flag |= CRCLOSE;
		poperror();
		break;

	default:
		panic("unknown namec access %d\n", amode);
	}
	poperror();

	if(newname){
		cleancname(cname);
		cnameclose(c.c->name);
		c.c->name = cname;
	}else
		cnameclose(cname);

	poperror();
	return c.c;
}

/*
 * name[0] is addressable.
 */
char*
skipslash(char *name)
{
    Again:
	while(*name == '/')
		name++;
	if(*name=='.' && (name[1]==0 || name[1]=='/')){
		name++;
		goto Again;
	}
	return name;
}

void
nameok(char *elem, int slashok)
{
	char *eelem;

	USED(slashok);
	eelem = elem+NAMELEN;
	while(*elem) {
		if(isfrog[*(uchar*)elem])
			error(Ebadchar);
		elem++;
		if(elem >= eelem)
			error(Efilename);
	}
}

/*
 * name[0] should not be a slash.
 */
char*
nextelem(char *name, char *elem)
{
	int w;
	char *end;
	Rune r;

	if(*name == '/')
		error(Efilename);
	end = utfrune(name, '/');
	if(end == 0)
		end = strchr(name, 0);
	w = end-name;
	if(w >= NAMELEN)
		error(Efilename);
	memmove(elem, name, w);
	elem[w] = 0;
	while(name < end) {
		name += chartorune(&r, name);
		if(r<sizeof(isfrog) && isfrog[r])
			error(Ebadchar);
	}
	return skipslash(name);
}

void
putmhead(Mhead *m)
{
	if(decref(&m->r) == 0)
		free(m);
}
