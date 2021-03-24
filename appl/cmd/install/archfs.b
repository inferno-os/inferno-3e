implement Archfs;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
include "arg.m";
	arg : Arg;
include "string.m";
	str : String;
include "daytime.m";
	daytime : Daytime;
include "styxlib.m";
	styx : Styxlib;
include "archfs.m";
include "arch.m";
	arch : Arch;

# add write some day

Iobuf : import bufio;
DIRLEN, Tmsg, Rmsg, Chan, Styxserver, convD2M : import styx;
Einuse, Ebadfid, Eopen, Enotfound, Enotdir, Eperm, Ebadarg, Eexists : import Styxlib;

UID : con "inferno";
GID : con "inf";

Dir : adt {
	dir : Sys->Dir;
	offset : int;
	parent : cyclic ref Dir;
	child : cyclic ref Dir;
	sibling : cyclic ref Dir;
	next : cyclic ref Dir;		# hash table link
};

HTSZ : con 32;
hashtab := array[HTSZ] of ref Dir;

root : ref Dir;
qid : int;
mtpt := "/mnt";
bio : ref Iobuf;
buf : array of byte;
skip := 0;

# Archfs : module
# {
# 	init : fn(ctxt : ref Draw->Context, args : list of string);
# };

init(nil : ref Draw->Context, args : list of string)
{
	init0(nil, args, nil);
}

initc(args : list of string, c : chan of int)
{
	init0(nil, args, c);
}

chanint : chan of int;

init0(nil : ref Draw->Context, args : list of string, chi : chan of int)
{
	chanint = chi;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	bufio->init();
	arg = load Arg Arg->PATH;
	str = load String String->PATH;
	daytime = load Daytime Daytime->PATH;
	styx = load Styxlib Styxlib->PATH;
	arch = load Arch Arch->PATH;
	if (bufio == nil || arg == nil || styx == nil || arch == nil)
		fatal("failed to load modules", 1);
	arch->init(nil, nil);
	arg->init(args);
	while ((c := arg->opt()) != 0) {
		case c {
			'm' =>
				mtpt = arg->arg();
				if (mtpt == nil)
					fatal("mount point missing", 1);
			's' =>
				skip = 1;
		}
	}
	args = arg->argv();
	if (args == nil)
		fatal("missing archive file", 1);
	buf = array[Sys->ATOMICIO] of byte;
	# root = newdir("/", UID, GID, 8r755|Sys->CHDIR, daytime->now());
	root = newdir(basename(mtpt), UID, GID, 8r755|Sys->CHDIR, daytime->now());
	root.parent = root;
	readarch(hd args, tl args);
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		fatal("can't create pipe", 1);
	(ch, s) := Styxserver.new(p[1]);
	p[1] = nil;
	pidch := chan of int;
	spawn serve(ch, s, pidch);
	pid := <- pidch;
	if(sys->mount(p[0], mtpt, Sys->MREPL, nil) < 0)
		fatal("cannot mount archive", 1);
	p[0] = nil;
	if (chi != nil) {
		chi <-= pid;
		chanint = nil;
	}
}

serve(ch : chan of ref Tmsg, s : ref Styxserver, pidch : chan of int)
{
	e : string;
	c : ref Chan;
	f, d : ref Dir;

	pidch <-= sys->pctl(0, nil);
	for (;;) {
		m0 := <- ch;
		if (m0 == nil)
			return;
# sys->fprint(sys->fildes(2), "%s\n", styx->tmsg2s(m0));
		pick m := m0 {
			Readerror =>
				fatal("read error on styx server", 1);
			Nop =>
				devnop(s, m);
			Flush =>
				s.devflush(m);
			Clone =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				s.devclone(m);
			Walk =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				if ((d.dir.mode & Sys->CHDIR) == 0) {
					deverror(s, m.tag, Enotdir);
					continue;
				}
				f = lookup(d, m.name);
				if (f == nil) {
					deverror(s, m.tag, Enotfound);
					continue;
				}
				c.qid = f.dir.qid;
				c.path = f.dir.name;
				s.reply(ref Rmsg.Walk(m.tag, m.fid, c.qid));
			Open =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				if (m.mode & (Sys->OWRITE|Sys->ORDWR|Sys->OTRUNC|Sys->ORCLOSE)) {
					deverror(s, m.tag, Eperm);
					continue;
				}
				c.qid.vers = d.dir.qid.vers;
				c.open = 1;
				c.mode = m.mode;
				s.reply(ref Rmsg.Open(m.tag, m.fid, c.qid));
			Create =>
				deverror(s, m.tag, Eperm);
			Read =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				data := readdir(d, int m.offset, m.count);
				s.reply(ref Rmsg.Read(m.tag, m.fid, data));
			Write =>
				deverror(s, m.tag, Eperm);				
			Clunk =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				s.chanfree(c);
				s.reply(ref Rmsg.Clunk(m.tag, m.fid));
			Stat =>
				(c, d, e) = mapfid(s, m.fid);
				if (e != nil) {
					deverror(s, m.tag, e);
					continue;
				}
				s.reply(ref Rmsg.Stat(m.tag, m.fid, d.dir));
			Remove =>
				deverror(s, m.tag, Eperm);
			Wstat =>
				deverror(s, m.tag, Eperm);
			Attach =>
				c = s.newchan(m.fid);
				if (c == nil) {
					deverror(s, m.tag, Einuse);
					continue;
				}
				c.uname = m.uname;
				c.qid.path = root.dir.qid.path;
				c.path = "arch";
				s.reply(ref Rmsg.Attach(m.tag, m.fid, c.qid));
		}
	}
}

