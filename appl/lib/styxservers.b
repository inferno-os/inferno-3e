implement Styxservers;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

#
#	Modified by Martin C. Atkins, 2001/2002 to add new rdev*
#	helper functions
#	Then modified to remove Dirgenmod, and it's helpers, and
#	to rename rdev* to dev*
#
#	Still-unresolved issues:
#		group identity/access checking
#		atime and mtime emulation
#		What is the correct behaviour for qid.vers?
#

include "sys.m";
	sys: Sys;
include "styx.m";
	styx: Styx;
	DIRLEN, Tmsg, Rmsg: import styx;
include "styxservers.m";

OEXEC: con 3;				# Surely this should be in Sys with OREAD, etc?
CHANHASHSIZE: con 32;
DEBUG: con 0;

init()
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if (styx == nil) {
		sys->fprint(sys->fildes(2), "styxservers: cannot load %s: %r\n", Styx->PATH);
		sys->raise("fail:bad module");
	}
	styx->init();
}

Styxserver.new(fd: ref Sys->FD, t: ref Filetree, rootqid: Qidpath): (chan of ref Tmsg, ref Styxserver)
{
	tchan := chan of ref Tmsg;
	srv := ref Styxserver(fd, array[CHANHASHSIZE] of list of ref Chan, t, rootqid);

	sync := chan of int;
	spawn tmsgreader(fd, tchan, sync);
	<-sync;
	return (tchan, srv);
}

tmsgreader(fd: ref Sys->FD, tchan: chan of ref Tmsg, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	m: ref Tmsg;
	do {
		m = Tmsg.read(fd, 0);
		tchan <-= m;
	} while (m != nil && tagof(m) != tagof(Tmsg.Readerror));
}

Styxserver.reply(srv: self ref Styxserver, m: ref Rmsg): int
{
	d := m.pack();
	return sys->write(srv.fd, d, len d);
}

Styxserver.attach(srv: self ref Styxserver, m: ref Tmsg.Attach): ref Chan
{
	c := srv.newchan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Einuse));
		return nil;
	}
	c.uname = m.uname;
	c.param = m.aname;
	c.qid = srv.rootqid;
	srv.reply(ref Rmsg.Attach(m.tag, m.fid, (c.qid, 0)));
	return c;
}

Styxserver.clone(srv: self ref Styxserver, m: ref Tmsg.Clone): ref Chan
{
	oc := srv.fidtochan(m.fid);
	if (oc == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if (oc.open) {
		srv.reply(ref Rmsg.Error(m.tag, Eopen));
		return nil;
	}
	c := srv.newchan(m.newfid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Einuse));
		return nil;
	}
	c.qid = oc.qid;
	c.uname  = oc.uname;
	c.param = oc.param;
	c.open = oc.open;
	c.mode = oc.mode;
	c.data = oc.data;
	srv.reply(ref Rmsg.Clone(m.tag, m.fid));
	return c;
}

Styxserver.walk(srv: self ref Styxserver, m: ref Tmsg.Walk): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if (!c.isdir()) {
		srv.reply(ref Rmsg.Error(m.tag, Enotdir));
		return nil;
	}
	(dir, err) := srv.t.find(c.qid);
	if(dir == nil) {
		srv.reply(ref Rmsg.Error(m.tag, err));
		return nil;
	}
	if (!openok(c.uname, OEXEC, dir.mode, dir.uid, dir.gid)) {
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}
	f: ref Sys->Dir;
	(f, err) = srv.t.walk(dir.qid.path, m.name);
	if (f == nil) {
		srv.reply(ref Rmsg.Error(m.tag, err));
		return nil;
	}
	c.qid = f.qid.path;
	srv.reply(ref Rmsg.Walk(m.tag, m.fid, f.qid));
	return c;
}

Styxserver.open(srv: self ref Styxserver, m: ref Tmsg.Open): ref Chan
{
	c := srv.fidtochan(m.fid);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if (c.open) {
		srv.reply(ref Rmsg.Error(m.tag, Eopen));
		return nil;
	}
	(f, err) := srv.t.find(c.qid);
	if(f == nil) {
		srv.reply(ref Rmsg.Error(m.tag, err));
		return nil;
	}
	if (!openok(c.uname, m.mode, f.mode, f.uid, f.gid)) {
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}
	mode := openmode(m.mode);
	if (mode == -1) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
		return nil;
	}
	c.mode = mode;
	if(m.mode & Sys->ORCLOSE) {
		(dir, nil) := srv.t.walk(c.qid, "..");
		if(!openok(c.uname, Sys->OWRITE, dir.mode, dir.uid, dir.gid)) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
		c.mode |= Sys->ORCLOSE;
	}
	c.open = 1;
	srv.reply(ref Rmsg.Open(m.tag, m.fid, f.qid));
	return c;
}

