implement Man;

include "sys.m";
include "draw.m";
include "filepat.m";
include "bufio.m";

Command : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

# include "man.m";
# The Man module implementation extends the standard
# Man module interface to look like a Command module as well.
#
# NOTE: should consider extending limbo syntax so as we can
#	do this sort of thing in a consistent way

Man : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);

	# Man module declarations
	#
	loadsections : fn (sections : list of string) : string;
	getfiles : fn (sections : list of string, keys : list of string) : list of (int, string, string);
};

MANPATH : con "/man/";
PATHDEPTH : con 1;

indices : list of (string, list of (string, string));

init(nil : ref Draw->Context, argv : list of string)
{
	sys := load Sys Sys->PATH;
	man2txt := load Command "/dis/man2txt.dis";
	if (man2txt == nil) {
		sys->print("failed to load man2txt command: %r\n");
		sys->raise("fail:bad module");
	}

	argv = tl argv;
	sections : list of string;
	fflag := 0;
	for (; argv != nil; argv = tl argv) {
		arg := hd argv;
		if (arg == nil)
			continue;
		if (arg == "-f") {
			argv = tl argv;
			if (argv == nil || sections != nil) {
				sys->print("Usage: man -f file...\n");
				sys->raise("fail:args");
			}
			fflag = 1;
			break;
		}
		
		if (!isint(arg))
			break;
		sections = arg :: sections;
	}
	if (argv == nil) {
		sys->print("Usage: man [-f] [0-9] ... name ...\n");
		sys->raise("fail:args");
	}

	paths := argv;
	if (!fflag) {
		err := loadsections(sections);
		if (err != nil) {
			sys->print("%s\n", err);
			sys->raise("fail:error");
		}
		files := getfiles(sections, argv);
		paths = nil;
		for (; files != nil; files = tl files) {
			(nil, nil, path) := hd files;
			paths = path :: paths;
		}
		paths = sortuniq(paths);
	}
	man2txt->init(nil, "man2txt" :: paths);
}

loadsections(scanlist : list of string) : string
{
	sys := load Sys Sys->PATH;
	bufio := load Bufio Bufio->PATH;
	Iobuf : import bufio;

	if (bufio == nil)
		return sys->sprint("failed to load %s module: %r", Bufio->PATH);

	indexpaths : list of string;
	if (scanlist == nil) {
		filepat := load Filepat Filepat->PATH;
		if (filepat == nil)
			return sys->sprint("failed to load %s module: %r", Filepat->PATH);

		indexpaths = filepat->expand(MANPATH + "[0-9]*/INDEX");
		if (indexpaths == nil)
			return sys->sprint("cannot find man pages");
	} else {
		for (; scanlist != nil; scanlist = tl scanlist)
			indexpaths = MANPATH + string hd scanlist + "/INDEX" :: indexpaths;
		indexpaths = sortuniq(indexpaths);
	}

	sections : list of string;
	for (; indexpaths != nil; indexpaths = tl indexpaths) {
		path := hd indexpaths;
		(n, toks) := sys->tokenize(path, "/");
		for (d := 0; d < PATHDEPTH; d++)
			toks = tl toks;
		sections = hd toks :: sections;
	}

	for (sl := sections; sl != nil; sl = tl sl) {
		section := hd sl;
		path := MANPATH + string section + "/INDEX";
		iob := bufio->open(path, Sys->OREAD);
		if (iob == nil)
			continue;
		pairs : list of (string, string) = nil;
		
		while((s := iob.gets('\n')) != nil) {
			if (s[len s - 1] == '\n')
				s = s[0:len s - 1];
			(n, toks) := sys->tokenize(s, " ");
			if (n != 2)
				continue;
			pairs = (hd toks, hd tl toks) :: pairs;
		}
		iob.close();
		indices = (section, pairs) :: indices;
	}
	return nil;
}

getfiles(sections : list of string, keys : list of string) : list of (int, string, string)
{
	ixl : list of (string, list of (string, string));

	if (sections == nil)
		ixl = indices;
	else {
		for (; sections != nil; sections = tl sections) {
			section := hd sections;
			for (il := indices; il != nil; il = tl il) {
				(s, mapl) := hd il;
				if (s == section) {
					ixl = (s, mapl) :: ixl;
					break;
				}
			}
		}
	}
	paths : list of (int, string, string);
	for (; ixl != nil; ixl = tl ixl) {
		for ((s, mapl) := hd ixl; mapl != nil; mapl = tl mapl) {
			(kw, file) := hd mapl;
			for (keyl := keys; keyl != nil; keyl = tl keyl) {
				if (hd keyl == kw) {
					p := MANPATH + string s + "/" + file;
					paths = (int s, kw, p) :: paths;
					break;
				}
			}
		}
	}
	return paths;
}

sortuniq(strlist : list of string) : list of string
{
	strs := array [len strlist] of string;
	for (i := 0; strlist != nil; (i, strlist) = (i+1, tl strlist))
		strs[i] = hd strlist;

	# simple sort (greatest first)
	for (i = 0; i < len strs - 1; i++) {
		for (j := i+1; j < len strs; j++)
			if (strs[i] < strs[j])
				(strs[i], strs[j]) = (strs[j], strs[i]);
	}

	# construct list (result is ascending)
	r : list of string;
	prev := "";
	for (i = 0; i < len strs; i++) {
		if (strs[i] != prev) {
			r = strs[i] :: r;
			prev = strs[i];
		}
	}
	return r;
}

isint(s : string) : int
{
	for (i := 0; i < len s; i++)
		if (s[i] < '0' || s[i] > '9')
			return 0;
	return 1;
}
