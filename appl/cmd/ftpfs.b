implement Ftpfs;

include "sys.m";
	sys: Sys;
	FD, Connection, Dir: import Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "daytime.m";
	time: Daytime;
	Tm: import time;

include "string.m";
	str: String;

include "styxlib.m";
	styxlib: Styxlib;
	Styxserver, Chan, Tmsg, Rmsg: import styxlib;

Ftpfs: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

#
#	File system node.  Refers to parent and file structure.
#	Siblings are linked.  The head is parent.children.
#

Node : adt
{
	dir:		Dir;
	uniq:		int;
	parent:		cyclic ref Node;
	sibs:		cyclic ref Node;
	children:	cyclic ref Node;
	file:		cyclic ref File;
	depth:		int;
	longname:	string;
	cached:		int;
	valid:		int;

	extendpath:	fn(parent: self ref Node, elem: string) : ref Node;
	fixsymbolic:	fn(n: self ref Node);
	invalidate:	fn(n: self ref Node);
	markcached:	fn(n: self ref Node);
	uncache:	fn(n: self ref Node);
	uncachedir:	fn(parent: self ref Node, child: ref Node);

	convD2M:	fn(n: self ref Node, x: int);
	qid:		fn(n: self ref Node) : Sys->Qid;

	fileget:	fn(n: self ref Node) : ref File;
	filefree:	fn(n: self ref Node);
	fileclean:	fn(n: self ref Node);
	fileisdirty:	fn(n: self ref Node) : int;
	filedirty:	fn(n: self ref Node);
	fileread:	fn(n: self ref Node, b: array of byte, off, c: int) : int;
	filewrite:	fn(n: self ref Node, b: array of byte, off, c: int) : int;

	action:		fn(n: self ref Node, cmd: string) : int;
	createdir:	fn(n: self ref Node) : int;
	createfile:	fn(n: self ref Node) : int;
	changedir:	fn(n: self ref Node) : int;
	docreate:	fn(n: self ref Node) : int;
	mkunique:	fn(parent: self ref Node, off: int) : int;
	pathname:	fn(n: self ref Node) : string;
	readdir:	fn(n: self ref Node) : int;
	readfile:	fn(n: self ref Node) : int;
	removedir:	fn(n: self ref Node) : int;
	removefile:	fn(n: self ref Node) : int;
};

#
#	Styx protocol file identifier.
#

Fid : adt
{
	fid:	int;
	node:	ref Node;
	busy:	int;
};

#
#	Foreign file with cache.
#

File : adt
{
	cache:		array of byte;
	length:		int;
	offset:		int;
	fd:		ref FD;
	inuse, dirty:	int;
	atime:		int;
	node:		cyclic ref Node;
	tempname:	string;

	createtmp:	fn(f: self ref File) : ref FD;
};

ftp:		Connection;
dfid:			ref FD;
dfidiob:		ref Iobuf;
buffresidue:	int = 0;
tbuff:		array of byte;
rbuff:		array of byte;
ccfd:			ref FD;
stdin, stderr:	ref FD;

fids:		list of ref Fid;

BSZ:		con 8192;
Chunk:		con 1024;
Nfiles:		con 128;

CHSYML:		con 16r40000000;

mountpoint:	string = "/n/ftp";
user:			string = nil;
password:		string;
hostname:	string = "kremvax";
anon:		string = "anon";

firewall:		string = "tcp!$PROXY!402";
myname:		string = "anon";
myhost:		string = "lucent.com";
proxyid:		string;
proxyhost:	string;

errstr:		string;
net:			string;
port:			int;

Enosuchfile:	con "file does not exist";
Eftpproto:	con "ftp protocol error";
Eshutdown:	con "remote shutdown";
Eioerror:	con "io error";
Enotadirectory:	con "not a directory";
Eisadirectory:	con "is a directory";
Epermission:	con "permission denied";
Ebadoffset:	con "bad offset";
Ebadlength:	con "bad length";
Enowstat:	con "wstat not implemented";
Emesgmismatch:	con "message size mismatch";

remdir:		ref Node;
remroot:	ref Node;
remrootpath:	string;

ss:	ref Styxserver;
heartbeatpid, controlmanagerpid: int;

#
#	FTP protocol codes are 3 digits >= 100.
#	The code type is obtained by dividing by 100.
#

Syserr:		con -2;
Syntax:		con -1;
Shutdown:	con 0;
Extra:		con 1;
Success:	con 2;
Incomplete:	con 3;
TempFail:	con 4;
PermFail:	con 5;
Impossible:	con 6;
Err:		con 7;

debug:		int = 0;
quiet:		int = 0;
active:		int = 0;
cdtoroot:		int = 0;

proxy:		int = 0;

mountfd:	ref FD;
styxlibfd: ref FD;

usage()
{
	sys->print("usage: ftpfs [-/dpq] [-m mountpoint] [-a password] ftphost\n");
	exit;
}

#
#	Set up FDs for service.
#

connect() : string
{
	pip := array[2] of ref Sys->FD;
	if(sys->pipe(pip) < 0)
		return sys->sprint("can't create pipe: %r");
	mountfd = pip[0];
	styxlibfd = pip[1];
	return nil;
}

#shut(s: string)
#{
#	sys->print("ftpfs: %s shutdown\n", s);
#}

#
#	Mount server.  Must be spawned because it does
#	an attach transaction.
#

mount(mountpoint: string)
{
	if (sys->mount(mountfd, mountpoint, sys->MREPL | sys->MCREATE, nil) < 0) {
		sys->print("mount %s failed: %r\n", mountpoint);
		shutdown();
	}
	mountfd = nil;
}

#
#	Keep the link alive.
#

beatquanta:	con 10;
beatlimit:	con 10;
beatcount:	int;
activity:	int;
transfer:	int;

heartbeat(pidc: chan of int)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	for (;;) {
		sys->sleep(beatquanta * 1000);
		if (activity || transfer) {
			beatcount = 0;
			activity = 0;
			continue;
		}
		beatcount++;
		if (beatcount == beatlimit) {
			acquire();
			if (sendrequest("NOOP", 0) == Success)
				getreply(0);
			release();
			beatcount = 0;
			activity = 0;
		}
	}
}