invalidreadmodes := array[] of {0,1,0,1};

Styxserver.read(srv: self ref Styxserver, m: ref Tmsg.Read): ref Chan
{
	c := srv.fidtochan(m.fid);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if(!c.open) {
		srv.reply(ref Rmsg.Error(m.tag, "not open"));
		return nil;
	}
	if (!c.isdir()) {
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}
	if(invalidreadmodes[c.mode&3]) {	# non-readable modes
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}

	srv.reply(ref Rmsg.Read(m.tag, m.fid, srv.t.readdir(c.qid, int (m.offset / big DIRLEN), m.count / DIRLEN)));
	return c;
}

invalidwritemodes := array[] of {1,0,1,1};

Styxserver.stat(srv: self ref Styxserver, m: ref Tmsg.Stat)
{
	c := srv.fidtochan(m.fid);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return;
	}
	(d, err) := srv.t.find(c.qid);
	if (d == nil) {
		srv.reply(ref Rmsg.Error(m.tag, err));
		return;
	}
	srv.reply(ref Rmsg.Stat(m.tag, m.fid, *d));
}

Styxserver.remove(srv: self ref Styxserver, m: ref Tmsg.Remove): ref Chan
{
	c := srv.fidtochan(m.fid);
	if(c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	srv.chanfree(c);			# Remove always clunks the fid
	srv.reply(ref Rmsg.Error(m.tag, Eperm));
	return c;	
}

Styxserver.clunk(srv: self ref Styxserver, m: ref Tmsg.Clunk): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}

	srv.chanfree(c);
	srv.reply(ref Rmsg.Clunk(m.tag, m.fid));
	return c;
}

Styxserver.default(srv: self ref Styxserver, gm: ref Tmsg)
{
	if (gm == nil) {
		srv.t.c <-= nil;
		exit;
	}
	pick m := gm {
	Readerror =>
		srv.t.c <-= nil;
		exit;
	Nop =>
		srv.reply(ref Rmsg.Nop(m.tag));
	Flush =>
		srv.reply(ref Rmsg.Flush(m.tag));
	Clone =>
		srv.clone(m);
	Walk =>
		srv.walk(m);
	Open =>
		srv.open(m);
	Create =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Read =>
		srv.read(m);
	Write =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Clunk =>
		srv.clunk(m);
		# to delete on ORCLOSE:
		# c := srv.clunk(m);
		# if(c != nil && c.mode & Sys->ORCLOSE)
		# 	srv.doremove(c);
	Stat =>
		srv.stat(m);
	Remove =>
		srv.remove(m);
	Wstat =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Attach =>
		srv.attach(m);
	* =>
		sys->fprint(sys->fildes(2), "styxservers: unhandled Tmsg read case - should not happen\n");
		sys->raise("fail: unhandled case");
	}
}

Styxserver.cancreate(srv: self ref Styxserver, m: ref Tmsg.Create): (ref Chan, int, string)
{
	c := srv.fidtochan(m.fid);
	if(c == nil)
		return (nil, 0, Ebadfid);
	if (c.open)
		return (nil, 0, Eopen);
	(d, err) := srv.t.find(c.qid);
	if(d == nil)
		return (nil, 0, err);
	if ((d.mode & Sys->CHDIR) == 0)
		return (nil, 0, Enotdir);
	if (m.name == "." || m.name == "..")
		return (nil, 0, Eexists);
	if(!openok(c.uname, Sys->OWRITE, d.mode, d.uid, d.gid))
		return (nil, 0, Eperm);
	if (srv.t.walk(d.qid.path, m.name).t0 != nil)
		return (nil, 0, Eexists);
	if((c.mode = openmode(m.mode)) == -1)
		return (nil, 0, Ebadarg);
	if(m.mode & Sys->ORCLOSE)	# can create, so must be able to delete!
		c.mode |= Sys->ORCLOSE;

	perm: int;
	if(m.perm & Sys->CHDIR)
		perm = Sys->CHDIR | (m.perm & ~8r777 & ~Sys->CHDIR) | (d.mode & m.perm & 8r777);
	else
		perm = (m.perm & (~8r777|8r111) ) | (d.mode & m.perm & 8r666);
	return (c, perm, nil);
}

