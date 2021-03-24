implement Cs;

#
# Connection server translates net!machine!service into
# /net/tcp/clone 135.104.9.53!564
#
# This is a server implementation for tcp/udp
#

include "sys.m";
	sys:	Sys;
include "draw.m";
include "srv.m";
include "ipsrv.m";
	srv: Ipsrv;
include "kvlib.m";
	kv: KVlib;
include "daytime.m";
	daytime: Daytime;


Cs: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Reply: adt
{
	fid:	int;
	pid:	int;
	addrs:	list of string;
	err:	string;
};

Cached: adt
{
	expire:	int;
	query:	string;
	addrs:	list of string;
};

Ncache: con 16;
cache:= array[Ncache] of ref Cached;
nextcache := 0;

rlist: list of ref Reply;
rlen, max: int = 0;

srvfile: con "/services/cs/db";

stderr: ref Sys->FD;

usage()
{
	sys->print("Usage: cs [-q n] [-v] [-r] [ipsrv options]\n");
	exit;
}

verbose := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	kv = load KVlib KVlib->PATH;
	if (kv == nil){
		sys->fprint(stderr, "cs: can't load KVlib: %r\n");
		sys->raise("fail:kvlib");
	}
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil){
		sys->fprint(stderr, "cs: can't load Daytime: %r\n");
		sys->raise("fail:daytime");
	}

	if(args != nil)
		args = tl args;

	restart := 0;
	opts: list of string;
	for (; args != nil && (hd args)[0] != '/'; args = tl args){
		case hd args {
		"-q" or "-t" =>
			if (tl args != nil) {
				key := hd args;
				args = tl args;
				if ('0' <= (hd args)[0] && (hd args)[0] <= '9') {
					val := int hd args;
					case key {
					"-q" => max = val;
					"-t" =>;	# obsolete
					}
				} else
					usage();
			}
		"-v" or "-d" => verbose++;
		"-r" or "-f" => restart = 1;
		* => opts = hd args :: opts;
		}
	}
	if(args != nil)
		usage();

	(ok, nil) := sys->stat("/net/cs");
	if(ok >= 0) {
		if (restart)
			sys->print("cs: restarting service\n");
		else {
			# sys->fprint(stderr, "cs: already started\n");
			return;
		}
	}

	if((srv = load Ipsrv Ipsrv->PATH) == nil) {
		sys->fprint(stderr, "cs: failed to load %s %r\n", Ipsrv->PATH);
		return;
	} else
		srv->init(Ipsrv->PATH :: reverse(opts));	# TO DO: is this really necessary?
	sys->bind("#s", "/net", Sys->MBEFORE);
	file := sys->file2chan("/net", "cs");
	if(file == nil) {
		sys->fprint(stderr, "cs: failed to make /net/cs: %r\n");
		return;
	}
	if(kv != nil)
		kv->kvopen(srvfile);
	spawn cs(file);
}

cs(file: ref Sys->FileIO)
{
	pidc := chan of int;
	donec := chan of ref Reply;
	for (;;) {
		alt {
			(nil, buf, fid, wc) := <-file.write =>
				cleanfid(fid);	# each write cancels previous requests
				if(wc != nil){
					now := daytime->now();
					r := ref Reply;
					r.fid = fid;
					spawn request(r, buf, now, wc, pidc, donec);
					r.pid = <-pidc;
					rlist = r :: rlist;
				}

			(off, nbytes, fid, rc) := <-file.read =>
				if(rc != nil){
					r := findfid(fid);
					if(r != nil)
						reply(r, off, nbytes, rc);
					else
						rreply(rc, (nil, "unknown request"));
				} else
					;	# cleanfid(fid);		# compensate for csendq in file2chan

			r := <-donec =>
				r.pid = 0;
		}
	}
}

rreply(rc: chan of (array of byte, string), reply: (array of byte, string))
{
	alt {
	rc <-= reply =>;
	* =>;
	}
}

wreply(wc: chan of (int, string), reply: (int, string))
{
	alt {
	wc <-= reply=>;
	* =>;
	}
}

findfid(fid: int): ref Reply
{
	for(rl := rlist; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid == fid)
			return r;
	}
	return nil;
}

cleanfid(fid: int)
{
	rl := rlist;
	rlist = nil;
	for(; rl != nil; rl = tl rl){
		r := hd rl;
		if(r.fid != fid)
			rlist = r :: rlist;
		else
			killgrp(r.pid);
	}
}

killgrp(pid: int)
{
	if(pid != 0){
		fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
		if(fd == nil || sys->fprint(fd, "killgrp") < 0)
			sys->fprint(stderr, "cs: can't killgrp %d: %r\n", pid);
	}
}

request(r: ref Reply, data: array of byte, now: int, wc: chan of (int, string), pidc: chan of int, donec: chan of ref Reply)
{
	pidc <-= sys->pctl(Sys->NEWPGRP, nil);
	query := string data;
	(r.addrs, r.err) = xlate(query, now);
	if(r.addrs == nil && r.err == nil)
		r.err = "cs: can't translate address";
	if(r.err != nil){
		if(verbose)
			sys->fprint(stderr, "cs: %s: %s\n", query, r.err);
		wreply(wc, (0, r.err));
		# older clients might expect error on read: wait for it
	} else
		wreply(wc, (len data, nil));
	donec <-= r;
}