#
#	Control lock.
#

grant:	chan of int;
notify:	chan of int;

controlmanager(pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		<- grant;
		<- notify;
	}
}

acquire()
{
	grant <- = 0;
}

release()
{
	notify <- = 0;
}

#
#	Data formatting routines.
#

sendreply(r: ref Rmsg)
{
	if (debug)
		sys->print("> %s\n", styxlib->rmsg2s(r));
	ss.reply(r);
}

rerror(tag: int, s: string)
{
	if (debug)
		sys->print("error: %s\n", s);
	sendreply(ref Rmsg.Error(tag, s));
}

seterr(e: int, s: string) : int
{
	case e {
	Syserr =>
		errstr = Eioerror;
	Syntax =>
		errstr = Eftpproto;
	Shutdown =>
		errstr = Eshutdown;
	* =>
		errstr = s;
	}
	return -1;
}

#
#	Node routines.
#

anode:	Node;
npath:	int	= 1;

newnode(parent: ref Node, name: string) : ref Node
{
	n := ref anode;
	n.dir.name = name;
	n.dir.atime = time->now();
	n.children = nil;
	n.longname = name;
	if (parent != nil) {
		n.parent = parent;
		n.sibs = parent.children;
		parent.children = n;
		n.depth = parent.depth + 1;
		n.valid = 0;
	} else {
		n.parent = n;
		n.sibs = nil;
		n.depth = 0;
		n.valid = 1;
		n.dir.uid = anon;
		n.dir.gid = anon;
		n.dir.mtime = n.dir.atime;
	}
	n.file = nil;
	n.uniq = npath++;
	n.cached = 0;
	return n;
}

Node.extendpath(parent: self ref Node, elem: string) : ref Node
{
	n: ref Node;

	for (n = parent.children; n != nil; n = n.sibs)
		if (n.dir.name == elem)
			return n;
	return newnode(parent, elem);
}

Node.markcached(n: self ref Node)
{
	n.cached = 1;
	n.dir.atime = time->now();
}

Node.uncache(n: self ref Node)
{
	if (n.fileisdirty())
		n.createfile();
	n.filefree();
	n.cached = 0;
}

Node.uncachedir(parent: self ref Node, child: ref Node)
{
	sp: ref Node;

	if (parent == nil || parent == child)
		return;
	for (sp = parent.children; sp != nil; sp = sp.sibs)
		if (sp != child && sp.file != nil && !sp.file.dirty && sp.file.fd != nil) {
			sp.filefree();
			sp.cached = 0;
		}
}

Node.invalidate(node: self ref Node)
{
	n: ref Node;

	node.uncachedir(nil);
	for (n = node.children; n != nil; n = n.sibs) {
		n.cached = 0;
		n.invalidate();
		n.valid = 0;
	}
}

Node.fixsymbolic(n: self ref Node)
{
	if (n.changedir() == 0) {
		n.dir.mode |= Sys->CHDIR; 
		n.uniq |= Sys->CHDIR;
	}
	n.dir.mode &= ~CHSYML; 
}

Node.convD2M(n: self ref Node, x: int)
{
	styxlib->convD2M(tbuff[x:], n.dir);
}

Node.qid(n: self ref Node) : Sys->Qid
{
	return Sys->Qid(n.uniq, 0);
}

#
#	File routines.
#

ntmp:	int;
files:	list of ref File;
nfiles:	int;
afile:	File;
atime:	int;

#
#	Allocate a file structure for a node.  If too many
#	are already allocated discard the oldest.
#

Node.fileget(n: self ref Node) : ref File
{
	f, o: ref File;
	l: list of ref File;

	if (n.file != nil)
		return n.file;
	o = nil;
	for (l = files; l != nil; l = tl l) {
		f = hd l;
		if (f.inuse == 0)
			break;
		if (!f.dirty && (o == nil || o.atime > f.atime))
			o = f;
	}
	if (l == nil) {
		if (nfiles == Nfiles && o != nil) {
			o.node.uncache();
			f = o;
		}
		else {
			f = ref afile;
			files = f :: files;
			nfiles++;
		}
	}
	n.file = f;
	f.node = n;
	f.atime = atime++;
	f.inuse = 1;
	f.dirty = 0;
	f.length = 0;
	f.fd = nil;
	return f;
}

#
#	Create a temporary file for a local copy of a file.
#	If too many are open uncache parent.
#

File.createtmp(f: self ref File) : ref FD
{
	t := "/tmp/ftp." + string time->now() + "." + string ntmp;
	if (ntmp >= 16)
		f.node.parent.uncachedir(f.node);
	f.fd = sys->create(t, Sys->ORDWR | Sys->ORCLOSE, 8r600);
	f.tempname = t;
	f.offset = 0;
	ntmp++;
	return f.fd;
}

#
#	Read 'c' bytes at offset 'off' from a file into buffer 'b'.
#

Node.fileread(n: self ref Node, b: array of byte, off, c: int) : int
{
	f: ref File;
	t, i: int;

	f = n.file;
	if (off + c > f.length)
		c = f.length - off;
	for (t = 0; t < c; t += i) {
		if (off >= f.length)
			return t;
		if (off < Chunk) {
			i = c;
			if (off + i > Chunk)
				i = Chunk - off;
			b[t:] = f.cache[off: off + i];
		}
		else {
			if (f.offset != off) {
				if (sys->seek(f.fd, off, Sys->SEEKSTART) < 0) {
					f.offset = -1;
					return seterr(Err, sys->sprint("seek temp failed: %r"));
				}
			}
			if (t == 0)
				i = sys->read(f.fd, b, c - t);
			else
				i = sys->read(f.fd, rbuff, c - t);
			if (i < 0) {
				f.offset = -1;
				return seterr(Err, sys->sprint("read temp failed: %r"));
			}
			if (i == 0)
				break;
			if (t > 0)
				b[t:] = rbuff[0: i];
			f.offset = off + i;
		}
		off += i;
	}
	return t;
}

#
#	Write 'c' bytes at offset 'off' to a file from buffer 'b'.
#