Styxserver.canwrite(srv: self ref Styxserver, m: ref Tmsg.Write): (ref Chan, string)
{
	c := srv.fidtochan(m.fid);
	if (c == nil)
		return (nil, Ebadfid);
	if (!c.open)
		return (nil, Ebadfid);
	if (invalidwritemodes[c.mode&3])	# non-writable modes
		return (nil, Eperm);
	if (c.isdir())
		return (nil, Eperm);
	(d, err) := srv.t.find(c.qid);
	if (d == nil)
		return (nil, err);
	if (!openok(c.uname, Sys->OWRITE, d.mode, d.uid, d.gid))
		return (nil, Eperm);
	return (c, nil);
}

Styxserver.fidtochan(srv: self ref Styxserver, fid: int): ref Chan
{
	for (l := srv.chans[fid & (CHANHASHSIZE-1)]; l != nil; l = tl l)
		if ((hd l).fid == fid)
			return hd l;
	return nil;
}

Styxserver.chanfree(srv: self ref Styxserver, c: ref Chan)
{
	slot := c.fid & (CHANHASHSIZE-1);
	nl: list of ref Chan;
	for (l := srv.chans[slot]; l != nil; l = tl l)
		if ((hd l).fid != c.fid)
			nl = (hd l) :: nl;
	srv.chans[slot] = nl;
}

Styxserver.chanlist(srv: self ref Styxserver): list of ref Chan
{
	cl: list of ref Chan;
	for (i := 0; i < len srv.chans; i++)
		for (l := srv.chans[i]; l != nil; l = tl l)
			cl = hd l :: cl;
	return cl;
}

Styxserver.newchan(srv: self ref Styxserver, fid: int): ref Chan
{
	# fid already in use
	if ((c := srv.fidtochan(fid)) != nil)
		return nil;
	c = ref Chan;
	c.qid = -1;
	c.open = 0;
	c.mode = 0;
	c.fid = fid;
	slot := fid & (CHANHASHSIZE-1);
	srv.chans[slot] = c :: srv.chans[slot];
	return c;
}

readbytes(m: ref Tmsg.Read, d: array of byte): ref Rmsg.Read
{
	r := ref Rmsg.Read(m.tag, m.fid, nil);
	if (m.offset >= big len d || m.offset < big 0)
		return r;
	offset := int m.offset;
	e := offset + m.count;
	if (e > len d)
		e = len d;
	r.data = d[offset:e];
	return r;
}

Filetree.new(c: chan of ref Treeop): ref Filetree
{
	return ref Filetree(c, chan of (ref Sys->Dir, string));
}

Filetree.find(t: self ref Filetree, q: Qidpath): (ref Sys->Dir, string)
{
	t.c <-= ref Treeop.Find(t.reply, q);
	return <-t.reply;
}

Filetree.walk(t: self ref Filetree, q: Qidpath, name: string): (ref Sys->Dir, string)
{
	t.c <-= ref Treeop.Walk(t.reply, q, name);
	return <-t.reply;
}

Filetree.readdir(t: self ref Filetree, q: Qidpath, offset, count: int): array of byte
{
	a := array[count * DIRLEN] of byte;
	t.c <-= ref Treeop.Readdir(t.reply, q, offset, count);
	i := 0;
	b := a;
	while ((d := (<-t.reply).t0) != nil) {
		if (i < count) {
			data := styx->packdir(*d);
			b[0:] = data;
			b = b[len data:];
			i++;
		}
	}

	return a[0:i * DIRLEN];
}

openmode(o: int): int
{
	OTRUNC, ORCLOSE, OREAD, ORDWR: import Sys;
	if(o >= (OTRUNC|ORCLOSE|ORDWR))
		return -1;
	o &= ~(OTRUNC|ORCLOSE);
	if(o > ORDWR)
		return -1;
	return o;
}

access := array[] of {8r400, 8r200, 8r600, 8r100};
openok(uname: string, omode: int, perm: int, funame, nil: string): int
{
	if ((perm & Sys->CHDIR) && (omode & Sys->OTRUNC))
		return 0;

	# XXX what should we do about groups?
	# this is inadequate anyway:
	# user should be allowed to open it if permission
	# is allowed to others.
	mode: int;
	if (uname == funame)
		mode = perm;
	else
		mode = perm << 6;

	if(omode & Sys->OTRUNC) {
		t := access[Sys->OWRITE];
		if((t & mode) != t)
			return 0;
	}

	t := access[omode & 3];
	return ((t & mode) == t);
}	

Chan.isdir(c: self ref Chan): int
{
	return (c.qid & Sys->CHDIR) != 0;
}
