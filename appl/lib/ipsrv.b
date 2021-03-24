implement Ipsrv;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

include "bufio.m";

include "srv.m";
	srv: Srv;

include "ipsrv.m";

srvfile := "/services/cs/services";
dnsfile := "/services/dns/db";
Iterations: con 10;

servers: list of string;

# domain name from dns/db
domain: string;

#
# TO DO:
#	might need an interlock when building the search lists?
#	fix: the local copy of dial
#	DNS client code might be separate?
#	ipv6
#

init(args: list of string)
{
	if(sys == nil) {
		sys = load Sys Sys->PATH;
		stderr = sys->fildes(2);
		srv = load Srv Srv->PATH;
	}
	if (args != nil)
		args = tl args;
	for(; args != nil; args = tl args) {
		key := hd args;
		if(key == "-n"){
			srv = nil;	# test native environment without $Srv
			continue;
		}
		if(tl args == nil) {
			sys->fprint(stderr, "ipsrv: missing arg for %s\n", key);
			break;
		}
		args = tl args;
		val := hd args;
		case key {
		"-s" => srvfile = val;
		"-d" => dnsfile = val;
		* =>		;		# just ignore them
		}
	}
	srvupdate();
	readservers(dnsfile);
}

samefile(d1, d2: Sys->Dir): int
{
	# ``it was black ... it was white!  it was dark ...  it was light! ah yes, i remember it well...''
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime==d2.mtime;
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

#
# read an IP service map in the format of a unix /etc/services file,
# rereading the file if it has changed
#

Serv: adt {
	port: string;
	net: string;
	names: array of string;
};
srvlist: list of Serv;

srvdir: ref Sys->Dir;	# description when last read

srvupdate(): int
{
	if(sys == nil){	# currently can't assume that init called by all existing apps
		sys = load Sys Sys->PATH;
		stderr = sys->fildes(2);
	}
	(n, dir) := sys->stat(srvfile);
	if(n < 0) {
		sys->fprint(stderr, "srv: cannot stat %s: %r\n", srvfile);
		return 0;
	}
	if(srvdir != nil && samefile(*srvdir, dir))
		return 0;
	srvdir = ref dir;
	bufio := load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->fprint(stderr, "srv: can't load Bufio: %r\n");
		return 0;
	}

	sf := bufio->open(srvfile, Bufio->OREAD);
	if (sf == nil) {
		sys->fprint(stderr, "srv: can't open %s: %r\n", srvfile);
		return 0;
	}

	nsrvlist: list of Serv;
	serv: Serv;
	err := 0;

	for(line := 1; (s := bufio->sf.gets('\n')) != nil; line++) {
		for(n = 0; n < len s; n++)
			if(s[n] == '#'){
				s = s[0:n];
				break;
			}
		(nf, slist) := sys->tokenize(s, " \t\r\n");
		if (nf == 0)	# blank line
			continue;
		if(nf < 2){
			sys->fprint(stderr, "ipsrv: %s:%d: bad format (need `service-name port/protocol')\n", srvfile, line);
			err = 1;
			continue;
		}
		(nil, map) := sys->tokenize(hd tl slist, "/");	# eg, 53/tcp
		if(len map != 2) {
			sys->fprint(stderr, "ipsrv: %s:%d: invalid port/protocol entry\n", srvfile, line);
			err = 1;
			continue;
		}
		serv.port = hd map;
		serv.net = hd tl map;
		slist = hd slist :: tl tl slist;
		serv.names = array[nf-1] of string;
		for(n = 0; slist != nil; slist = tl slist)
			serv.names[n++] = hd slist;
		nsrvlist = serv :: nsrvlist;
	}
	if(nsrvlist != nil && (!err || srvlist==nil))
		srvlist = nsrvlist;
	return 1;
}

ipn2p(net, service: string): string
{
	if(net == nil || service == nil)
		return nil;

	srvupdate();
	for(l := srvlist; l != nil; l = tl l){
		serv := hd l;
		if(net == serv.net){
			for(n := 0; n < len serv.names; n++)
				if(serv.names[n] == service)
					return serv.port;
		}
	}
	if(srv != nil)
		return srv->ipn2p(net, service);	# try the host's map if available
	return nil;
}

