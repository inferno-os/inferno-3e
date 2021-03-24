#include "lib9.h"
#include <libcrypt.h>

#define SLEN	256

void
setupRC4state(RC4state *key, uchar *start, int n)
{
	uchar *s;
	int i, j = 0, k = 0, t;

	key->x = key->y = 0;
	s = key->state;
	for (i = 0; i < SLEN; i++)
		s[i] = i;
	for (i = 0; i < SLEN; i++) {
		t = s[i];
		k = (start[j] + t + k)&(SLEN-1);
		s[i] = s[k];
		s[k] = t;
		if (++j == n)
			j = 0;
	}
}

void
rc4(RC4state *key, uchar *p, int len)
{
	uchar *s;
	int i, x, y, tx, ty;

	s = key->state;
	x = key->x;
	y = key->y;
	for (i = 0; i < len; i++) {
		x = (x+1)&(SLEN-1);
		tx = s[x];
		y = (tx+y)&(SLEN-1);
		s[x] = ty = s[y];
		s[y] = tx;
		p[i] ^= s[(tx+ty)&(SLEN-1)];
	} 
	key->x = x;
	key->y = y;
}
