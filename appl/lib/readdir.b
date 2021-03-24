implement Readdir;

include "sys.m";
	sys: Sys;
	Dir: import sys;
include "readdir.m";

init(path: string, sortkey: int): (array of ref Dir, int)
{
	sys = load Sys Sys->PATH;
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		return (nil, -1);
	
	d := array[200] of Dir;
	n := 0;

	while((nr := sys->dirread(fd, d[n:])) > 0) {
		n += nr;
		if(n == len d)
			d = (array[2*len d] of Dir)[0:] = d;
	}
	if(nr < 0)
		return (nil, -1);
	d = d[0:n];
	a := makerefs(d, sortkey);
	sortkey &= ~COMPACT;
	if((sortkey & ~DESCENDING) == NONE)
		return (a, len a);
	d = nil;
	return sortdir(a, sortkey);
}

makerefs(d: array of Dir, key: int): array of ref Dir
{
	n := len d;
	a := array[n] of ref Dir;
	if ((key & COMPACT) == 0) {
		for(i := 0; i < n; i++)
			a[i] = ref d[i];
	} else {
		ht := array[41] of list of string;
		for (i := j := 0; i < n; i++)
			if (hashadd(ht, d[i].name))
				a[j++] = ref d[i];
		a = a[0:j];
	}
	return a;
}

sortdir(a: array of ref Dir, key: int): (array of ref Dir, int)
{
	mergesort(a, array[len a] of ref Dir, key);
	return (a, len a);
}
	
# mergesort because it's stable.
mergesort(a, b: array of ref Dir, key: int)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], key);
		mergesort(a[m:], b[m:], key);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (greater(b[i], b[j], key))
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}

greater(x, y: ref Dir, sortkey: int): int
{
	case (sortkey) {
	NAME => return(x.name > y.name);
	ATIME => return(x.atime < y.atime);
	MTIME => return(x.mtime < y.mtime);
	SIZE => return(x.length > y.length);
	NAME|DESCENDING => return(x.name < y.name);
	ATIME|DESCENDING => return(x.atime > y.atime);
	MTIME|DESCENDING => return(x.mtime > y.mtime);
	SIZE|DESCENDING => return(x.length < y.length);
	}
	return 0;
}

# from tcl_strhash.b
hashfn(key: string, n : int): int
{
	h := i := 0;
        while(i<len key){
                h = 10*h + key[i];
                h = h%n;
                i++;
        }
        return h%n;
}

hashadd(ht: array of list of string, nm: string): int
{
	if (ht == nil)
		return 1;
	idx := hashfn(nm, len ht);
	for (ent := ht[idx]; ent != nil; ent = tl ent)
		if (hd ent == nm)
			return 0;
	ht[idx] = nm :: ht[idx];
	return 1;
}