Node.filewrite(n: self ref Node, b: array of byte, off, c: int) : int
{
	f: ref File;
	t, i: int;

	f = n.fileget();
	if (f.cache == nil)
		f.cache = array[Chunk] of byte;
	for (t = 0; t < c; t += i) {
		if (off < Chunk) {
			i = c;
			if (off + i > Chunk)
				i = Chunk - off;
			f.cache[off:] = b[t: t + i];
		}
		else {
			if (f.fd == nil) {
				if (f.createtmp() == nil)
					return seterr(Err, sys->sprint("temp file: %r"));
				if (sys->write(f.fd, f.cache, Chunk) != Chunk) {
					f.offset = -1;
					return seterr(Err, sys->sprint("write temp failed: %r"));
				}
				f.offset = Chunk;
				f.length = Chunk;
			}
			if (f.offset != off) {
				if (off > f.length) {
					# extend the file with zeroes
					# sparse files may not be supported
				}
				if (sys->seek(f.fd, off, Sys->SEEKSTART) < 0) {
					f.offset = -1;
					return seterr(Err, sys->sprint("seek temp failed: %r"));
				}
			}
			i = sys->write(f.fd, b[t:len b], c - t);
			if (i != c - t) {
				f.offset = -1;
				return seterr(Err, sys->sprint("write temp failed: %r"));
			}
		}
		off += i;
		f.offset = off;
	}
	if (off > f.length)
		f.length = off;
	return t;
}

Node.filefree(n: self ref Node)
{
	f: ref File;

	f = n.file;
	if (f == nil)
		return;
	if (f.fd != nil) {
		ntmp--;
		f.fd = nil;
		f.tempname = nil;
	}
	f.cache = nil;
	f.length = 0;
	f.inuse = 0;
	f.dirty = 0;
	n.file = nil;
}

Node.fileclean(n: self ref Node)
{
	if (n.file != nil)
		n.file.dirty = 0;
}

Node.fileisdirty(n: self ref Node) : int
{
	return n.file != nil && n.file.dirty;
}

Node.filedirty(n: self ref Node)
{
	f: ref File;

	f = n.fileget();
	f.dirty = 1;
}

#
#	Fid management.
#

afid:	Fid;

getfid(fid: int) : ref Fid
{
	l: list of ref Fid;
	f, ff: ref Fid;

	ff = nil;
	for (l = fids; l != nil; l = tl l) {
		f = hd l;
		if (f.fid == fid) {
			if (f.busy)
				return f;
			else {
				ff = f;
				break;
			}
		} else if (ff == nil && !f.busy)
			ff = f;
	}
	if (ff == nil) {
		ff = ref afid;
		fids = ff :: fids;
	}
	ff.node = nil;
	ff.fid = fid;
	return ff;
}

#
#	FTP protocol.
#

fail(s: int, l: string)
{
	case s {
	Syserr =>
		sys->print("read fail: %r\n");
	Syntax =>
		sys->print("%s\n", Eftpproto);
	Shutdown =>
		sys->print("%s\n", Eshutdown);
	* =>
		sys->print("unexpected response: %s\n", l);
	}
	exit;
}

getfullreply(echo: int) : (int, int, string)
{
	buffmulti: string;
	s: string;
	done: int;
	done = 0;
	buffmulti = nil;
	while (!done) {
		s = dfidiob.gets(int '\n');
		if (s == nil || len s < 2)
			return (Shutdown, 0, nil);
		# process string
		if (s[len s - 1] == '\n') {
			if (s[len s - 2] == '\r')
				s = s[0: len s - 2];
			else
				s = s[0: len s - 1];
		}
		if (debug || echo)
			sys->print("%s\n", s);
		if (len s < 4)
			return (Syntax, 0, nil);
		if (buffmulti != nil) {
			if (s[3] == ' ' && s[0 : 3] == buffmulti) {
				done = 1;
				break;
			}
		}
		else if (s[3] == '-')
			buffmulti = s[0:3];
		else {
			done = 1;
			break;
		}
	}
	# only way to here is if the last line of a multiline, or a single line response
	# has been found

	c := int s[0:3];
	if (c < 100)
		return (Syntax, 0, nil);
	return (c / 100, c, s);
}

getreply(echo: int) : (int, string)
{
	(c, code, s) := getfullreply(echo);
	return (c, s);
}

sendrequest2(req: string, echo: int, figleaf: string) : int
{
	activity = 1;
	if (debug || echo) {
		if (figleaf == nil)
			figleaf = req;
		sys->print("%s\n", figleaf);
	}
	b := array of byte (req + "\r\n");
	n := sys->write(dfid, b, len b);
	if (n < 0)
		return Syserr;
	if (n != len b)
		return Shutdown;
	return Success;
}

sendrequest(req: string, echo: int) : int
{
	return sendrequest2(req, echo, req);
}

sendfail(s: int)
{
	case s {
	Syserr =>
		sys->print("write fail: %r\n");
	Shutdown =>
		sys->print("%s\n", Eshutdown);
	* =>
		sys->print("internal error\n");
	}
	exit;
}

dataport(l: list of string) : string
{
	s := "tcp!" + hd l;
	l = tl l;
	s = s + "." + hd l;
	l = tl l;
	s = s + "." + hd l;
	l = tl l;
	s = s + "." + hd l;
	l = tl l;
	return s + "!" + string ((int hd l * 256) + (int hd tl l));
}

commas(l: list of string) : string
{
	s := hd l;
	l = tl l;
	while (l != nil) {
		s = s + "," + hd l;
		l = tl l;
	}
	return s;
}