#
# basic Domain Name Service client
#

DNSport: con 53;
UseTCP: con 0;
DEBUG: con 0;

#
# subset of RR types
#
Ta: con 1;
Tns: con 2;
Tcname: con 5;
Tsoa: con 6;
Tptr: con 12;
Tmx: con 15;

#
# classes
#
Cin: con 1;
Call: con 255;

#
# opcodes
#
Oquery: con 0<<11;	# normal query
Oinverse: con 1<<11;	# inverse query
Ostatus:	con 2<<11;	# status request
Omask:	con 16rF<<11;	# mask for opcode

#
# response codes
#
Rok:	con 0;
Rformat:	con 1;	# format error
Rserver:	con 2;	# server failure
Rname:	con 3;	# bad name
Runimplemented: con 4;	# unimplemented operation
Rrefused:	con 5;	# permission denied, not supported
Rmask:	con 16rF;	# mask for response

#
# other flags in opcode
#
Fresp:	con 1<<15;	# message is a response
Fauth:	con 1<<10;	# true if an authoritative response
Ftrunc:	con 1<<9;		# truncated message
Frecurse:	con 1<<8;		# request recursion
Fcanrecurse:	con 1<<7;	# server can recurse

QR: adt {
	qname: string;
	qtype: int;
	qclass: int;
};

RR: adt {
	name: string;
	rtype: int;
	rclass: int;
	ttl: int;
	rdata: array of byte;
	ptr:	string;	# ptr
	host:	string;	# name, and others
};

DNSmsg: adt {
	id: 	int;
	flags:	int;
	qd: list of ref QR;
	an: list of ref RR;
	ns: list of ref RR;
	ar: list of ref RR;
	err: string;
};

rrlen(rrl: list of ref RR): int
{
	l := 0;
	for(; rrl != nil; rrl = tl rrl){
		# if name is formatted correctly, the length of name
		# should be the same as the length of the string + 2
		rr := hd rrl;
		l += (2+len rr.name) + 2+2+4+ (2+len rr.rdata);	# name, type[2], class[2], ttl[4], data
	}
	return l;
}

putword(val: int, aob: array of byte, loc: int): (array of byte, int)
{
	if(loc < 0)
		return (aob, loc);
	if(loc + 2 > len aob)
		return (aob, -loc);
	aob[loc] = byte (val>>8);
	aob[loc+1] = byte val;
	return (aob, loc+2);
}

putlong(val: int, aob: array of byte, loc: int): (array of byte, int)
{
	if(loc < 0)
		return (aob, loc);
	if(loc + 4 > len aob)
		return (aob, -loc);
	aob[loc] = byte (val>>24);
	aob[loc+1] = byte (val>>16);
	aob[loc+2] = byte (val>>8);
	aob[loc+3] = byte val;
	return (aob, loc+4);
}


getword(aob: array of byte, loc: int): (int, int)
{
	if(loc < 0)
		return (0, loc);
	if(loc + 2 > len aob)
		return (0, -loc);
	val := (int aob[loc] << 8) | int aob[loc+1];
	return (val, loc+2);
}

getlong(aob: array of byte, loc: int): (int, int)
{
	if(loc < 0)
		return (0, loc);
	if(loc + 4 > len aob)
		return (0, -loc);
	val := (((((int aob[loc] << 8)| int aob[loc+1]) << 8) | int aob[loc+2]) << 8) | int aob[loc+3];
	return (val, loc+4);
}

putdn(str: string, aob: array of byte, loc: int): (array of byte, int)
{
	if(loc < 0)
		return (aob, loc);
	l := 0;
	while(l < len str) {
		for(c := l; c < len str && str[c] != '.'; c++)
			;
		flen := c - l;
		if(flen < 1 || loc+flen+1 > len aob)
			return (aob, -loc);
		aob[loc++] = byte flen;
		for(; l < c; l++)
			aob[loc++] = byte str[l];
		l++; # skip dot
	}
	if(loc >= len aob)
		return (aob, -loc);
	aob[loc++] = byte 0;
	return (aob, loc);
}

