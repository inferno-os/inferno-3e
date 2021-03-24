#include "lib9.h"
#include "kernel.h"
#include <libcrypt.h>
#include "rand.h"

void
reallyRandomBytes(uchar *buf, int numbytes)
{
	int randfd, n;
	
	randfd = kopen("/dev/random", OREAD);
	if(randfd < 0)
		handle_exception(CRITICAL, "can't open /dev/random");
	n = kread(randfd, buf, numbytes);
	kclose(randfd);
	if(n != numbytes){
		/* can only fail if we're killed */
		if(n < 0)
			n = 0;
		memset(buf, 0xAB, numbytes-n);
	}
}