third(cmd: string) : ref FD
{
	acquire();
	for (;;) {
		(n, data) := sys->dial(firewall, nil);
		if (n < 0) {
			if (debug)
				sys->print("dial %s failed: %r\n", firewall);
			break;
		}
		t := sys->sprint("\n%s!*\n\n%s\n%s\n1\n-1\n-1\n", proxyhost, myhost, myname);
		b := array of byte t;
		n = sys->write(data.dfd, b, len b);
		if (n < 0) {
			if (debug)
				sys->print("firewall write failed: %r\n");
			break;
		}
		b = array[256] of byte;
		n = sys->read(data.dfd, b, len b);
		if (n < 0) {
			if (debug)
				sys->print("firewall read failed: %r\n");
			break;
		}
		(c, k) := sys->tokenize(string b[:n], "\n");
		if (c < 2) {
			if (debug)
				sys->print("bad response from firewall\n");
			break;
		}
		if (hd k != "0") {
			if (debug)
				sys->print("firewall connect: %s\n", hd tl k);
			break;
		}
		p := hd tl k;
		if (debug)
			sys->print("portid %s\n", p);
		(c, k) = sys->tokenize(p, "!");
		if (c < 3) {
			if (debug)
				sys->print("bad portid from firewall\n");
			break;
		}
		n = int hd tl tl k;
		(c, k) = sys->tokenize(hd tl k, ".");
		if (c != 4) {
			if (debug)
				sys->print("bad portid ip address\n");
			break;
		}
		t = sys->sprint("PORT %s,%d,%d", commas(k), n / 256, n & 255);
		r := sendrequest(t, 0);
		if (r != Success)
			break;
		(r, nil) = getreply(0);
		if (r != Success)
			break;
		r = sendrequest(cmd, 0);
		if (r != Success)
			break;
		(r, nil) = getreply(0);
		if (r != Extra)
			break;
		n = sys->read(data.dfd, b, len b);
		if (n < 0) {
			if (debug)
				sys->print("firewall read failed: %r\n");
			break;
		}
		b = array of byte "0\n?\n";
		n = sys->write(data.dfd, b, len b);
		if (n < 0) {
			if (debug)
				sys->print("firewall write failed: %r\n");
			break;
		}
		release();
		return data.dfd;
	}
	release();
	return nil;
}

passive(cmd: string) : ref FD
{
	acquire();
	if (sendrequest("PASV", 0) != Success) {
		release();
		return nil;
	}
	(r, m) := getreply(0);
	release();
	if (r != Success)
		return nil;
	(nil, p) := str->splitl(m, "(");
	if (p == nil)
		str->splitl(m, "0-9");
	else
		p = p[1:len p];
	(c, l) := sys->tokenize(p, ",");
	if (c < 6) {
		sys->print("data: %s\n", m);
		return nil;
	}
	a := dataport(l);
	if (debug)
		sys->print("data dial %s\n", a);
	(s, d) := sys->dial(a, nil);
	if (s < 0)
		return nil;
	acquire();
	r = sendrequest(cmd, 0);
	if (r != Success) {
		release();
		return nil;
	}
	(r, m) = getreply(0);
	release();
	if (r != Extra)
		return nil;
	return d.dfd;
}

getnet(dir: string): (string, int)
{
	buf := array[50] of byte;
	n := dir + "/local";
	lfd := sys->open(n, Sys->OREAD);
	if (lfd == nil) {
		if (debug)
			sys->fprint(stderr, "open %s: %r\n", n);
		return (nil, 0);
	}
	length := sys->read(lfd, buf, len buf);
	if (length < 0) {
		if (debug)
			sys->fprint(stderr, "read%s: %r\n", n);
		return (nil, 0);
	}
	(r, l) := sys->tokenize(string buf[0:length], "!");
	if (r != 2) {
		if (debug)
			sys->fprint(stderr, "tokenize(%s) returned (%d)\n", string buf[0:length], r);
		return (nil, 0);
	}
	if (debug)
		sys->print("net is %s!%d\n", hd l, int hd tl l);
	return (hd l, int hd tl l);
}
	
activate(cmd: string) : ref FD
{
	r: int;

	listenport, dataport: Connection;
	m: string;

	(r, listenport) = sys->announce("tcp!" + net + "!0");
	if (r < 0)
		return nil;
	(x1, x2)  := getnet(listenport.dir);
	(x3, x4) := sys->tokenize(x1, ".");
	t := sys->sprint("PORT %s,%d,%d", commas(x4), int x2 / 256, int x2&255);
	acquire();
	r = sendrequest(t, 0);
	if (r != Success) {
		release();
		return nil;
	}
	(r, m) = getreply(0);
	if (r != Success) {
		release();
		return nil;
	}
	r = sendrequest(cmd, 0);
	if (r != Success) {
		release();
		return nil;
	}
	(r, m) = getreply(0);
	release();
	if (r != Extra)
		return nil;
	(r, dataport) = sys->listen(listenport);
	if (r < 0) {
		sys->fprint(stderr, "activate: listen failed: %r\n");
		return nil;
	}
	fd := sys->open(dataport.dir + "/data", sys->ORDWR);
	if (debug)
		sys->print("activate: data connection on %s\n", dataport.dir);
	if (fd == nil) {
		sys->fprint(stderr, "activate: open of %s failed: %r\n", dataport.dir);
		return nil;
	}
	return fd;
}

data(cmd: string) : ref FD
{
	if (proxy)
		return third(cmd);
	else if (active)
		return activate(cmd);
	else
		return passive(cmd);
}

#
#	File list cracking routines.
#

shorten(name: string, off: int) : string
{
	l := len name;
	if (l < Sys->NAMELEN)
		return name;
	return name[0:Sys->NAMELEN - off - 1] + "*" + name[l - off:l];
}

Node.mkunique(parent: self ref Node, off: int) : int
{
	n, p: ref Node;

	change := 0;
	for (n = parent.children; n != nil; n = n.sibs) {
		for (p = n.sibs; p != nil; p = p.sibs) {
			if (n.dir.name != p.dir.name)
				continue;
			p.dir.name = shorten(p.longname, off);
			change = 1;
		}
	}
	return change;
}

fields(l: list of string, n: int) : array of string
{
	a := array[n] of string;
	for (i := 0; i < n; i++) {
		a[i] = hd l;
		l = tl l;
	}
	return a;
}

now:	ref Tm;
months:	con "janfebmaraprmayjunjulaugsepoctnovdec";