getdn(aob: array of byte, loc: int): (string, int)
{
	if(loc < 0)
		return (nil, loc);
	name := "";
	while(loc < len aob && (l := int aob[loc++]) != 0) {
		if((l & 16rC0) == 16rC0) {		# pointer
			if(loc >= len aob)
				return (name, -loc);
			ploc := ((l & 16r3F)<<8) | int aob[loc];
			if(ploc >= len aob)
				return ("", -loc);
			loc++;
			pname: string;
			(pname, ploc) = getdn(aob, ploc);
			if(ploc < 1)
				return (name, -loc);
			name += pname;
			return (name, loc); # pointer ends dn
		}
		else if((l & 16rC0) == 0) {
			if(loc + l > len aob)
				return (name, -loc);
			name += string aob[loc:loc+l];
			loc += l;
			if(loc < len aob && aob[loc] != byte 0)
				name += ".";
		}
		else
			return (name, -loc);
	}
	return (name, loc);
}

putquesl(qrl: list of ref QR, aob: array of byte, loc: int): (array of byte, int)
{
	for(; qrl != nil && loc >= 0; qrl = tl qrl){
		q := hd qrl;
		(aob, loc) = putdn(q.qname, aob, loc);
		(aob, loc) = putword(q.qtype, aob, loc);
		(aob, loc) = putword(q.qclass, aob, loc);
	}
	return (aob, loc);
}

getquesl(nq: int, aob: array of byte, loc: int): (list of ref QR, int)
{
	if(loc < 0)
		return (nil, loc);
	qrl: list of ref QR;
	for(i := 0; i < nq; i++) {
		qd := ref QR;
		(qd.qname, loc) = getdn(aob, loc);
		(qd.qtype, loc) = getword(aob, loc);
		(qd.qclass, loc) = getword(aob, loc);
		if(loc < 1)
			return (qrl, loc);
		qrl = qd :: qrl;
	}
	q: list of ref QR;
	for(; qrl != nil; qrl = tl qrl)
		q = hd qrl :: q;
	return (q, loc);
}

putrrl(rrl: list of ref RR, aob: array of byte, loc: int): (array of byte, int)
{
	if(loc < 0)
		return (aob, loc);
	for(; rrl != nil; rrl = tl rrl){
		rr := hd rrl;
		(aob, loc) = putdn(rr.name, aob, loc);
		(aob, loc) = putword(rr.rtype, aob, loc);
		(aob, loc) = putword(rr.rclass, aob, loc);
		(aob, loc) = putlong(rr.ttl, aob, loc);
		case rr.rtype {
		Tptr =>
			(aob, loc) = putdn(rr.ptr, aob, loc);
		Tcname or Tns =>
			(aob, loc) = putdn(rr.host, aob, loc);
		* =>
			dlen := len rr.rdata;
			(aob, loc) = putword(dlen, aob, loc);
			if(loc < 1)
				return (aob, loc);
			if(loc + dlen > len aob)
				return (aob, -loc);
			aob[loc:] = rr.rdata;
			loc += dlen;
		}
	}
	return (aob, loc);
}

getrrl(nr: int, aob: array of byte, loc: int): (list of ref RR, int)
{
	if(loc < 0)
		return (nil, loc);
	rrl: list of ref RR;
	for(i := 0; i < nr; i++) {
		rr := ref RR;
		(rr.name, loc) = getdn(aob, loc);
		(rr.rtype, loc) = getword(aob, loc);
		(rr.rclass, loc) = getword(aob, loc);
		(rr.ttl, loc) = getlong(aob, loc);
		dlen: int;
		(dlen, loc) = getword(aob, loc);
		if(loc < 1)
			return (rrl, loc);
		if(dlen > 0) {
			tloc: int;
			n := loc+dlen;
			if(n > len aob)
				n = len aob;	# should moan?
			# must fetch names now since they can have C0 pointers into rest of message
			case rr.rtype {
			Tptr =>
				(rr.ptr, tloc) = getdn(aob, loc);
			Tcname or Tns =>
				(rr.host, tloc) = getdn(aob, loc);
			* =>
				rr.rdata = array[dlen] of byte;
				rr.rdata[0:] = aob[loc:n];
			}
			loc = n;
		}
		rrl = rr :: rrl;
	}
	r: list of ref RR;
	for(; rrl != nil; rrl = tl rrl)
		r = (hd rrl) :: r;
	return (r, loc);
}

