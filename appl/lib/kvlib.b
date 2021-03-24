implement KVlib;

# This module contains the interface to any db in the
# simple format of services/cs/db. It is used by modules like
# getauthinfo so that the prompt has the value of $SIGNER.

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";
include "bufio.m";

include "kvlib.m";

#
# Maps key strings to value strings from file
#

KVpair: adt {
	key:	string;
	value:	string;
};
kvlist: list of KVpair;

lastdb: string;
dbcdir: ref Sys->Dir;	# state of file when it last was read

kvopen(path: string) : int
{
	lastdb = path;
	if (sys == nil) {
		sys = load Sys Sys->PATH;
		stderr = sys->fildes(2);
	}

	l: list of KVpair;
	readp := 0;

	(n, dir) := sys->stat(path);
	if (n < 0) {
		sys->fprint(stderr, "kvlib: kvopen: can't stat %s %r\n", path);
		kvlist = nil;
		return -1;
	}
	if(dbcdir != nil && samefile(*dbcdir, dir))
		return 0;
	(n, l) = readkvlist(path);
	dbcdir = ref dir;
	if(n < 0)
		return -1;	# seems better to keep existing list on error
	kvlist = l;
	return 0;
}

samefile(d1, d2: Sys->Dir): int
{
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime==d2.mtime;
}

kvmap(key: string): string
{
	if (lastdb != nil) {
		if (kvopen(lastdb) >= 0)
			return kvlistmap(key, kvlist);
	}    
	sys->fprint(stderr, "kvlib: kvmap: cannot map key %s from unopened file\n", key);
	return nil;
}

kvlistmap(key: string, l: list of KVpair): string
{
	for(; l != nil; l = tl l)
		if((hd l).key == key)
			return (hd l).value;
	return nil;
}

readkvlist(path: string): (int, list of KVpair)
{
	bufio := load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "kvlib: can't load Bufio: %r\n");
		return (-1, nil);
	}
	fd := bufio->open(path, Bufio->OREAD);
	if (fd == nil) {
		sys->fprint(stderr, "kvlib: can't open %s: %r\n", path);
		return (-1, nil);
	}
	env: list of KVpair;
	cnt := 0;
	err := 0;
	for(line := 1; (t := bufio->fd.gets('\n')) != nil; line++) {
		if(t[0] == '#')
			continue;
		(n, el) := sys->tokenize(t, " \t\r\n");
		if (n == 0)
			continue;	# blank line
		if (n != 2) {
			sys->fprint(stderr, "kvlib: %s:%d record with %d fields\n", path, line, n);
			err = 1;
		}
		env = KVpair(hd el, hd tl el) :: env;
		cnt++;
	}
	if(err && env == nil)
		return (-1, nil);	# no valid translations
	return (cnt, env);
}