cracktime(month, day, year, hms: string) : int
{
	tm: Tm;

	if (now == nil)
		now = time->local(time->now());
	tm = *now;
	if (month[0] >= '0' && month[0] <= '9') {
		tm.mon = int month - 1;
		if (tm.mon < 0 || tm.mon > 11)
			tm.mon = 5;
	}
	else if (len month >= 3) {
		month = str->tolower(month[0:3]);
		for (i := 0; i < 36; i += 3)
			if (month == months[i:i+3]) {
				tm.mon = i / 3;
				break;
			}
	}
	tm.mday = int day;
	if (hms != nil) {
		(h, z) := str->splitl(hms, "apAP");
		(a, b) := str->splitl(h, ":");
		tm.hour = int a;
		if (b != nil) {
			(c, d) := str->splitl(b[1:len b], ":");
			tm.min = int c;
			if (d != nil)
				tm.sec = int d[1:len d];
		}
		if (z != nil && str->tolower(z)[0] == 'p')
			tm.hour += 12;
	}
	if (year != nil) {
		tm.year = int year;
		if (tm.year >= 1900)
			tm.year -= 1900;
	}
	else {
		if (tm.mon > now.mon || (tm.mon == now.mon && tm.mday > now.mday+1))
			tm.year--;
	}
	return time->tm2epoch(ref tm);
}

crackmode(p: string) : int
{
	flags := 0;
	case len p {
	10 =>	# unix and new style plan 9
		case p[0] {
		'l' =>
			return CHSYML | 0777;
		'd' =>
			flags = Sys->CHDIR;
		}
		p = p[1:10];
	11 =>	# old style plan 9
		if (p[0] == 'l')
			flags = Sys->CHDIR;
		p = p[2:11];
	* =>
		return Sys->CHDIR | 0777;
	}
	mode := 0;
	n := 0;
	for (i := 0; i < 3; i++) {
		mode <<= 3;
		if (p[n] == 'r')
			mode |= 4;
		if (p[n+1] == 'w')
			mode |= 2;
		case p[n+2] {
		'x' or 's' or 'S' =>
			mode |= 1;
		}
		n += 3;
	}
	return mode | flags;
}

crackdir(p: string) : (string, Dir)
{
	d: Dir;
	ln, a: string;

	(n, l) := sys->tokenize(p, " \t\r\n");
	f := fields(l, n);
	if (n > 2 && f[n - 2] == "->")
		n -= 2;
	case n {
	8 =>	# ls -l
		ln = f[7];
		d.uid = f[2];
		d.gid = f[2];
		d.mode = crackmode(f[0]);
		d.length = int f[3];
		(a, nil) = str->splitl(f[6], ":");
		if (len a != len f[6])
			d.atime = cracktime(f[4], f[5], nil, f[6]);
		else
			d.atime = cracktime(f[4], f[5], f[6], nil);
	9 =>	# ls -lg
		ln = f[8];
		d.uid = f[2];
		d.gid = f[3];
		d.mode = crackmode(f[0]);
		d.length = int f[4];
		(a, nil) = str->splitl(f[7], ":");
		if (len a != len f[7])
			d.atime = cracktime(f[5], f[6], nil, f[7]);
		else
			d.atime = cracktime(f[5], f[6], f[7], nil);
	10 =>	# plan 9
		ln = f[9];
		d.uid = f[3];
		d.gid = f[4];
		d.mode = crackmode(f[0]);
		d.length = int f[5];
		(a, nil) = str->splitl(f[8], ":");
		if (len a != len f[8])
			d.atime = cracktime(f[6], f[7], nil, f[8]);
		else
			d.atime = cracktime(f[6], f[7], f[8], nil);
	4 =>	# NT
		ln = f[3];
		d.uid = anon;
		d.gid = anon;
		if (f[2] == "<DIR>") {
			d.length = 0;
			d.mode = Sys->CHDIR | 8r777;
		}
		else {
			d.mode = 8r666;
			d.length = int f[2];
		}
		(n, l) = sys->tokenize(f[0], "/-");
		if (n == 3)
			d.atime = cracktime(hd l, hd tl l, f[2], f[1]);
	1 =>	# ls
		ln = f[0];
		d.uid = anon;
		d.gid = anon;
		d.mode = 0777;
		d.atime = 0;
	* =>
		return (nil, d);
	}
	if (ln == "." || ln == "..")
		return (nil, d);
	d.mtime = d.atime;
	d.name = shorten(ln, 0);
	return (ln, d);
}

longls	: int = 1;

Node.readdir(n: self ref Node) : int
{
	f: ref FD;
	p: ref Node;

	if (n.changedir() < 0)
		return -1;
	transfer = 1;
	for (;;) {
		if (longls) {
			f = data("LIST -l");
			if (f == nil) {
				longls = 0;
				continue;
			}
		}
		else {
			f = data("LIST");
			if (f == nil) {
				transfer = 0;
				return seterr(Err, Enosuchfile);
			}
		}
		break;
	}
	b := bufio->fopen(f, sys->OREAD);
	if (b == nil) {
		transfer = 0;
		return seterr(Err, Eioerror);
	}
	while ((s := b.gets('\n')) != nil) {
		if (debug)
			sys->print("%s", s);
		(l, d) := crackdir(s);
		if (l == nil)
			continue;
		p = n.extendpath(l);
		p.dir = d;
		p.uniq |= d.mode & Sys->CHDIR;
		p.valid = 1;
	}
	for (i := 0; i < Sys->NAMELEN-5; i++)
		if (n.mkunique(i) == 0)
			break;
	(r, nil) := getreply(0);
	transfer = 0;
	if (r != Success)
		return seterr(Err, Enosuchfile);
	return 0;
}

Node.readfile(n: self ref Node) : int
{
	c: int;

	if (n.parent.changedir() < 0)
		return -1;
	transfer = 1;
	f := data("RETR " + n.longname);
	if (f == nil) {
		transfer = 0;
		return seterr(Err, Enosuchfile);
	}
	off := 0;
	while ((c = sys->read(f, tbuff, BSZ)) > 0) {
		if (n.filewrite(tbuff, off, c) != c) {
			off = -1;
			break;
		}
		off += c;
	}
	if (c < 0) {
		transfer = 0;
		return seterr(Err, Eioerror);
	}
	n.filewrite(tbuff, off, 0);
	(s, nil) := getreply(0);
	transfer = 0;
	if (s != Success)
		return seterr(s, Enosuchfile);
	return off;
}

path(a, b: string) : string
{
	if (a == nil)
		return b;
	if (b == nil)
		return a;
	if (a[len a - 1] == '/')
		return a + b;
	else
		return a + "/" + b;
}

