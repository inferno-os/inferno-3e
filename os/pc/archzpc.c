#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"

/*
  * board-specific support for the Ziatech 5512
  */

#define	FLASHMEM	0xfff80000

/*
 * for devflash.c:/^flashreset
 * retrieve flash type, virtual base and length and return 0;
 * return -1 on error (no flash)
 */
int
archflashreset(char *type, void **addr, long *length)
{
	strcpy(type, "DD28F032SA");
	*addr = (void *)FLASHMEM;
	*length = 2*1024*1024;
	return 0;
}