msg2aob(msg: ref DNSmsg, addlen: int): array of byte
{
	ml := 12; # header length in octets
	for(qdl := msg.qd; qdl != nil; qdl = tl qdl){
		# if name is formatted correctly, the length of qname
		# should be the same as the length of the string + 2
		ml += (len (hd qdl).qname+2) + 4;
	}
	ml += rrlen(msg.an);
	ml += rrlen(msg.ns);
	ml += rrlen(msg.ar);

	n := 0;
	if(addlen)
		n = 2;
	aob := array[ml+n] of byte;

	l := 0;
	if(addlen)
		(aob, l) = putword(ml, aob, l);
	(aob, l) = putword(msg.id, aob, l);
	(aob, l) = putword(msg.flags, aob, l);
	(aob, l) = putword(len msg.qd, aob, l);
	(aob, l) = putword(len msg.an, aob, l);
	(aob, l) = putword(len msg.ns, aob, l);
	(aob, l) = putword(len msg.ar, aob, l);
	(aob, l) = putquesl(msg.qd, aob, l);
	(aob, l) = putrrl(msg.an, aob, l);
	(aob, l) = putrrl(msg.ns, aob, l);
	(aob, l) = putrrl(msg.ar, aob, l);
	if(l < 1)
		return nil;
	return aob;
}

aob2msg(aob: array of byte): ref DNSmsg
{
	msg := ref DNSmsg;
	msg.flags = Rformat;
	l := 0;
	(msg.id, l) = getword(aob, l);
	(msg.flags, l) = getword(aob, l);
	if(l < 0 || l > len aob){
		msg.err = "length error";		# might happen legally if truncated?
		return msg;
	}
	if(l >= len aob)
		return msg;

	nqd, nan, nns, nar: int;
	(nqd, l) = getword(aob, l);
	(nan, l) = getword(aob, l);
	(nns, l) = getword(aob, l);
	(nar, l) = getword(aob, l);
	if(l >= len aob)
		return msg;
	(msg.qd, l) = getquesl(nqd, aob, l);
	(msg.an, l) = getrrl(nan, aob, l);
	(msg.ns, l) = getrrl(nns, aob, l);
	(msg.ar, l) = getrrl(nar, aob, l);
	if(l < 1){
		sys->fprint(stderr, "l=%d format error\n", l);
		msg.err = "format error";
		return msg;
	}
	return msg;
}

rcodes := array[] of {
	Rok => "no error",
	Rformat => "format error",
	Rserver => "server failure",
	Rname => "bad name",
	Runimplemented => "unimplemented",
	Rrefused => "refused",
};

reason(n: int): string
{
	if(n < 0 || n > len rcodes)
		return sys->sprint("error %d", n);
	return rcodes[n];
}

readn(fd: ref Sys->FD, nb: int): array of byte
{
	buf:= array[nb] of byte;
	for(n:=0; n<nb;){
		m := sys->read(fd, buf[n:], nb-n);
		if(m <= 0)
			return nil;
		n += m;
	}
	return buf;
}

isdigit(c: int): int
{
	return (c >= '0' && c <= '9');
}

isnum(num: string): int
{
	for(i:=0; i<len num; i++)
		if(!isdigit(num[i]))
			return 0;
	return 1;
}

isipaddr(addr: string): int
{
	(nil, fields) := sys->tokenize(addr, ".");
	if(fields == nil)
		return 0;
	for(; fields != nil; fields = tl fields) {
		if(!isnum(hd fields) ||
			int hd fields < 0 ||
			int hd fields > 255)
			return 0;
	}
	return 1;
}

nrot := 0;	# rotation on servers list
dnsdir: ref Sys->Dir;		# state of DNS server file when last read