Node.pathname(n: self ref Node) : string
{
	s: string;

	while (n != n.parent) {
		s = path(n.longname, s);
		n = n.parent;
	}
	return path(remrootpath, s);
}

Node.changedir(n: self ref Node) : int
{
	t: ref Node;
	d: string;

	t = n;
	if (t == remdir)
		return 0;
	if (n.depth == 0)
		d = remrootpath;
	else
		d = n.pathname();
	remdir.uncachedir(nil);
	acquire();
	r := sendrequest("CWD " + d, 0);
	if (r == Success)
		(r, nil) = getreply(0);
	release();
	case r {
	Success
#	or Incomplete
		=>
		remdir = n;
		return 0;
	* =>
		return seterr(r, Enosuchfile);
	}
}

Node.docreate(n: self ref Node) : int
{
	f: ref FD;

	transfer = 1;
	f = data("STOR " + n.longname);
	if (f == nil) {
		transfer = 0;
		return -1;
	}
	off := 0;
	for (;;) {
		r := n.fileread(tbuff, off, BSZ);
		if (r <= 0)
			break;
		if (sys->write(f, tbuff, r) < 0) {
			off = -1;
			break;
		}
		off += r;
	}
	transfer = 0;
	return off;
}

Node.createfile(n: self ref Node) : int
{
	if (n.parent.changedir() < 0)
		return -1;
	off := n.docreate();
	if (off < 0)
		return -1;
	(r, nil) := getreply(0);
	if (r != Success)
		return -1;
	return off;
}

Node.action(n: self ref Node, cmd: string) : int
{
	if (n.parent.changedir() < 0)
		return -1;
	acquire();
	r := sendrequest(cmd + " " + n.dir.name, 0);
	if (r == Success)
		(r, nil) = getreply(0);
	release();
	if (r != Success)
		return -1;
	return 0;
}

Node.createdir(n: self ref Node) : int
{
	return n.action("MKD");
}

Node.removefile(n: self ref Node) : int
{
	return n.action("DELE");
}

Node.removedir(n: self ref Node) : int
{
	return n.action("RMD");
}

pwd(s: string) : string
{
	(nil, s) = str->splitl(s, "\"");
	if (s == nil || len s < 2)
		return "/";
	(s, nil) = str->splitl(s[1:len s], "\"");
	return s;
}

#
#	User info for firewall.
#
getuser()
{
	b := array[128] of byte;
	f := sys->open("/dev/user", Sys->OREAD);
	if (f != nil) {
		n := sys->read(f, b, len b);
		if (n > 0)
			myname = string b[:n];
		else if (n == 0)
			sys->print("warning: empty /dev/user\n");
		else
			sys->print("warning: could not read /dev/user: %r\n");
	} else
		sys->print("warning: could not open /dev/user: %r\n");
	f = sys->open("/dev/sysname", Sys->OREAD);
	if (f != nil) {
		n := sys->read(f, b, len b);
		if (n > 0)
			myhost = string b[:n];
		else if (n == 0)
			sys->print("warning: empty /dev/sysname\n");
		else
			sys->print("warning: could not read /dev/sysname: %r\n");
	} else
		sys->print("warning: could not open /dev/sysname: %r\n");
	if (debug)
		sys->print("proxy %s for %s@%s\n", firewall, myname, myhost);
}

server()
{
	schan : chan of ref Tmsg;
	(schan, ss) = styxlib->Styxserver.new(styxlibfd);
	for (;;) {
		t :=<- schan;
		if (t == nil) {
			if (debug)
				sys->print("ftpfs: server: exiting\n");
			kill(heartbeatpid);
			kill(controlmanagerpid);
			break;
		}
		if (debug)
			sys->print("< %s\n", styxlib->tmsg2s(t));
		pick x := t {
		Attach =>
			attachT(x);
		Clone =>
			cloneT(x);
		Clunk =>
			clunkT(x);
		Create =>
			createT(x);
		Flush =>
			flushT(x);
		Nop =>
			nopT(x);
		Open =>
			openT(x);
		Read =>
			readT(x);
		Remove =>
			removeT(x);
		Stat =>
			statT(x);
		Walk =>
			walkT(x);
		Write =>
			writeT(x);
		Wstat =>
			wstatT(x);
		* =>
			rerror(t.tag, "unimp");
		}
	}
}

raw(on: int)
{
	if(ccfd == nil) {
		ccfd = sys->open("/dev/consctl", Sys->OWRITE);
		if(ccfd == nil) {
			sys->fprint(stderr, "ftpfs: cannot open /dev/consctl: %r\n");
			return;
		}
	}
	if(on)
		sys->fprint(ccfd, "rawon");
	else
		sys->fprint(ccfd, "rawoff");
}

prompt(p: string, def: string, echo: int): string
{
	if (def == nil)
		sys->print("%s: ", p);
	else
		sys->print("%s[%s]: ", p, def);
	if (!echo)
		raw(1);
	b := bufio->fopen(stdin, Sys->OREAD);
	s := b.gets(int '\n');
	if (!echo) {
		raw(0);
		sys->print("\n");
	}
	if (len s) s = s[0:len s - 1];
	if (s == "")
		return def;
	return s;
}

#
#	Entry point.  Load modules and initiate protocol.
#

