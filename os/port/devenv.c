/*
 *	devenv - environment
 */
#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include	"dat.h"
#include	"fns.h"

static void envremove(Chan*);

enum
{
	Maxenvsize = 16300,
};

static int
envgen(Chan *c, Dirtab*, int, int s, Dir *dp)
{
	Egrp *eg;
	Evalue *e;

	if(s == DEVDOTDOT){
		devdir(c, c->qid, "#e", 0, eve, CHDIR|0775, dp);
		return 1;
	}
	eg = up->env->egrp;
	qlock(eg);
	for(e = eg->entries; e != nil && s != 0; e = e->next)
		s--;
	if(e == nil) {
		qunlock(eg);
		return -1;
	}
	devdir(c, e->qid, e->var, e->len, eve, 0666, dp);
	qunlock(eg);
	return 1;
}

static Chan*
envattach(char *spec)
{
	if(up->env == nil || up->env->egrp == nil)
		error(Enodev);
	return devattach('e', spec);
}

static int
envwalk(Chan *c, char *name)
{
	return devwalk(c, name, 0, 0, envgen);
}

static void
envstat(Chan *c, char *db)
{
	if(c->qid.path & CHDIR)
		c->qid.vers = up->env->egrp->vers;
	devstat(c, db, 0, 0, envgen);
}

static Chan *
envopen(Chan *c, int mode)
{
	Egrp *eg;
	Evalue *e;
	
	if(c->qid.path & CHDIR) {
		if(mode != OREAD)
			error(Eperm);
		c->mode = mode;
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}
	eg = up->env->egrp;
	qlock(eg);
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil) {
		qunlock(eg);
		error(Enonexist);
	}
	if((mode & OTRUNC) && e->val) {
		free(e->val);
		e->val = 0;
		e->len = 0;
		e->qid.vers++;
	}
	qunlock(eg);
	c->mode = openmode(mode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
envcreate(Chan *c, char *name, int mode, ulong)
{
	Egrp *eg;
	Evalue *e, **le;

	if(c->qid.path != CHDIR)
		error(Eperm);
	mode = openmode(mode);
	eg = up->env->egrp;
	qlock(eg);
	if(waserror()){
		qunlock(eg);
		nexterror();
	}
	for(le = &eg->entries; (e = *le) != nil; le = &e->next)
		if(strcmp(e->var, name) == 0)
			error(Eexist);
	e = smalloc(sizeof(Evalue));
	e->var = smalloc(strlen(name)+1);
	strcpy(e->var, name);
	e->val = 0;
	e->len = 0;
	e->qid.path = ++eg->path;
	e->next = nil;
	e->qid.vers = 0;
	*le = e;
	c->qid = e->qid;
	eg->vers++;
	poperror();
	qunlock(eg);
	c->offset = 0;
	c->flag |= COPEN;
	c->mode = mode;
}

static void
envclose(Chan *c)
{
	if(c->flag & CRCLOSE)
		envremove(c);
}

static long
envread(Chan *c, void *a, long n, ulong offset)
{
	Egrp *eg;
	Evalue *e;

	if(c->qid.path & CHDIR)
		return devdirread(c, a, n, 0, 0, envgen);
	eg = up->env->egrp;
	qlock(eg);
	if(waserror()){
		qunlock(eg);
		nexterror();
	}
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil)
		error(Enonexist);
	if(offset + n > e->len)
		n = e->len - offset;
	if(n <= 0)
		n = 0;
	else
		memmove(a, e->val+offset, n);
	poperror();
	qunlock(eg);
	return n;
}

static long
envwrite(Chan *c, void *a, long n, ulong offset)
{
	char *s;
	int ve;
	Egrp *eg;
	Evalue *e;

	if(n <= 0)
		return 0;
	eg = up->env->egrp;
	qlock(eg);
	if(waserror()){
		qunlock(eg);
		nexterror();
	}
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil)
		error(Enonexist);
	ve = offset+n;
	if(ve > Maxenvsize)
		error(Etoobig);
	if(ve > e->len) {
		s = smalloc(ve);
		memmove(s, e->val, e->len);
		if(e->val != nil)
			free(e->val);
		e->val = s;
		e->len = ve;
	}
	memmove(e->val+offset, a, n);
	e->qid.vers++;
	poperror();
	qunlock(eg);
	return n;
}

static void
envremove(Chan *c)
{
	Egrp *eg;
	Evalue *e, **l;

	if(c->qid.path & CHDIR)
		error(Eperm);
	eg = up->env->egrp;
	qlock(eg);
	for(l = &eg->entries; (e = *l) != nil; l = &e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil) {
		qunlock(eg);
		error(Enonexist);
	}
	*l = e->next;
	eg->vers++;
	qunlock(eg);
	free(e->var);
	if(e->val != nil)
		free(e->val);
	free(e);
}

Dev envdevtab = {
	'e',
	"env",

	devreset,
	devinit,
	envattach,
	devdetach,
	devclone,
	envwalk,
	envstat,
	envopen,
	envcreate,
	envclose,
	envread,
	devbread,
	envwrite,
	devbwrite,
	envremove,
	devwstat
};