readservers(fname: string): list of string
{
	(ok, dir) := sys->stat(fname);
	if(ok != 0) {
		sys->fprint(stderr, "ipsrv: unable to stat %s\n", fname);
		return nil;
	}
	if(dnsdir != nil && samefile(*dnsdir, dir)){
		# required performance improvement -- move past bad dns!
		if (nrot) {
#		  	sys->print("rotate %d into %d\n", nrot, len servers);
			servers = rotate(servers, nrot);
			nrot = 0;
		}
		return servers;
	}
	dnsdir = ref dir;

#	sys->print("readservers: open %s \n", fname);
	fd := sys->open(fname, Sys->OREAD);
	if(fd == nil) {
		sys->fprint(stderr, "ipsrv: can't open %s: %r\n", fname);
		return nil;
	}
	buf := array[2048] of byte;
	n := sys->read(fd, buf, len buf);
	(nil, srvs) := sys->tokenize(string buf[0:n], "\r\n");
	buf = nil;
	ls: list of string;
	ndomain: string;
	for(; srvs != nil; srvs = tl srvs) {
		m := hd srvs;
		if(m[0] == '#')
			continue;
		if(isipaddr(m))
			ls = m :: ls;
		else if(ishostname(m))
			ndomain = m;
		else
			sys->fprint(stderr, "ipsrv: %s: invalid DNS server %s\n", fname, m);
	}
	if(len ls < 1)
		return nil;
	for(; ls != nil; ls = tl ls)
		srvs = hd ls :: srvs;
	domain = ndomain;
	return servers = srvs;
}

rotate(l: list of string, n: int): list of string
{
	m := n % (len l);
	if (m == 0)
		return l;
	if (m < 0)
		m = (len l) + m;
	nl: list of string;
	for(i := 0; i++ < m; l = tl l)
		nl = hd l :: nl;
	return append(l, reverse(nl));
}

reverse(l: list of string): list of string
{
	r: list of string;
	for(; l != nil; l = tl l)
		r = hd l :: r;
	return r;
}

append(h, t: list of string): list of string
{
	r := reverse(h);
	for(; r != nil; r = tl r)
		t = hd r :: t;
	return t;
}

# names that will not hang iph2a (why is this needed?)
ishostname(s: string): int
{
	if (s == nil) return 0;
	for (i := 0; i < len s; i++) {
		c := s[i];
		if (!(('0' <= c && c <= '9') ||
		    ('a' <= c && c <= 'z') ||
		    ('A' <= c && c <= 'Z') ||
		    c=='-' || c== '.' || c=='&'))
			return 0;
	}
	return 1;
}

# add subdomains - domain is read from dns/db
indomain(name: string): list of string
{
	inl: list of string;
	if (domain != nil) {
		hn := count('.', name);
		dn := count('.', domain);
		for (n := dn -1; n >= 0; n--)
			inl = name+"."+subcount('.', n, domain) :: inl;
	}
	return name :: inl;
}

count(e: int, s: string): int
{
	for ((i, n) := (0, 0); i < len s; i++)
		if (s[i] == e) n++;
	return n;
}

subcount(e, n: int, s: string): string
{
	if (!n || s == nil) return s;
	for ((i, m) := (0, 0); i < len s; i++)
		if (s[i] == e && ++m == n) break;
	if (++i < len s) return s[i:];
	return nil;
}

dnsquery(fd: ref Sys->FD, qtype: int, qclass: int, name: string): (ref DNSmsg, string)
{
	qd := ref QR;
	qd.qtype = qtype;
	qd.qclass = qclass;
	qd.qname = name;

	dm := ref DNSmsg;
	dm.id = 1;
	dm.flags = Oquery | Frecurse;
	dm.qd = qd :: nil;

	aob := msg2aob(dm, UseTCP);
	if(aob == nil)
		return (nil, "dns: bad query message");

	# reply
	if(UseTCP){
		n := sys->write(fd, aob, len aob);
		if(n != len aob)
			return (nil, sys->sprint("dns: write err: %r"));
		buf := readn(fd, 2);	# TCP/DNS record header
		(mlen, nil) := getword(buf, 0);
		if(mlen < 2 || mlen > 16384)
			return (nil, sys->sprint("dns: bad reply msg length=%d", mlen));
		buf = readn(fd, mlen);
		if(buf == nil)
			return (nil, sys->sprint("dns: read err: %r"));
		dm = aob2msg(buf);
		if(dm == nil)
			return (nil, "dns: bad reply message");
	}else{
		pidc := chan of int;
		c := chan of array of byte;
		spawn reader(fd, c, pidc);
		rpid := <-pidc;
		spawn timer(c, pidc);
		tpid := <-pidc;
		for(ntries := 0; ntries < 8; ntries++){
			if(DEBUG)
				sys->print("send[%d] %d\n", ntries, len aob);
			n := sys->write(fd, aob, len aob);
			if(n != len aob)
				return (nil, sys->sprint("dns: udp write err: %r"));
			buf := <-c;
			if(buf != nil){
				dm = aob2msg(buf);
				if(dm == nil){
					kill(tpid);
					kill(rpid);
					return (nil, "dns: bad udp reply message");
				}
				break;
			}else if(DEBUG)
				sys->print("timeout\n");
		}
		kill(tpid);
		kill(rpid);
	}
	if(dm.err != nil){
		sys->fprint(stderr, "dns: bad reply: %s\n", dm.err);
		return (nil, dm.err);
	}
	return (dm, nil);
}