reply(r: ref Reply, off: int, nbytes: int, rc: chan of (array of byte, string))
{
	if(r.err != nil){
		rreply(rc, (nil, r.err));
		return;
	}
	addr: string = nil;
	if(r.addrs != nil){
		addr = hd r.addrs;
		r.addrs = tl r.addrs;
	}
	off = 0;	# TO DO: investigate claimed bug in file2chan offsets
	rreply(rc, reads(addr, off, nbytes));
}

#
# return the file2chan reply for a read of the given string
#
reads(str: string, off, nbytes: int): (array of byte, string)
{
	bstr := array of byte str;
	slen := len bstr;
	if(off < 0 || off >= slen)
		return (nil, nil);
	if(off + nbytes > slen)
		nbytes = slen - off;
	if(nbytes <= 0)
		return (nil, nil);
	return (bstr[off:off+nbytes], nil);
}

lookcache(query: string, now: int): ref Cached
{
	for(i:=0; i<len cache; i++){
		c := cache[i];
		if(c != nil && c.query == query && now < c.expire){
			if(verbose)
				sys->print("cache: %s -> %s\n", query, hd c.addrs);
			return c;
		}
	}
	return nil;
}

putcache(query: string, addrs: list of string, now: int)
{
	ce := ref Cached;
	ce.expire = now+120;
	ce.query = query;
	ce.addrs = addrs;
	cache[nextcache] = ce;
	nextcache = (nextcache+1)%Ncache;
}

xlate(address: string, now: int): (list of string, string)
{
	n: int;
	l, rl: list of string;
	repl, netw, mach, service, s: string;

	ce := lookcache(address, now);
	if(ce != nil && ce.addrs != nil)
		return (ce.addrs, nil);

	(n, l) = sys->tokenize(address, "!\n");
	if(n < 2)
		return (nil, "bad format request");

	netw = hd l;
	if(netw == "net")
		netw = "tcp";	# TO DO: better (needs lib/ndb)
	if(!isnetwork(netw))
		return (nil, "network unavailable "+netw);
	l = tl l;

	if(!isipnet(netw)) {
		repl = "/net/" + netw + "/clone ";
		for(;;){
			repl += hd l;
			if((l = tl l) == nil)
				break;
			repl += "!";
		}
		return (repl :: nil, nil);	# no need to cache
	}

	if(n != 3)
		return (nil, "bad format request");
	mach = hd l;
	service = hd tl l;

	if(isnumeric(service) == 0) {
		service = srv->ipn2p(netw, service);
		if(service == nil)
			return (nil, "bad service name");
	}

	if(mach == "*")
		l = "" :: nil;
	else
	if(isipaddr(mach) == 0) {
		# Symbolic server == "$SVC"
		if(mach[0] == '$' && kv != nil
		   && (mach = kv->kvmap(mach)) == nil)
			return (nil, "unknown service");
		l = srv->iph2a(mach);
		if(l == nil)
			return (nil, "unknown host");
	}
	else
		l = mach :: nil;

	while(l != nil) {
		s = hd l;
		l = tl l;
		if(s != "")
			s[len s] = '!';
		s += service;

		repl = "/net/" + netw + "/clone " + s;
		if (verbose)
			sys->fprint(stderr, "cs: %s!%s!%s -> %s\n", netw, mach, service, repl);

		rl = repl :: rl;
	}
	rl = reverse(rl);
	putcache(address, rl, now);
	return (rl, nil);
}

reverse(l: list of string) : list of string
{
	t : list of string;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

isipaddr(a: string): int	# wrong for ipv6
{
	i, c: int;

	for(i = 0; i < len a; i++) {
		c = a[i];
		if((c < '0' || c > '9') && c != '.')
			return 0;
	}
	return 1;
}

isnumeric(a: string): int
{
	i, c: int;

	for(i = 0; i < len a; i++) {
		c = a[i];
		if(c < '0' || c > '9')
			return 0;
	}
	return 1;
}

nets: list of string;

isnetwork(s: string) : int
{
	if(find(s, nets))
		return 1;
	(ok, nil) := sys->stat("/net/"+s+"/clone");
	if(ok >= 0) {
		nets = s :: nets;
		return 1;
	}
	return 0;
}

find(e: string, l: list of string) : int
{
	for(; l != nil; l = tl l)
		if (e == hd l)
			return 1;
	return 0;
}

isipnet(s: string) : int
{
	return s == "net" || s == "tcp" || s == "udp" || s == "il";
}

include "bufio.m";

getval(key, path : string) : string
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return nil;
	bufio := load Bufio Bufio->PATH;
	if(bufio == nil) {
		sys->fprint(stderr, "cs: can't load Bufio: %r\n");
		return nil;
	}
	sf := bufio->fopen(fd, Bufio->OREAD);
	while((t := bufio->sf.gets('\n')) != nil) {
		if(t[0] == '#')
			continue;
		(nil, el) := sys->tokenize(t, " \t\r\n");
		if(el != nil && hd el == key)
			if (tl el != nil)
				return hd tl el;
	}
	return nil;
}

sysname() : string
{
	buf := array[64] of byte;
	fd := sys->open("/dev/sysname", sys->OREAD);
	n := sys->read(fd, buf, len buf);
	if (n <= 0) {
		sys->fprint(stderr, "cs: read /dev/sysname %r\n");
		return "*";
	}
	return string buf[0:n];
}
