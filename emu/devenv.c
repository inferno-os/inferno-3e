/*
 *	devenv - environment
 */
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

static void envremove(Chan*);

static int
envgen(Chan *c, Dirtab *d, int nd, int s, Dir *dp)
{
	Egrp *eg;
	Evalue *e;

	USED(d);
	USED(nd);
	if(s == DEVDOTDOT){
		devdir(c, c->qid, "#e", 0, eve, CHDIR|0775, dp);
		return 1;
	}
	eg = up->env->egrp;
	qlock(&eg->l);
	for(e = eg->entries; e != nil && s != 0; e = e->next)
		s--;
	if(e == nil) {
		qunlock(&eg->l);
		return -1;
	}
	devdir(c, e->qid, e->var, e->len, eve, 0666, dp);
	qunlock(&eg->l);
	return 1;
}

static Chan*
envattach(char *spec)
{
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
	qlock(&eg->l);
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil) {
		qunlock(&eg->l);
		error(Enonexist);
	}
	if(mode == (OWRITE|OTRUNC) && e->val) {
		free(e->val);
		e->val = 0;
		e->len = 0;
		e->qid.vers++;
	}
	qunlock(&eg->l);
	c->offset = 0;
	c->flag |= COPEN;
	c->mode = mode&~OTRUNC;
	return c;
}

static void
envcreate(Chan *c, char *name, int mode, ulong perm)
{
	Egrp *eg;
	Evalue *e, *le;

	USED(perm);
	if(c->qid.path != CHDIR)
		error(Eperm);
	eg = up->env->egrp;
	qlock(&eg->l);
	for(le = nil, e = eg->entries; e != nil; le = e, e = e->next)
		if(strcmp(e->var, name) == 0) {
			qunlock(&eg->l);
			error(Eexist);
		}
	e = malloc(sizeof(Evalue));
	e->var = malloc(strlen(name)+1);
	strcpy(e->var, name);
	e->val = 0;
	e->len = 0;
	e->qid.path = ++eg->path;
	if (le == nil)
		eg->entries = e;
	else
		le->next = e;
	e->qid.vers = 0;
	c->qid = e->qid;
	eg->vers++;
	qunlock(&eg->l);
	c->offset = 0;
	c->flag |= COPEN;
	c->mode = mode;
}

static void
envclose(Chan * c)
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
	qlock(&eg->l);
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil) {
		qunlock(&eg->l);
		error(Enonexist);
	}
	if(offset + n > e->len)
		n = e->len - offset;
	if(n <= 0)
		n = 0;
	else
		memmove(a, e->val+offset, n);
	qunlock(&eg->l);
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
	qlock(&eg->l);
	for(e = eg->entries; e != nil; e = e->next)
		if(e->qid.path == c->qid.path)
			break;
	if(e == nil) {
		qunlock(&eg->l);
		error(Enonexist);
	}
	ve = offset+n;
	if(ve > e->len) {
		s = malloc(ve);
		memmove(s, e->val, e->len);
		if(e->val)
			free(e->val);
		e->val = s;
		e->len = ve;
	}
	memmove(e->val+offset, a, n);
	e->qid.vers++;
	qunlock(&eg->l);
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
	qlock(&eg->l);
	for(l = &eg->entries; *l != nil; l = &(*l)->next)
		if((*l)->qid.path == c->qid.path)
			break;
	e = *l;
	if(e == nil) {
		qunlock(&eg->l);
		error(Enonexist);
	}
	*l = e->next;
	eg->vers++;
	qunlock(&eg->l);
	free(e->var);
	if(e->val != nil)
		free(e->val);
	free(e);
}

Dev envdevtab = {
	'e',
	"env",

	devinit,
	envattach,
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