reader(fd: ref Sys->FD, c: chan of array of byte, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		buf := array[4096] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0){
			if(DEBUG)
				sys->print("rcvd %d\n", n);
			c <-= buf[0:n];
		}else
			c <-= nil;
	}
}

timer(c: chan of array of byte, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		sys->sleep(5*1000);
		c <-= nil;
	}
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}

iph2a(mach: string): list of string
{
	if(isipaddr(mach))
		return mach :: nil;
	if(!ishostname(mach)) {
		sys->fprint(stderr, "ipsrv: invalid host name: %s\n", mach);
		return nil;
	}
	if(srv != nil){		# try the host's map first
		l := srv->iph2a(mach);
		if(l != nil)
			return l;
	}
	srvs := readservers(dnsfile);
	niter := 0;
	good := 0;
	while(srvs != nil && niter++ < Iterations){
		(fd, err) := dialdns(hd srvs);
		srvs = tl srvs;
		if (fd == nil) {
			# do not retry modem dialup on every DNS server!
			if (len err >= 10 && err[0:10] == "cs: dialup")
				sys->raise("fail: " + err[4:]);
			continue;
		}
		if(DEBUG)
			sys->fprint(stderr, "ipsrv: dial %s\n", hd srvs);
		# remember a good server so cs performance goes up!
		if (!good) {
			nrot = niter -1;
			good = 1;
		}
		for (lm := indomain(mach); lm != nil; lm = tl lm){
			(al, ns) := findhost(fd, hd lm, tl lm == nil);
			if (al != nil){
				if(hd al == "!")
					break;
				return al;
			}
			if(ns != nil)
				srvs = hd ns :: srvs;	# for now we'll try just the first one
		}
	}
	return nil;
}

findhost(fd: ref Sys->FD, mach: string, lastp: int): (list of string, list of string)
{
	(dm, err) := dnsquery(fd, Ta, Cin, mach);
	if(dm == nil){
		sys->fprint(stderr, "ipsrv: %s\n", err);
		return (nil, nil);
	}
	if((dm.flags&Rmask) != Rok){
		# don't repeat the request on an error
		#  TO DO: should return `best error'
		if((dm.flags & Rmask) == Rname && !(lastp || dm.flags&Fauth)){
			;	# TO DO: caller's search should stop on authoritative Nonexistent if lastp
			if(DEBUG)
				sys->fprint(stderr, "ipsrv: %s: remote dns: %s\n", mach, reason(dm.flags & Rmask));
		}else if((err = reason(dm.flags & Rmask)) != nil)
			sys->fprint(stderr, "ipsrv: %s: remote dns: %s\n", mach, err);
		return (nil, nil);
	}
	ips: list of string;
	cname: string;
	for(anl := dm.an; anl != nil; anl = tl anl){
		an := hd anl;
		case an.rtype {
		Ta =>
			rd := an.rdata;
			if(len rd == 4) {
				ipa := sys->sprint("%d.%d.%d.%d", int rd[0], int rd[1], int rd[2], int rd[3]);
				ips = ipa :: ips;
			}
		Tcname =>
			if(an.host != nil)
				cname = an.host;
		}
	}
	if(ips != nil)
		return (ips, nil);
	if(cname != nil)
		return (iph2a(cname), nil);	# try the alias (BUG: might loop!)
	if(dm.ns != nil){
		srvs: list of string;
		for(anl = dm.ns; anl != nil; anl = tl anl){
			an := hd anl;
			case an.rtype {
			Tns =>
				if(DEBUG)
					sys->fprint(stderr, "ipsrv: %s: try ns %s\n", mach, an.host);
				ipa := hinted(an.host, dm.ar);
				if(ipa != nil)
					srvs = ipa :: srvs;
				else
					srvs = an.host :: srvs;
			* =>
				sys->fprint(stderr, "ipsrv: %s: type %d in ns list\n", mach, an.rtype);
			}
		}
		if(srvs != nil)
			return (nil, srvs);
	}
	return ("!" :: nil, nil);		# TO DO: eliminate this hack (it's a flag to break out of the domain loop
}

