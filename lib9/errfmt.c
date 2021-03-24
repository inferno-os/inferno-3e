#include "lib9.h"
#include "fmtdef.h"

int
errfmt(Fmt *f)
{
	char buf[ERRMAX];

	rerrstr(buf, sizeof buf);
	return _fmtcpy(f, buf, utflen(buf), strlen(buf));
}
