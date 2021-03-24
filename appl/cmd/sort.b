implement Sort;

include "sys.m";
	sys: Sys;
include "bufio.m";
include "draw.m";

Sort: module
{
	init:	fn(nil: ref Draw->Context, argl: list of string);
};

init(nil : ref Draw->Context, argl : list of string)
{
	bio : ref Bufio->Iobuf;

	sys = load Sys Sys->PATH;
	bufio := load Bufio Bufio->PATH;
	stderr := sys->fildes(2);
	Iobuf : import bufio;
	if (len argl > 2) {
		sys->fprint(stderr, "usage: sort [file]\n");
		exit;
	}
	if (len argl == 2) {
		bio = bufio->open(hd tl argl, Bufio->OREAD);
		if (bio == nil) {
			sys->fprint(stderr, "cannot open %s: %r\n", hd tl argl);
			exit;
		}
	}
	else
		bio = bufio->fopen(sys->fildes(0), Bufio->OREAD);
	na := Sys->ATOMICIO;
	a := array[na] of string;
	n := 0;
	while ((s := bio.gets('\n')) != nil) {
		if (n >= na) {
			b := array[2*na] of string;
			b[0:] = a[0:na];
			a = b;
			na *= 2;
		}
		a[n++] = s;
	}	
	mergesort(a, array[n] of string, n);
	for (i := 0; i < n; i++)
		sys->print("%s", a[i]);
}

mergesort(a, b: array of string, r: int)
{
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], m);
		mergesort(a[m:r], b[m:r], r-m);
		b[0:] = a[0:r];
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i] > b[j])
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