hinted(name: string, rl: list of ref RR): string
{
	for(; rl != nil; rl = tl rl){
		an := hd rl;
		if(an.name == name && an.rtype == Ta && len an.rdata == 4){
			rd := an.rdata;
			return sys->sprint("%d.%d.%d.%d", int rd[0], int rd[1], int rd[2], int rd[3]);
		}
	}
	return nil;
}

ipa2h(addr: string): list of string
{
	if(srv != nil){		# try the host's map first
		l := srv->ipa2h(addr);
		if(l != nil)
			return l;
	}
	tmpservers := readservers(dnsfile);
	niter := 0;
	good := 0;
Searching:
	while(tmpservers != nil && niter++ < Iterations) {
		(fd, err) := dialdns(hd tmpservers);
		tmpservers = tl tmpservers;
		if (fd == nil) {
			# do not retry modem dialup on every DNS server!
			if (err[0:10] == "cs: dialup")
				sys->raise("fail: " + err[4:]);
			continue;
		}

		# remember a good server for cs performance!
		if (!good) {
			nrot = niter -1;
			good = 1;
		}

		(n, ipseg) := sys->tokenize(addr, ".");
		if (n != 4) {
			sys->fprint(stderr, "ipsrv: bad address %s\n", addr);
			return nil;
		}
		inaddr := sys->sprint("%s.%s.%s.%s.in-addr.arpa", hd tl tl tl ipseg, hd tl tl ipseg, hd tl ipseg, hd ipseg);
		(dm, diag) := dnsquery(fd, Tptr, Cin, inaddr);
		if(dm == nil){
			sys->fprint(stderr, "ipsrv: %s\n", diag);
			return nil;
		}
		if((dm.flags&Rmask) != Rok){
			err = reason(dm.flags&Rmask);
			sys->fprint(stderr, "ipsrv: remote dns: %s\n", err);
			if((dm.flags&Rmask) == Rname){
				if(dm.flags & Fauth)
					return nil;
			}
			continue Searching;		# might be server's fault
		}
		dms: list of string;
		for(anl := dm.an; anl != nil; anl = tl anl){
			an := hd anl;
			if(an.rtype == Tptr && an.ptr != nil) {
				# eliminate obvious duplicates (are there any?)
				if(dms == nil || an.ptr != hd dms)
					dms = an.ptr :: dms;
			}
		}
		if(dms != nil)
			return reverse(dms);
		# collect new name servers
		for(arl := dm.ar; arl != nil; arl = tl arl){
			rd := (hd arl).rdata;
			if(len rd == 4) {
				ipa := sys->sprint("%d.%d.%d.%d", int rd[0], int rd[1], int rd[2], int rd[3]);
				tmpservers = append(tmpservers, ipa::nil);
			}
		}
	}
	return nil;
}

dialdns(server: string): (ref Sys->FD, string)
{
	proto := "udp";
	if(UseTCP)
		proto = "tcp";
	(ok, conn) := sys->dial(proto+"!"+server+"!"+(string DNSport), nil);
	if(ok == -1) {
		err := sys->sprint("%r");
		sys->fprint(stderr, "ipsrv: error connecting to %s dns server: %s\n", proto, err);
		return (nil, err);
	}
	return (conn.dfd, nil);
}
