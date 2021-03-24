#include	"dat.h"
#include	"fns.h"
#include	"error.h"

extern ulong	kerndate;

int
devno(int c, int user)
{
	int i;

	for(i = 0; devtab[i] != nil; i++) {
		if(devtab[i]->dc == c)
			return i;
	}
	if(user == 0)
		panic("devno %C 0x%ux", c, c);

	return -1;
}

void
devdir(Chan *c, Qid qid, char *n, long length, char *user, long perm, Dir *db)
{
	strcpy(db->name, n);
	db->qid = qid;
	db->type = devtab[c->type]->dc;
	db->dev = c->dev;
	db->mode = perm;
	if(qid.path & CHDIR)
		db->mode |= CHDIR;
	if(c->flag&CMSG)
		db->mode |= CHMOUNT;
	db->atime = time(0);
	db->mtime = kerndate;
	db->length = length;
	memmove(db->uid, user, NAMELEN);
	memmove(db->gid, eve, NAMELEN);
}

/*
 * the zeroth element of the table MUST be the directory itself for ..
 */
int
devgen(Chan *c, Dirtab *tab, int ntab, int i, Dir *dp)
{
	if(tab==0)
		return -1;
	if(i!=DEVDOTDOT){
		if(i >= ntab)
			return -1;
		tab += i;
	}
	devdir(c, tab->qid, tab->name, tab->length, eve, tab->perm, dp);
	return 1;
}

void
devinit(void)
{
}

Chan*
devattach(int tc, char *spec)
{
	Chan *c;
	char buf[NAMELEN+4];

	c = newchan();
	c->qid.path = CHDIR;
	c->qid.vers = 0;
	c->type = devno(tc, 0);
	sprint(buf, "#%C%s", tc, spec==nil? "": spec);
	c->name = newcname(buf);
	return c;
}

Chan *
devclone(Chan *c, Chan *nc)
{
	if(c->flag & COPEN)
		panic("clone of open file type %C\n", devtab[c->type]->dc);

	if(nc == 0)
		nc = newchan();

	nc->type = c->type;
	nc->dev = c->dev;
	nc->mode = c->mode;
	nc->qid = c->qid;
	nc->offset = c->offset;
	nc->flag = c->flag;
	nc->mh = c->mh;
	if(c->mh != nil)
		incref(&c->mh->r);
	nc->mountid = c->mountid;
	nc->u = c->u;
	nc->mchan = c->mchan;
	nc->mqid = c->mqid;
	nc->mcp = c->mcp;
	return nc;
}

int
devwalk(Chan *c, char *name, Dirtab *tab, int ntab, Devgen *gen)
{
	long i;
	Dir dir;

	isdir(c);
	if(name[0]=='.' && name[1]==0)
		return 1;
	if(name[0]=='.' && name[1]=='.' && name[2]==0){
		(*gen)(c, tab, ntab, DEVDOTDOT, &dir);
		c->qid = dir.qid;
		return 1;
	}
	for(i=0;; i++) {
		switch((*gen)(c, tab, ntab, i, &dir)){
		case -1:
			strncpy(up->env->error, Enonexist, NAMELEN);
			return 0;
		case 0:
			continue;
		case 1:
			if(strcmp(name, dir.name) == 0) {
				c->qid = dir.qid;
				return 1;
			}
			continue;
		}
	}
	return 0;
}

void
devstat(Chan *c, char *db, Dirtab *tab, int ntab, Devgen *gen)
{
	int i;
	Dir dir;
	char *p, *elem;

	for(i=0;; i++)
		switch((*gen)(c, tab, ntab, i, &dir)){
		case -1:
			if(c->qid.path & CHDIR){
				if(c->name == nil)
					elem = "???";
				else if(strcmp(c->name->s, "/") == 0)
					elem = "/";
				else
					for(elem=p=c->name->s; *p; p++)
						if(*p == '/')
							elem = p+1;
				devdir(c, c->qid, elem, 0, eve, CHDIR|0555, &dir);
				convD2M(&dir, db);
				return;
			}
			print("%s: devstat %C %lux\n",
				up->env->user, devtab[c->type]->dc, c->qid.path);
			error(Enonexist);
		case 0:
			break;
		case 1:
			if(c->qid.path == dir.qid.path) {
				if(c->flag&CMSG)
					dir.mode |= CHMOUNT;
				convD2M(&dir, db);
				return;
			}
			break;
		}
}

