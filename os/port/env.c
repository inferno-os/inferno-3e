#include "u.h"
#include "../port/lib.h"
#include "../port/error.h"
#include "mem.h"
#include	"dat.h"
#include	"fns.h"

/*
 * kernel interface to environment variables
 */
Egrp*
newegrp(void)
{
	Egrp	*e;

	e = smalloc(sizeof(Egrp));
	e->ref = 1;
	return e;
}

void
closeegrp(Egrp *e)
{
	Evalue *el, *nl;

	if(e == nil || decref(e) != 0)
		return;
	for (el = e->entries; el != nil; el = nl) {
		free(el->var);
		if (el->val)
			free(el->val);
		nl = el->next;
		free(el);
	}
	free(e);
}

void
egrpcpy(Egrp *to, Egrp *from)
{
	Evalue *e, *ne, **last;

	if(from == nil)
		return;
	last = &to->entries;
	qlock(from);
	for (e = from->entries; e != nil; e = e->next) {
		ne = smalloc(sizeof(Evalue));
		ne->var = smalloc(strlen(e->var)+1);
		strcpy(ne->var, e->var);
		if (e->val) {
			ne->val = smalloc(e->len);
			memmove(ne->val, e->val, e->len);
			ne->len = e->len;
		}
		ne->qid.path = ++to->path;
		*last = ne;
		last = &ne->next;
	}
	qunlock(from);
}

void
ksetenv(char *var, char *val)
{
	Chan *c;
	char buf[2*NAMELEN];

	sprint(buf, "#e/%s", var);
	c = namec(buf, Acreate, OWRITE, 0600);
	devtab[c->type]->write(c, val, strlen(val), 0);
	cclose(c);
}
