#include "lib9.h"

int
canlock(Lock *l)
{
	int v;
	int *la;

	la = &l->val;

	_asm {
		mov	eax, la
		mov	ebx, 1
		xchg	ebx, [eax]
		mov	v, ebx
	}
	switch(v){
	case 0:
		return 1;
	case 1:
		return 0;
	default:
		print("canlock corrupted 0x%lux\n", v);
	}
}