mapfid(s : ref Styxserver, fid : int) : (ref Chan, ref Dir, string)
{
	c := s.fidtochan(fid);
	if (c == nil)
		return (nil, nil, Ebadfid);
	d := mapqid(root, c.qid.path);
	if (d == nil)
		return (nil, nil, Enotfound);
	return (c, d, nil);
}

mapqid(d : ref Dir, qidp : int) : ref Dir
{
	d = nil;
	hv := hashval(qidp);
	for (htd := hashtab[hv]; htd != nil; htd = htd.next)
		if (htd.dir.qid.path == qidp)
			return htd;
	# if (d.dir.qid.path == qidp)
	#	return d;
	# for (s := d.child; s != nil; s = s.sibling)
	#	if ((t := mapqid(s, qidp)) != nil)
	#		return t;
	return nil;
}

hashval(n : int) : int
{
	return (n & ~Sys->CHDIR)%HTSZ;
}

hashadd(d : ref Dir)
{
	hv := hashval(d.dir.qid.path);
	d.next = hashtab[hv];
	hashtab[hv] = d;
}

devnop(s : ref Styxserver, m : ref Tmsg.Nop)
{
	s.reply(ref Rmsg.Nop(m.tag));
}

deverror(s : ref Styxserver, tag : int, e : string)
{
	s.reply(ref Rmsg.Error(tag, e));
}

readarch(f : string, args : list of string)
{
	ar := arch->openarchfs(f);
	if(ar == nil || ar.b == nil)
		fatal(sys->sprint("cannot open %s(%r)\n", f), 1);
	bio = ar.b;
	while ((a := arch->gethdr(ar)) != nil) {
		if (args != nil) {
			if (!selected(a.name, args)) {
				if (skip)
					return;
				arch->drain(ar, a.d.length);
				continue;
			}
			mkdirs("/", a.name);
		}
		d := mkdir(a.name, a.d.mode, a.d.mtime, a.d.uid, a.d.gid, 0);
		if((a.d.mode & Sys->CHDIR) == 0) {
			d.dir.length = a.d.length;
			d.offset = bio.offset();
		}
		arch->drain(ar, a.d.length);
	}
	if (ar.err != nil)
		fatal(ar.err, 0);
}

selected(s: string, args: list of string): int
{
	for(; args != nil; args = tl args)
		if(fileprefix(hd args, s))
			return 1;
	return 0;
}

fileprefix(prefix, s: string): int
{
	n := len prefix;
	m := len s;
	if(n > m || !str->prefix(prefix, s))
		return 0;
	if(m > n && s[n] != '/')
		return 0;
	return 1;
}

basename(f : string) : string
{
	for (i := len f; i > 0; ) 
		if (f[--i] == '/')
			return f[i+1:];
	return f;
}

split(p : string) : (string, string)
{
	if (p == nil)
		fatal("nil string in split", 1);
	if (p[0] != '/')
		fatal("p0 not / in split", 1);
	while (p[0] == '/')
		p = p[1:];
	i := 0;
	while (i < len p && p[i] != '/')
		i++;
	if (i == len p)
		return (p, nil);
	else
		return (p[0:i], p[i:]);
}

mkdirs(basedir, name: string)
{
	(nil, names) := sys->tokenize(name, "/");
	while(names != nil) {
		# sys->print("mkdir %s\n", basedir);
		mkdir(basedir, 8r775|Sys->CHDIR, daytime->now(), UID, GID, 1);
		if(tl names == nil)
			break;
		basedir = basedir + "/" + hd names;
		names = tl names;
	}
}

