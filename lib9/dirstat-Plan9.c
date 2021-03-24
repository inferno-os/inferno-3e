#include "lib9.h"

#ifndef Inferno4
#undef dirstat
#undef dirfstat
#undef dirwstat
#undef dirfwstat
#undef Qid
#undef Dir

static void
cpn(char *t, char *f)
{
	*t = 0;
	strncat(t, f, NAMELEN-1);
}

void
dir9p2to9p1(Dir9p1 *d1, Dir *d)
{
	cpn(d1->name, d->name);
	cpn(d1->uid, d->uid);
	cpn(d1->gid, d->gid);
	d1->qid.path = d->qid.path & ~CHDIR;
	if(d->qid.type & QTDIR)
		d1->qid.path |= CHDIR;
	d1->qid.vers = d->qid.vers;
	d1->mode = d->mode;
	d1->atime = d->atime;
	d1->mtime = d->mtime;
	d1->length = d->length;
	d1->type = d->type;
	d1->dev = d->dev;
}

int
v3dirstat(char *file, Dir9p1 *d1)
{
	Dir *d;

	d = dirstat(file);
	if(d == nil)
		return -1;
	dir9p2to9p1(d1, d);
	free(d);
	return 0;
}

int
v3dirfstat(int fd, Dir9p1 *d1)
{
	Dir *d;

	d = dirfstat(fd);
	if(d == nil)
		return -1;
	dir9p2to9p1(d1, d);
	free(d);
	return 0;
}

int
v3dirwstat(char *file, Dir9p1 *d1)
{
	Dir d;

	nulldir(&d);
	d.name = d1->name;
	/* don't change uid */
	d.gid = d1->gid;
	/* don't change qid */
	d.mode = d1->mode;
	/* don't change atime */
	d.mtime = d1->mtime;
	/* don't change length */
	/* don't change type, dev */
	return dirwstat(file, &d);
}	
#endif
