# ns - display the construction of the current namespace (loosely based on plan 9's ns)
implement Ns;

include "sys.m";
include "draw.m";
include "string.m";

Ns: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

SHELLMETA: con " \t\\$#";

init(nil: ref Draw->Context, argv: list of string)
{

	pid: int;

	sys := load Sys Sys->PATH;
	str := load String String->PATH;

	if (len argv < 2) {
		pid = sys->pctl(0, nil);
	} else {
		arg := hd tl argv;
		if (arg[0] == '-'){
			sys->fprint(sys->fildes(2), "usage: ns [pid]\n");
			return;
		}

		(pid, nil) = str->toint(arg, 10);
	}

	nsname := sys->sprint("#p/%d/ns", pid);
	nsfd := sys->open(nsname, Sys->OREAD);
	if (nsfd == nil) {
		sys->fprint(sys->fildes(2), "ns: can't open %s: %r\n", nsname);
		return;
	}

	buf := array[256] of byte;
	while((l := sys->read(nsfd, buf, len buf)) > 0){
		(nstr, lstr) := sys->tokenize(string buf[0:l], " \n");
		if(lstr != nil && hd lstr == "cd"){
			sys->write(sys->fildes(1), buf, l);
			continue;
		}
		if(nstr == 4)	# spec at the front
			lstr = tl lstr;
		(flags, nil) := str->toint(hd lstr, 10);

		sflag := "";
		if (flags & Sys->MBEFORE)
			sflag += "b";
		if (flags & Sys->MAFTER)
			sflag += "a";
		if (flags & Sys->MCREATE)
			sflag += "c";
		if (sflag != "")
			sflag = "-" + sflag + " ";

		# quote arguments if "#" found
		src := hd tl tl lstr;
		if (len src >= 3 && (src[0:2] == "#/" || src[0:2] == "#U")) # remove unnecesary #/'s and #U's
			src = src[2:];

		# is it a mount or a bind?
		cmd := "bind";
		if (len src >= 3 && src[2] == 'M')
			cmd = "mount";

		# remove "#." from beginning of destination path
		dest := hd tl lstr;
		if(dest == "#M") {
			dest = dest[2:];
			if (dest == "")
				dest = "/";
		}

		sys->print("%s %s%s %s\n", cmd, sflag, quoted(src), quoted(dest));
	} 
	if(l < 0)
		sys->fprint(sys->fildes(2), "ns: error reading %s: %r\n", nsname);
}

any(c: int, t: string): int
{
	for(j := 0; j < len t; j++)
		if(c == t[j])
			return 1;
	return 0;
}

contains(s: string, t: string): int
{
	for(i := 0; i<len s; i++)
		if(any(s[i], t))
			return 1;
	return 0;
}

quoted(s: string): string
{
	if(!contains(s, SHELLMETA))
		return s;
	r := "'";
	for(i := 0; i < len s; i++){
		if(s[i] == '\'')
			r[len r] = '\'';
		r[len r] = s[i];
	}
	r[len r] = '\'';
	return r;
}