readdir(d : ref Dir, offset : int, n : int) : array of byte
{
	if (d.dir.mode & Sys->CHDIR)
		return readd(d, offset, n);
	else
		return readf(d, offset, n);
}
	
readd(d : ref Dir, offset : int, n : int) : array of byte
{
	t : ref Dir;

	offset /= DIRLEN;
	n /= DIRLEN;
	m := 0;
	for (s := d.child; s != nil; s = s.sibling) {
		if (offset-- == 0)
			t = s;
		if (t != nil)
			m++;
	}
	if (m < n)
		n = m;
	data := array[n*DIRLEN] of byte;
	p := 0;
	for (s = t; s != nil && n > 0; s = s.sibling) {
		convD2M(data[p:p+DIRLEN], s.dir);
		p += DIRLEN;
		n--;
	}
	return data;
}

readf(d : ref Dir, offset : int, n : int) : array of byte
{
	leng := d.dir.length;
	if (offset+n > leng)
		n = leng-offset;
	if (n <= 0 || offset < 0)
		return nil;
	bio.seek(d.offset+offset, Bufio->SEEKSTART);
	a := array[n] of byte;
	p := 0;
	m := 0;
	for ( ; n != 0; n -= m) {
		l := len buf;
		if (n < l)
			l = n;
		m = bio.read(buf, l);
		if (m <= 0 || m != l)
			fatal("premature eof", 1);
		a[p:] = buf[0:m];
		p += m;
	}
	return a;
}

mkdir(f : string, mode : int, mtime : int, uid : string, gid : string, existsok : int) : ref Dir
{
	if (f == "/")
		return nil;
	d := newdir(basename(f), uid, gid, mode, mtime);
	addfile(d, f, existsok);
	return d;
}

addfile(d : ref Dir, path : string, existsok : int)
{
	elem : string;

	opath := path;
	p := prev := root;
	basedir := "";
# sys->print("addfile %s : %s\n", d.dir.name, path);
	while (path != nil) {
		(elem, path) = split(path);
		basedir += "/" + elem;
		op := p;
		p = lookup(p, elem);
		if (path == nil) {
			if (p != nil) {
				if (!existsok && (p.dir.mode&Sys->CHDIR) == 0)
					sys->fprint(sys->fildes(2), "addfile: %s already there", opath);
					# fatal(sys->sprint("addfile: %s already there", opath), 1);
				return;
			}
			if (prev.child == nil)
				prev.child = d;
			else {
				for (s := prev.child; s.sibling != nil; s = s.sibling)
					;
				s.sibling = d;
			}
			d.parent = prev;
		}
		else {
			if (p == nil) {
				mkdir(basedir, 8r775|Sys->CHDIR, daytime->now(), UID, GID, 1);
				p = lookup(op, elem);
				if (p == nil)
					fatal("bad file system", 1);
			}
		}
		prev = p;
	}
}

lookup(p : ref Dir, f : string) : ref Dir
{
	if ((p.dir.mode&Sys->CHDIR) == 0) 
		fatal("not a directory in lookup", 1);
	if (f == ".")
		return p;
	if (f == "..")
		return p.parent;
	for (d := p.child; d != nil; d = d.sibling)
		if (d.dir.name == f)
			return d;
	return nil;
}

newdir(name, uid, gid : string, mode, mtime : int) : ref Dir
{
	dir : Sys->Dir;

	dir.name = name;
	dir.uid = uid;
	dir.gid = gid;
	dir.qid.path = qid++;
	dir.qid.path |= (mode&Sys->CHDIR);
	dir.qid.vers = 0;
	dir.mode = mode;
	dir.atime = dir.mtime = mtime;
	dir.length = 0;
	dir.dtype = 'X';
	dir.dev = 0;

	d := ref Dir;
	d.dir = dir;
	d.offset = 0;
	hashadd(d);
	return d;
}

# pr(d : ref Dir)
# {
#	dir := d.dir;
#	sys->print("%s %s %s %x %x %x %d %d %d %d %d %d\n",
#		dir.name, dir.uid, dir.gid, dir.qid.path, dir.qid.vers, dir.mode, dir.atime, dir.mtime, dir.length, dir.dtype, dir.dev, d.offset);
# }

fatal(e : string, pr: int)
{
	if(pr){
		sys->fprint(sys->fildes(2), "fatal: %s\n", e);
		if (chanint != nil)
			chanint <-= -1;
	}
	else{
		# probably not an archive file
		if (chanint != nil)
			chanint <-= -2;
	}
	exit;
}