init(nil: ref Draw->Context, argv: list of string)
{
	l: string;
	rv: int;
	code: int;

	if (sys == nil)
		sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);

	time = load Daytime Daytime->PATH;
	if (time == nil) {
		sys->print("load %s failed: %r", Daytime->PATH);
		exit;
	}
	str = load String String->PATH;
	if (str == nil) {
		sys->print("load %s failed: %r", String->PATH);
		exit;
	}
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->print("load %s failed: %r", Bufio->PATH);
		exit;
	}
	styxlib = load Styxlib Styxlib->PATH;
	if (styxlib == nil) {
		sys->print("load %s failed: %r", Styxlib->PATH);
		exit;
	}

	# parse arguments
	# [-/dpq] [-m mountpoint] [-a password] host
	argv = tl argv;
	while (argv != nil) {
		s := hd argv;
		if (s[0] != '-')
			break;
		for (i := 1; i < len s; i++) {
			case s[i] {
			'd' =>
				debug++;
			'/' =>
				cdtoroot = 1;
			'p' =>
				active = 1;
			'q' =>
				quiet = 1;
			'm' =>
				argv = tl argv;
				if (argv == nil)
					usage();
				mountpoint = hd argv;
			'a' =>
				argv = tl argv;
				if (argv == nil)
					usage();
				user = "anonymous";
				password = hd argv;
			* =>
				usage();
			}
		}
		argv = tl argv;
	}

	if (len argv != 1)
		usage();
	hostname = hd argv;

	if (len hostname > 6 && hostname[:6] == "proxy!") {
		hostname = hostname[6:];
		proxy = 1;
	}
		
	if (proxy) {
		if (!quiet)
			sys->print("dial firewall service %s\n", firewall);
		(rv, ftp) = sys->dial(firewall, nil);
		if (rv < 0) {
			sys->print("dial %s failed: %r\n", firewall);
			exit;
		}
		dfid = ftp.dfd;
		getuser();
		t := sys->sprint("\ntcp!%s!tcp.21\n\n%s\n%s\n0\n-1\n-1\n", hostname, myhost, myname);
		if (debug)
			sys->print("request%s\n", t);
		b := array of byte t;
		rv = sys->write(dfid, b, len b);
		if (rv < 0) {
			sys->print("firewall write failed: %r\n");
			exit;
		}
		b = array[256] of byte;
		rv = sys->read(dfid, b, len b);
		if (rv < 0) {
			sys->print("firewall read failed: %r\n");
			return;
		}
		(c, k) := sys->tokenize(string b[:rv], "\n");
		if (c < 2) {
			sys->print("bad response from firewall\n");
			exit;
		}
		if (hd k != "0") {
			sys->print("firewall connect: %s\n", hd tl k);
			exit;
		}
		proxyid = hd tl k;
		if (debug)
			sys->print("proxyid %s\n", proxyid);
		(c, k) = sys->tokenize(proxyid, "!");
		if (c < 3) {
			sys->print("bad proxyid from firewall\n");
			exit;
		}
		proxyhost = (hd k) + "!" + (hd tl k);
		if (debug)
			sys->print("proxyhost %s\n", proxyhost);
	} else {
		d := "tcp!" + hostname + "!ftp";
		if (!quiet)
			sys->print("dial %s\n", d);
		(rv, ftp) = sys->dial(d, nil);
		if (debug)
			sys->print("localdir %s\n", ftp.dir);
		if (rv < 0) {
			sys->print("dial %s failed: %r\n", d);
			exit;
		}
		dfid = ftp.dfd;
	}
	dfidiob = bufio->fopen(dfid, sys->ORDWR);
	(net, port) = getnet(ftp.dir);		
	tbuff = array[BSZ] of byte;
	rbuff = array[BSZ] of byte;
	(rv, l) = getreply(!quiet);
	if (rv != Success)
		fail(rv, l);
	if (user == nil) {
		getuser();
		user = myname;
		user = prompt("User", user, 1);
	}
	rv = sendrequest("USER " + user, 0);
	if (rv != Success)
		sendfail(rv);
	(rv, code, l) = getfullreply(!quiet);
	if (rv != Success) {
		if (rv != Incomplete)
			fail(rv, l);
		if (code == 331) {
			if (password == nil) password = prompt("Password", nil, 0);
			rv = sendrequest2("PASS " + password, 0, "PASS XXXX");
			if (rv != Success)
				sendfail(rv);
			(rv, l) = getreply(0);
			if (rv != Success)
				fail(rv, l);
		}
	}
	if (cdtoroot) {
		rv = sendrequest("CWD /", 0);
		if (rv != Success)
			sendfail(rv);
		(rv, l) = getreply(0);
		if (rv != Success)
			fail(rv, l);
	}
	rv = sendrequest("TYPE I", 0);
	if (rv != Success)
		sendfail(rv);
	(rv, l) = getreply(0);
	if (rv != Success)
		fail(rv, l);
	rv = sendrequest("PWD", 0);
	if (rv != Success)
		sendfail(rv);
	(rv, l) = getreply(0);
	if (rv != Success)
		fail(rv, l);
	remrootpath = pwd(l);
	remroot = newnode(nil, "/");
	remroot.uniq |= Sys->CHDIR;
	remroot.dir.mode = Sys->CHDIR | 8r777;
	remdir = remroot;
	l = connect();
	if (l != nil) {
		sys->print("%s\n", l);
		exit;
	}
	grant = chan of int;
	notify = chan of int;
	spawn mount(mountpoint);
	pidc := chan of int;
	spawn controlmanager(pidc);
	controlmanagerpid = <-pidc;			
	spawn heartbeat(pidc);
	heartbeatpid = <-pidc;
	if (debug)
		sys->print("heartbeatpid %d\n", heartbeatpid);			
	spawn server();				# dies when receive on chan fails
}

kill(pid: int): int
{
	if (debug)
		sys->print("killing %d\n", pid);
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil) {
		sys->print("kill: open failed\n");
		return -1;
	}
	if (sys->write(fd, array of byte "kill", 4) != 4) {
		sys->print("kill: write failed\n");
		return -1;
	}
	return 0;
}

shutdown()
{
	mountfd = nil;
}

#
#	Styx transactions.
#

nopT(t: ref Tmsg.Nop)
{
	sendreply(ref Rmsg.Nop(t.tag));
}

flushT(t: ref Tmsg.Flush)
{
	sendreply(ref Rmsg.Flush(t.tag));
}

cloneT(t: ref Tmsg.Clone)
{
	f, n: ref Fid;

	f = getfid(t.fid);
	n = getfid(t.newfid);
	n.busy = 1;
	n.node = f.node;
	sendreply(ref Rmsg.Clone(t.tag, t.fid));
}

