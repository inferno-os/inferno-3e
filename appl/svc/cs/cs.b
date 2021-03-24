implement Cs;

#
#	Module:		CS
#	Purpose:	Connection Server
#	Author:		Eric Van Hensbergen (ericvh@lucent.com)
#	History:	Based on original CS from 1127 Research Tree
#

include "sys.m";
	sys: Sys;
	FileIO: import Sys;
include "draw.m";
include "cs.m";
include "bufio.m";
include "string.m";
include "regex.m";
	regex:	Regex;
include "daytime.m";
	daytime: Daytime;

Cs: module
{
	init:	fn(ctxt: ref Draw->Context, nil: list of string);
};

CONFIG_PATH:	con "/services/cs/config";

stderr: ref Sys->FD;
verbose := 0;

Reply: adt
{
	fid:	int;
	pid:	int;
	reqc:	chan of (int, int, Sys->Rread);
};

rlist: list of ref Reply;

Plugin: adt
{
	mod:	CSplugin;	# module to implement the plug-in
	demand:	int;	# dials ppp or other connection on demand
	exp:	regex->Re;	# regular expression which selects the module
};

plugins:	list of Plugin;

Cached: adt
{
	expire:	int;
	query:	string;
	addrs:	list of string;
};

Ncache: con 16;
cache:= array[Ncache] of ref Cached;
nextcache := 0;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if((regex = load Regex Regex->PATH) == nil) {
		sys->fprint(stderr, "cs: can't load %s: %r\n", Regex->PATH);
		sys->raise("fail: couldn't load regex module");
	}
	if((daytime = load Daytime Daytime->PATH) == nil){
		sys->fprint(stderr, "cs: can't load %s: %r\n", Daytime->PATH);
		sys->raise("fail:Daytime");
	}

	force := 0;

	if (argv !=nil)
		argv = tl argv;
	while(argv != nil) {
		s := hd argv;
		if(s[0] != '-')
			break;
		for(i := 1; i < len s; i++) case s[i] {
		'f' =>
			force = 1;
		'v' =>
			verbose = 1;
		* =>
			sys->fprint(stderr, "usage: svc/cs/cs [-f]\n");
			return;
		}
		argv = tl argv;
	}

	if(!force){
		(ok, nil) := sys->stat("/net/cs");
		if(ok >= 0) {
			sys->raise("fail: cs already started");
			return;
		}
	}

	sys->bind("#s", "/net", Sys->MBEFORE );
	file := sys->file2chan("/net", "cs");
	if(file == nil) {
		sys->raise("fail: failed to make file: /net/cs");
		return;
	}
	
	config(ctxt);

	spawn cs(file);
}

config(context: ref Draw->Context)
{
	lines:	list of string;

	# load bufio
	bufio := load Bufio Bufio->PATH;
	str := load String String->PATH;

	if (bufio == nil) {
		sys->raise("fail:Couldn't load BufIO module");
		exit;
	}
	if (str == nil) {
		sys->raise("fail:Couldn't load String module");
		exit;
	}

	Iobuf: import bufio;
	# open the config file
	f := bufio->open(CONFIG_PATH,Sys->OREAD);

	if(f == nil) {
		sys->raise("fail:Couldn't load config file");
		exit;
	}

	# read config file line by line and place into list;
	while((l := f.gett("\r\n")) != nil) {
		if ((l == "\r") || (l == "\n") || (l[0] == '#'))
			continue;
		if ((l[(len l)-1] == '\r')||(l[(len l)-1] == '\n'))
			l = l[:(len l)-1];
		lines = l::lines;
	}
	
	# parse lines and process regular expressions
	while (lines != nil) {
		newplugin: Plugin;
		(modpath, modex) := str->splitl(hd lines, " ");
		lines = tl lines;
		if (modex == nil) continue;
		modex = modex[1:];
		newplugin.demand = modpath == "/dis/svc/cs/ispservice.dis";
		newplugin.mod = load CSplugin modpath;
		if (newplugin.mod == nil) {
			sys->fprint(stderr, "cs: couldn't load plugin %s: %r\n",modpath);
			continue;
		}
		newplugin.mod->init(context, nil);
		(re, err) := regex->compile(modex, 1);
		if(re == nil){
			sys->fprint(stderr, "cs: regular expression `%s': %s\n", modex, err);
			continue;
		}
		newplugin.exp = re;
		plugins = newplugin::plugins;
	}
}

