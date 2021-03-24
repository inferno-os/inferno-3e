#include	"lib9.h"
#include	<libcrypt.h>

#define P	0x7fffffff
#define D	(P+1.0)
#define posrand()	(fastrand()&P)

double
frand()
{
	return (posrand()+posrand()/D)/D;
}
