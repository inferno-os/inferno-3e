implement RC4;

include "rc4.m";

SLEN : con 256;

setupRC4state(start : array of byte, n : int): ref RC4state
{
	t : int;

	s := array[SLEN] of byte;
	for (i := 0; i < SLEN; i++)
		s[i] = byte i;
	j := 0;
	k := 0;
	for (i = 0; i < SLEN; i++) {
		t = int s[i];
		k = (int start[j] + t + k)&(SLEN-1);
		s[i] = s[k];
		s[k] = byte t;
		if(++j == n)
			j = 0;
	}
	return ref RC4state(s, 0, 0);
}

rc4(key : ref RC4state, a : array of byte, n : int)
{
	tx, ty : int;

	s := key.state;
	x := key.x;
	y := key.y;
	for (i := 0; i < n; i++) {
		x = (x+1)&(SLEN-1);
		tx = int s[x];
		y = (tx+y)&(SLEN-1);
		ty = int s[y];
		s[x] = byte ty;
		s[y] = byte tx;
		a[i] ^= s[(tx+ty)&(SLEN-1)];
	}
	key.x = x;
	key.y = y;
}

