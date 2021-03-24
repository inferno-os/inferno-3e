#include "lib9.h"

void
oserrstr(char *buf, uint nerr)
{
	*buf = 0;
	errstr(buf, nerr);
}

#ifdef Plan9v3

#undef errstr

int
v4errstr(char *buf, int nerr)
{
	char ebuf[ERRLEN];

	utfecpy(ebuf, ebuf+ERRLEN, buf);
	errstr(ebuf);
	utfecpy(buf, buf+nerr, ebuf);
}
#endif