walkT(t: ref Tmsg.Walk)
{
	f: ref Fid;
	n: ref Node;

	f = getfid(t.fid);
	if ((f.node.uniq & Sys->CHDIR) == 0) {
		rerror(t.tag, Enotadirectory);
		return;
	}
	else if (t.name == "..")
		f.node = f.node.parent;
	else if (t.name != ".") {
		n = f.node;
		if (t.name == ".flush.ftpfs") {
			n.invalidate();
			n.readdir();
		}
		n = n.extendpath(t.name);
		if (n.parent.cached) {
			if (!n.valid) {
				rerror(t.tag, Enosuchfile);
				return;
			}
			if ((n.dir.mode & CHSYML) != 0)
				n.fixsymbolic();
		} else if (!n.valid) {
			if (n.changedir() == 0)
				n.uniq |= Sys->CHDIR;
			else
				n.uniq &= ~Sys->CHDIR;
		}
		f.node = n;
	}
	sendreply(ref Rmsg.Walk(t.tag, t.fid, f.node.qid()));
}

openT(t: ref Tmsg.Open)
{
	f: ref Fid;

	f = getfid(t.fid);
	if ((f.node.uniq & Sys->CHDIR) != 0 && t.mode != Sys->OREAD) {
		rerror(t.tag, Epermission);
		return;
	}
	if ((t.mode & Sys->OTRUNC) != 0) {
		f.node.uncache();
		f.node.parent.uncache();
		f.node.filedirty();
	} else if (!f.node.cached) {
		f.node.filefree();
		if ((f.node.uniq & Sys->CHDIR) != 0) {
			f.node.invalidate();
			if (f.node.readdir() < 0) {
				rerror(t.tag, Enosuchfile);
				return;
			}
		}
		else {
			if (f.node.readfile() < 0) {
				rerror(t.tag, errstr);
				return;
			}
		}
		f.node.markcached();
	}
	sendreply(ref Rmsg.Open(t.tag, t.fid, f.node.qid()));
}

createT(t: ref Tmsg.Create)
{
	f: ref Fid;

	f = getfid(t.fid);
	if ((f.node.uniq & Sys->CHDIR) == 0) {
		rerror(t.tag, Enotadirectory);
		return;
	}
	f.node = f.node.extendpath(t.name);
	f.node.uncache();
	if ((t.perm & Sys->CHDIR) != 0) {
		if (f.node.createdir() < 0) {
			rerror(t.tag, Epermission);
			return;
		}
	}
	else
		f.node.filedirty();
	f.node.parent.invalidate();
	f.node.parent.uncache();
	sendreply(ref Rmsg.Create(t.tag, t.fid, f.node.qid()));
}

readT(t: ref Tmsg.Read)
{
	f: ref Fid;
	p: ref Node;
	rv: int;
	count: int;

	f = getfid(t.fid);
	count = t.count;

	if (count > Sys->ATOMICIO)
		count = Sys->ATOMICIO;
	if ((f.node.uniq & Sys->CHDIR) != 0) {
		rv = 0;
		if (((int t.offset) % Styxlib->DIRLEN) != 0) {
			rerror(t.tag, Ebadoffset);
			return;
		}
		if (count < Styxlib->DIRLEN) {
			rerror(t.tag, Ebadlength);
			return;
		}
		n := int t.offset / Styxlib->DIRLEN;
		for (p = f.node.children; n > 0 && p != nil; p = p.sibs)
			if (p.valid)
				n--;
		if (n == 0) {
			n = count / Styxlib->DIRLEN;
			for (; n > 0 && p != nil; p = p.sibs) {
				if (p.valid) {
					if ((p.dir.mode & CHSYML) != 0)
						p.fixsymbolic();
					p.convD2M(rv);
					rv += Styxlib->DIRLEN;
					n--;
				}
			}
		}
	}
	else {
		if (!f.node.cached && f.node.readfile() < 0) {
			rerror(t.tag, errstr);
			return;
		}
		f.node.markcached();
		rv = f.node.fileread(tbuff, int t.offset, count);
		if (rv < 0) {
			rerror(t.tag, errstr);
			return;
		}
	}
	sendreply(ref Rmsg.Read(t.tag, t.fid, tbuff[0:rv]));
}

writeT(t: ref Tmsg.Write)
{
	f: ref Fid;

	f = getfid(t.fid);
	if ((f.node.uniq & Sys->CHDIR) != 0) {
		rerror(t.tag, Eisadirectory);
		return;
	}
	count := f.node.filewrite(t.data, int t.offset, len t.data);
	if (count < 0) {
		rerror(t.tag, errstr);
		return;
	}
	f.node.filedirty();
	sendreply(ref Rmsg.Write(t.tag, t.fid, count));
}

clunkT(t: ref Tmsg.Clunk)
{
	f: ref Fid;

	f = getfid(t.fid);
	if (f.node.fileisdirty()) {
		if (f.node.createfile() < 0)
			sys->print("ftpfs: could not create %s\n", f.node.pathname());
		f.node.fileclean();
		f.node.uncache();
	}
	f.busy = 0;
	sendreply(ref Rmsg.Clunk(t.tag, t.fid));
}

removeT(t: ref Tmsg.Remove)
{
	f: ref Fid;

	f = getfid(t.fid);
	if ((f.node.uniq & Sys->CHDIR) != 0) {
		if (f.node.removedir() < 0) {
			rerror(t.tag, errstr);
			return;
		}
	}
	else {
		if (f.node.removefile() < 0) {
			rerror(t.tag, errstr);
			return;
		}
	}
	f.node.parent.uncache();
	f.node.uncache();
	f.node.valid = 0;
	f.busy = 0;
	sendreply(ref Rmsg.Remove(t.tag, t.fid));
}

statT(t: ref Tmsg.Stat)
{
	f: ref Fid;
	n: ref Node;

	f = getfid(t.fid);
	n = f.node.parent;
	if (!n.cached) {
		n.invalidate();
		n.readdir();
		n.markcached();
	}
	if (!f.node.valid) {
		rerror(t.tag, Enosuchfile);
		return;
	}
	sendreply(ref Rmsg.Stat(t.tag, t.fid, f.node.dir));
}

wstatT(t: ref Tmsg.Wstat)
{
	rerror(t.tag, Enowstat);
}

attachT(t: ref Tmsg.Attach)
{
	f: ref Fid;

	f = getfid(t.fid);
	f.busy = 1;
	f.node = remroot;
	sendreply(ref Rmsg.Attach(t.tag, t.fid, remroot.qid()));
}
