#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"libcrypt.h"

enum {
	Captimeout = 15,	/* seconds until expiry */
	Capidletime = 60	/* idle seconds before capwatch exits */
};

typedef struct Caps Caps;
struct Caps
{
	uchar	hash[SHA1dlen];
	ulong	time;
	Caps*	next;
};

struct {
	QLock	l;
	Caps*	caps;
	int	kpstarted;
} allcaps;

static void
capwatch(void*)
{
	Caps *c, **l;
	int idletime;

	idletime = 0;
	for(;;){
		tsleep(&up->sleep, return0, nil, 1000);
		qlock(&allcaps.l);
		for(l = &allcaps.caps; (c = *l) != nil;)
			if(++c->time > Captimeout){
				*l = c->next;
				free(c);
			}else
				l = &c->next;
		if(allcaps.caps == nil){
			if(++idletime > Capidletime){
				allcaps.kpstarted = 0;
				qunlock(&allcaps.l);
				pexit("", 0);
			}
		}else
			idletime = 0;
		qunlock(&allcaps.l);
	}
}

int
capwritehash(uchar *a, int l)
{
	Caps *c;

	if(l != SHA1dlen)
		return -1;
	if(strcmp(up->env->user, eve) != 0)
		return  -1;
	c = malloc(sizeof(*c));
	if(c == nil)
		return -1;
	memmove(c->hash, a, l);
	c->time = 0;
	qlock(&allcaps.l);
	c->next = allcaps.caps;
	allcaps.caps = c;
	if(!allcaps.kpstarted){
		allcaps.kpstarted = 1;
		kproc("capwatch", capwatch, 0, 0);
	}
	qunlock(&allcaps.l);
	return 0;
}

int
capwriteuse(uchar *a, int len)
{
	int n;
	uchar digest[SHA1dlen];
	char buf[128], *p, *users[3];
	Caps *c, **l;

	if(len >= sizeof(buf)-1)
		return -1;
	memmove(buf, a, len);
	buf[len] = 0;
	p = strrchr(buf, '@');
	if(p == nil)
		return -1;
	*p++ = 0;
	len = strlen(p);
	n = strlen(buf);
	if(len == 0 || n == 0)
		return -1;
	hmac_sha1((uchar*)buf, n, (uchar*)p, len, digest, nil);
	n = getfields(buf, users, nelem(users), 0, "@");
	if(n != 2 || *users[0] == 0 || *users[1] == 0)
		return -1;
	qlock(&allcaps.l);
	for(l = &allcaps.caps; (c = *l) != nil; l = &c->next)
		if(memcmp(c->hash, digest, sizeof(c->hash)) == 0){
			*l = c->next;
			qunlock(&allcaps.l);
			free(c);
			if(strcmp(up->env->user, users[0]) != 0)
				return -1;
			strncpy(up->env->user, users[1], NAMELEN-1);
			up->env->user[NAMELEN-1] = 0;
			return 0;
		}
	qunlock(&allcaps.l);
	return -1;
}