long
devdirread(Chan *c, char *d, long n, Dirtab *tab, int ntab, Devgen *gen)
{
	long k, m;
	Dir dir;

	k = c->offset/DIRLEN;
	for(m=0; m<n; k++) {
		switch((*gen)(c, tab, ntab, k, &dir)){
		case -1:
			return m;

		case 0:
			c->offset += DIRLEN;
			break;

		case 1:
			convD2M(&dir, d);
			m += DIRLEN;
			d += DIRLEN;
			break;
		}
	}

	return m;
}

/*
 * error(Eperm) if open permission not granted for up->user.
 */
void
devpermcheck(char *fileuid, ulong perm, int omode)
{
	ulong t;
	static int access[] = { 0400, 0200, 0600, 0100 };

	if(strcmp(up->env->user, fileuid) == 0)
		perm <<= 0;
	else
	if(strcmp(up->env->user, eve) == 0)
		perm <<= 3;
	else
		perm <<= 6;

	t = access[omode&3];
	if((t&perm) != t)
		error(Eperm);
}

Chan *
devopen(Chan *c, int omode, Dirtab *tab, int ntab, Devgen *gen)
{
	int i;
	Dir dir;

	for(i=0;; i++) {
		switch((*gen)(c, tab, ntab, i, &dir)){
		case -1:
			goto Return;
		case 0:
			break;
		case 1:
			if(c->qid.path == dir.qid.path) {
				devpermcheck(dir.uid, dir.mode, omode);
				goto Return;
			}
			break;
		}
	}
Return:
	c->offset = 0;
	if((c->qid.path&CHDIR) && omode!=OREAD)
		error(Eperm);
	c->mode = openmode(omode);
	c->flag |= COPEN;
	return c;
}

Block*
devbread(Chan *c, long n, ulong offset)
{
	Block *bp;

	bp = allocb(n);
	if(waserror()) {
		freeb(bp);
		nexterror();
	}
	bp->wp += devtab[c->type]->read(c, bp->wp, n, offset);
	poperror();
	return bp;
}

long
devbwrite(Chan *c, Block *bp, ulong offset)
{
	long n;

	if(waserror()) {
		freeb(bp);
		nexterror();
	}
	n = devtab[c->type]->write(c, bp->rp, BLEN(bp), offset);
	poperror();
	freeb(bp);

	return n;	
}

void
devcreate(Chan *c, char *name, int mode, ulong perm)
{
	USED(c);
	USED(name);
	USED(mode);
	USED(perm);
	error(Eperm);
}

void
devremove(Chan *c)
{
	USED(c);
	error(Eperm);
}

void
devwstat(Chan *c, char *buf)
{
	USED(c);
	USED(buf);
	error(Eperm);
}

int
readstr(ulong off, char *buf, ulong n, char *str)
{
	int size;

	size = strlen(str);
	if(off >= size)
		return 0;
	if(off+n > size)
		n = size-off;
	memmove(buf, str+off, n);
	return n;
}

int
readnum(ulong off, char *buf, ulong n, ulong val, int size)
{
	char tmp[64];

	if(size > 64) size = 64;

	snprint(tmp, sizeof(tmp), "%*.0lud ", size, val);
	if(off >= size)
		return 0;
	if(off+n > size)
		n = size-off;
	memmove(buf, tmp+off, n);
	return n;
}

/*
 *  parse a command written to a device
 */
Cmdbuf*
parsecmd(char *p, int n)
{
	Cmdbuf *cb;

	cb = malloc(sizeof(*cb));
	if(cb == nil)
		error(Enomem);
	
	if(n > sizeof(cb->buf)-1)
		n = sizeof(cb->buf)-1;
	memmove(cb->buf, p, n);
	if(n > 0 && cb->buf[n-1] == '\n')
		n--;
	cb->buf[n] = '\0';
	cb->nf = tokenize(cb->buf, cb->f, nelem(cb->f));
	return cb;
}
