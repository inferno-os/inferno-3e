implement Ls;

include "sys.m";
	sys: Sys;
	FD, Dir: import Sys;

include "draw.m";
	Context: import Draw;

include "daytime.m";
	daytime: Daytime;

include "readdir.m";
	readdir: Readdir;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

Ls: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

PREFIX: con 16r40000000;

dopt := 0;
eopt := 0;
lopt := 0;
nopt := 0;
popt := 0;
qopt := 0;
topt := 0;
uopt := 0;
now:	int;
sortby:	int;

out: ref Bufio->Iobuf;
stderr: ref FD;

dwIndex: int;
dwQueue: array of Dir;

badmodule(p: string)
{
	sys->fprint(stderr, "ls: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmodule(Bufio->PATH);
	readdir = load Readdir Readdir->PATH;
	if(readdir == nil)
		badmodule(Readdir->PATH);
	str = load String String->PATH;
	if(str == nil)
		badmodule(String->PATH);

	stderr = sys->fildes(2);
	out = bufio->fopen(sys->fildes(1), Bufio->OWRITE);
	rev := 0;
	sortby = Readdir->NAME;
	compact := 0;

	if(argv !=nil)
		argv = tl argv;
	while(argv != nil) {
		s := hd argv;
		if(s != nil && s[0] != '-')
			break;
		for (i := 1; i < len s; i++) case s[i] {
		'l' =>
			lopt++;
			daytime = load Daytime Daytime->PATH;
			if(daytime == nil)
				badmodule(Daytime->PATH);
			now = daytime->now();
		'p' =>
			popt++;
		'q' =>
			qopt++;
		'd' =>
			dopt++;
		'e' =>
			eopt++;
		'n' =>
			nopt++;
		't' =>
			topt++;
		'u' =>
			uopt++;
		's' =>
			sortby = Readdir->SIZE;
		'c' =>
			compact = Readdir->COMPACT;
		'r' =>
			rev = Readdir->DESCENDING;
		* =>
			sys->fprint(stderr, "usage: ls [-delpqrstuc] [files]\n");
			sys->raise("fail:usage");
		}
		argv = tl argv;
	}
	if(nopt == 0) {
		if(topt){
			if(uopt)
				sortby = Readdir->ATIME;
			else
				sortby = Readdir->MTIME;
		}
	} else
		sortby = Readdir->NONE;
	sortby |= rev|compact;

	if(argv == nil) {
		argv = list of {"."};
		popt++;
	}

	for(; argv != nil; argv = tl argv)
		ls(hd argv);
	delayWrite();
	out.flush();
}

ls(file: string)
{
	dir: Dir;
 	ok: int;

	(ok, dir) = sys->stat(file);
	if(ok == -1) {
		sys->fprint(stderr, "ls: stat %s: %r\n", file);
		return;
	}
	if(dopt || (dir.mode & sys->CHDIR) == 0) {
		# delay write: save it in the queue to sort by sortby
		if(dwIndex == 0) 
			dwQueue = array[30] of Dir;
		else if(len dwQueue == dwIndex) {
			# expand dwQueue
			tmp := array[2 * dwIndex] of Dir;
			tmp[0:] = dwQueue;
			dwQueue = tmp;
		}
		(dirname, nil) := str->splitstrr(file, "/");
		if(dirname != "") {
			dir.name = dirname + dir.name;
			dir.dev |= PREFIX;
		}
		dwQueue[dwIndex++] = dir; 
		return;
	}

	delayWrite();

	(d, n) := readdir->init(file, sortby);
	if( n < 0)
		sys->fprint(stderr, "ls: Readdir: %s: %r\n", file);
	else
		lsprint(file, d[0:n]);
}

delayWrite() 
{
	if(dwIndex == 0)
		return;
	
	a := array[dwIndex] of ref Dir;
	for (i := 0; i < dwIndex; i++)
		a[i] = ref dwQueue[i];
	(b, n) := readdir->sortdir(a, sortby);

	lsprint("", b[0:n]);
	
	# reset dwIndex
	dwIndex = 0;
	dwQueue = nil;
}

Widths: adt {
	vers, dev, uid, gid, length: int;
};

dowidths(dir: array of ref Dir): ref Widths
{
	w := Widths(0, 0, 0, 0, 0);
	for (i := 0; i < len dir; i++) {
		d := dir[i];
		if(qopt)
			if((n := len string d.qid.vers) > w.vers)
				w.vers = n;
		if(lopt) {
			n: int;
			if((n = len string (d.dev & ~PREFIX)) > w.dev)
				w.dev = n;
			if((n = len d.uid) > w.uid)
				w.uid = n;
			if((n = len d.gid) > w.gid)
				w.gid = n;
			if((n = len string d.length) > w.length)
				w.length = n;
		}
	}
	return ref w;
}


lsprint(dirname: string, dir: array of ref Dir)
{
	w := dowidths(dir);

	for (i := 0; i < len dir; i++)
		lslineprint(dirname, dir[i].name, dir[i], w);
}

lslineprint(dirname, name: string, dir: ref Dir, w: ref Widths)
{
	if(qopt)
		out.puts(sys->sprint("%.8ux.%.*ud ", dir.qid.path, w.vers, dir.qid.vers));

	file := name;
	pf := dir.dev & PREFIX;
	dir.dev &= ~PREFIX;
	if(popt) {
		if(pf)
			(nil, file) = str->splitstrr(dir.name, "/");
		else
			file = dir.name;
	} else if(dirname != "") {
		if(dirname[len dirname-1] == '/')
			file = dirname + file;
		else
			file = dirname + "/" + file;
	}


	if(lopt) {
		time := dir.mtime;
		if(uopt)
			time = dir.atime;
		if(eopt)
			out.puts(sys->sprint("%s %c %*d %*s %*s %*ud %d %s\n",
				modes(dir.mode), dir.dtype, w.dev, dir.dev,
				w.uid, dir.uid, w.gid, dir.gid, w.length, dir.length,
				time, file));
		else
			out.puts(sys->sprint("%s %c %*d %*s %*s %*ud %s %s\n",
				modes(dir.mode), dir.dtype, w.dev, dir.dev,
				w.uid, dir.uid, w.gid, dir.gid, w.length, dir.length,
				daytime->filet(now, time), file));
	} else
		out.puts(file+"\n");
}

mtab := array[] of {
	"---",	"--x",	"-w-",	"-wx",
	"r--",	"r-x",	"rw-",	"rwx"
};

modes(mode: int): string
{
	s: string;

	if(mode & Sys->CHDIR)
		s = "d";
	else
		s = "-";
	s += mtab[(mode>>6)&7]+mtab[(mode>>3)&7]+mtab[mode&7];
	return s;
}