cs(file: ref Sys->FileIO)
{
	pidc := chan of int;
	donec := chan of (ref Reply, chan of int);
	for (;;) {
		alt {
			(nil, buf, fid, wc) := <-file.write =>
				cleanfid(fid);	# each write cancels previous requests
				if(wc != nil){
					now := daytime->now();
					r := ref Reply;
					r.fid = fid;
					r.reqc = chan of (int, int, Sys->Rread);
					spawn request(r, buf, now, wc, pidc, donec);
					<-pidc;
					rlist = r :: rlist;
				}

			(off, nbytes, fid, rc) := <-file.read =>
				if(rc != nil){
					r := findfid(fid);
					if(r != nil)
						r.reqc <-= (off, nbytes, rc);
					else
						rreply(rc, (nil, "unknown request"));
				}else
					;	# cleanfid(fid);		# compensate for csendq in file2chan

			(r, exitc) := <-donec =>
				r.pid = 0;
				cleanfid(r.fid);
				exitc <-= 1;
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

request(r: ref Reply, data: array of byte, now: int, wc: chan of (int, string), pidc: chan of int, donec: chan of (ref Reply, chan of int))
{
	r.pid = sys->pctl(Sys->NEWPGRP, nil);
	pidc <-= r.pid;
	query := string data;
	(addrs, err) := xlate(query, now);
	if(addrs == nil && err == nil)
		err = "cs: can't translate address";
	if(err != nil){
		if(verbose)
			sys->fprint(stderr, "cs: %s: %s\n", string data, err);
		wreply(wc, (0, err));
		# older clients might expect error on read: wait for it
	} else
		wreply(wc, (len data, nil));
	exitc := chan of int;
	for(;;){
		alt{
		(off, nbytes, rc) := <-r.reqc =>
			addr: string = nil;
			if(addrs != nil){
				addr = hd addrs;
				addrs = tl addrs;
			}
			off = 0;	# TO DO: investigate claimed bug in file2chan offsets
			if(err == nil)
				rreply(rc, reads(addr, off, nbytes));
			else
				rreply(rc, (nil, err));
			if(addr == nil)
				donec <-= (r, exitc);
		<-exitc =>
			exit;
		}
	}
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
			if(0)
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

xlate1(cpi: Plugin, addr: string): (list of string, string)
{
	e := ref Sys->Exception;
	if (sys->rescue("fail:*", e) == Sys->HANDLER) {
		resp := cpi.mod->xlate(addr);
		return (resp, nil);
	} else {
		err := e.name[5:];
		while(len err > 0 && err[0] == ' ')
			err = err[1:];
		sys->rescued(Sys->ACTIVE, nil);
		return (nil, err);
	}			
}

xlate(address: string, now: int): (list of string, string)
{
	cpi: Plugin;
	cca: string;
	resp: list of string;
	newresp: list of string;
	err: string;

	while(len address > 1 && address[len address-1] == '\n')
		address = address[0:len address-1];
	if(address == nil)
		return (nil, "bad format request");

	ce := lookcache(address, now);
	if(ce != nil && ce.addrs != nil){
		# must still force ppp dial if we aren't online currently
		for(pi := plugins; pi != nil; pi = tl pi){
			cpi = hd pi;
			if(cpi.demand){
				xlate1(cpi, address);
				break;
			}
		}
		return (ce.addrs, nil);
	}

	resp = address :: nil;

	# for all configured plug-ins
	for (pi := plugins; pi != nil; pi = tl pi) {
		cpi = hd pi;
		# for all current addresses
		
		resp = reverselos(resp);
		for (ca := resp; ca != nil; ca = tl ca) {
			cca = hd ca;
			# if ca matches the expression
			if  (regex->execute(cpi.exp, cca) != nil) {
				(newaddrs, newerr) := xlate1(cpi, cca);
				# prepend results in reverse order
				for (a := newaddrs; len a; a = tl a)
					newresp = (hd a) :: newresp;
				if (newerr != nil)
					err = newerr;
			} else 
				newresp = cca :: newresp;
		}
		resp = newresp;
		newresp = nil;
	}

	# for all current addresses
	for (foo := resp; foo != nil; foo = tl foo) {
		(n, l) := sys->tokenize(hd foo, "!\n");
		case (n) {
			2 => 
				newresp = ("/net/"+(hd l)+"/clone "+hd (tl l))::newresp;
				break;
			3 => 
				newresp = ("/net/"+(hd l)+"/clone "+hd (tl l)+"!"+hd (tl tl l))::newresp;
				break;
			* =>
				sys->fprint(stderr,"cs: malformed address (%s) returned from translation - ignored\n", hd foo);
				continue;
		}
		
	}
	putcache(address, newresp, now);
	return (newresp, err);
}

reverselos(l: list of string) : list of string
{
	t : list of string;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}
