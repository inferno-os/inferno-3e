#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "bootparam.h"

/* note: returns 0 for invalid addresses */

ulong
va2pa(void *v)
{
	int idx;
	ulong pte, ste, *ttb;

	idx = MmuL1x((ulong)v);
	ttb = (ulong*)conf.pagetable;
	ste = ttb[idx];
	switch(ste & MmuL1type) {
	case MmuL1section:
		return (ste & 0xfff00000)|((ulong)v & 0x000fffff);
	case MmuL1page:
		pte = ((ulong *)(ste & 0xfffffc00))[((ulong)v >> 12) & 0xff]; 
		switch(pte & 3) {
		case MmuL2large:
			return (pte & 0xffff0000)|((ulong)v & 0x0000ffff);
		case MmuL2small:
			return (pte & 0xfffff000)|((ulong)v & 0x00000fff);
		}
	}
	return 0;
}

enum {
	MmuSectionSh = 20,
	MmuSmallPageSh = 12,
	SectionPages = MmuSection/MmuSmallPage,
	PtAlign = (1<<10)
};

#define ALT_BOOTP	0xF1000000

static void
relocv(ulong lomem, void **a)
{
	if ((*a > (void *)0x0) && (*a < (void*)lomem))
		*a = (void *)((ulong)*a + ALT_BOOTP);
}

static void
reloclist(ulong lomem, char **l)
{
	while (*l)
		relocv(lomem, l++);
}

static void
flushmmu(void)
{
	ulong mr;

	mr = mmuctlregr();
	if (mr & CpCDcache) {
		writeBackDC();
		flushDcache();
	}
	if (mr & CpCwb)
		drainWBuffer();
	flushTLB();		/* invalidate previous mapping */
}

/*
 * This will make an interrupt vector container at ALT_IVEC (ffff0000)
 *  and move bootparam from 0-7fff to ALT_BOOTP.
 * This leaves us a space that is inaccessible in the range
 *   ffff1000 to 00007fff.  So offsets from '0' pointers and limbo
 *   references via 'H' are trapped by hardware.
 * The 32K originally at 0 is already filled with pagetables and
 *  bootparams, so is not wasted.
 */
void
remaplomem(void)
{
	int ii, ero, ap;
	ulong *ptable, *stable, mem0, lomem;

	/*
	 * L1 table, typically sections, not page tables.
	 */
	stable = (ulong*)conf.pagetable;
	mem0 = va2pa((void *)0);	/* reuse pages currently at 0 */

	/*
	 * Map ALT_BOOTP to copy of first 1Meg
	 */
	stable[MmuL1x(ALT_BOOTP)] = stable[MmuL1x(0)];
	flushmmu();

	/*
	 * Relocate the addresses in bootparam
	 */
	if (bootparam == nil) {
		lomem = 0x8000;
		relocv(lomem, (void**)&conf.pagetable);
	}
	else {
		lomem = (ulong)bootparam->lomem;
		reloclist(lomem, bootparam->argv);
		relocv(lomem, &bootparam->argv);
		reloclist(lomem, bootparam->envp);
		relocv(lomem, &bootparam->envp);
		relocv(lomem, &bootparam->bootname);
		relocv(lomem, (void**)&conf.pagetable);
		relocv(lomem, &bootparam);
	}

	/*
	 * Get space for 2 page tables
	 */
	ptable = xspanalloc(2 * sizeof *ptable * SectionPages, PtAlign, 0);
	/*
	 * Build a page table for ALT_IVEC, all invalid (0) except for
	 *  ivec page, mapped read-only.
	 */
	ptable[MmuL2x(ALT_IVEC)] = mem0 | MmuL2AP(MmuAPsro) | MmuWB | MmuIDC | MmuL2small;
	stable[MmuL1x(ALT_IVEC)] = va2pa(ptable) | MmuL1page;
	ptable += SectionPages;
	/*
	 * Build a new page table for the 1 Meg section at '0'.
	 * Leave the 1st 32K invalid (0), then duplicate the map
	 *  from 32K -> 1Meg, making pages below etext read-only.
	 */
	ero = (ulong)etext >> 12;
	
	for (ii = MmuL2x(lomem); ii < SectionPages; ii++) {
		if (ii < ero && !conf.textwrite)
			ap = MmuL2AP(MmuAPsro);
		else
			ap = MmuL2AP(MmuAPsrw);
		ptable[ii] = (mem0 + ii*MmuSmallPage) | ap | MmuWB | MmuIDC | MmuL2small;
	}
	stable[MmuL1x(0)] = va2pa(ptable) | MmuL1page;
	flushmmu();		/* invalidate previous mapping */
}

static void
setmmu1(ulong pa, ulong epa, ulong va, ulong attrib)
{
	ulong *stable;

	stable = (ulong*)conf.pagetable;
	for(; pa < epa; pa += (1<<MmuSectionSh)){
		stable[MmuL1x(va)] = pa | MmuL1section | (1<<4) | attrib;
		va += 1<<MmuSectionSh;
	}
}

/*
 * this maps whole sections only
 */
void
mmusetmap(Pagemap *map, int n)
{
	while(--n >= 0)
		setmmu1(map->phys, map->lim, map->virt, map->attrib);
	flushmmu();
}
