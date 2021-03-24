implement Styxlib;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "styxlib.m";

CHANHASHSIZE: con 32;
starttime: int;
timefd: ref Sys->FD;

DEBUG: con 0;

Styxserver.new(fd: ref Sys->FD): (chan of ref Tmsg, ref Styxserver)
{
	if (sys == nil)
		sys = load Sys Sys->PATH;

	starttime = now();
	tchan := chan of ref Tmsg;
	srv := ref Styxserver(fd, array[CHANHASHSIZE] of list of ref Chan, getuname());

	sync := chan of int;
	spawn tmsgreader(fd, tchan, sync);
	<-sync;
	return (tchan, srv);
}

now(): int
{
	if(timefd == nil){
		timefd = sys->open("/dev/time", sys->OREAD);
		if(timefd == nil)
			return 0;
	}
	buf := array[128] of byte;
	sys->seek(timefd, 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;

	t := (big string buf[0:n]) / big 1000000;
	return int t;
}


getuname(): string
{
	if ((fd := sys->open("/dev/user", Sys->OREAD)) == nil)
		return "unknown";
	buf := array[Sys->NAMELEN] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return "unknown";
	return string buf[0:n];
}

tmsgreader(fd: ref Sys->FD, tchan: chan of ref Tmsg, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->NEWNS, fd.fd :: nil);
	sync <-= 1;
	fd = sys->fildes(fd.fd);
	data := array[MAXRPC] of byte;
	sofar := 0;
	for (;;) {
		n := sys->read(fd, data[sofar:], len data - sofar);
		if (n <= 0) {
			m: ref Tmsg = nil;
			if (n < 0)
				m = ref Tmsg.Readerror(-1, sys->sprint("%r"));
			tchan <-= m;
			return;
		}
		sofar += n;
		(cn, m) := d2tmsg(data[0:sofar]);
		if (cn == -1) {
			# on msg format error, flush any data and
			# hope it'll be alright in the future.
			sofar = 0;
		} else if (cn > 0) {
			# if it's a write message, then the buffer is used in
			# the message, so allocate another one to avoid
			# aliasing.
			if (tagof(m) == tagof(Tmsg.Write)) {
				ndata := array[MAXRPC] of byte;
				ndata[0:] = data[cn:sofar];
				data = ndata;
			} else
				data[0:] = data[cn:sofar];
			sofar -= cn;
			tchan <-= m;
			m = nil;
		}
	}
}

Styxserver.reply(srv: self ref Styxserver, m: ref Rmsg): int
{
	d := array[MAXRPC] of byte;
	if (DEBUG) 
		sys->fprint(sys->fildes(2), "%s\n", rmsg2s(m));
	n := rmsg2d(m, d);
	return sys->write(srv.fd, d, n);
}

Styxserver.devattach(srv: self ref Styxserver, m: ref Tmsg.Attach): ref Chan
{
	c := srv.newchan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Einuse));
		return nil;
	}
	c.uname = m.uname;
	c.qid.path = Sys->CHDIR;
	c.path = "dev";
	srv.reply(ref Rmsg.Attach(m.tag, m.fid, c.qid));
	return c;
}

Styxserver.devclone(srv: self ref Styxserver, m: ref Tmsg.Clone): ref Chan
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
	c.open = oc.open;
	c.mode = oc.mode;
	c.path = oc.path;
	c.data = oc.data;
	srv.reply(ref Rmsg.Clone(m.tag, m.fid));
	return c;
}

Styxserver.devflush(srv: self ref Styxserver, m: ref Tmsg.Flush)
{
	srv.reply(ref Rmsg.Flush(m.tag));
}

Styxserver.devwalk(srv: self ref Styxserver, m: ref Tmsg.Walk,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan
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
	# should check permissions here?
	i := 0;
	(ok, d) := gen->dirgen(srv, c, tab, i++);
	while (ok >= 0) {
		if (ok > 0 && d.name == m.name) {
			c.qid = d.qid;
			c.path = d.name;
			srv.reply(ref Rmsg.Walk(m.tag, m.fid, c.qid));
			return c;
		}
		(ok, d) = gen->dirgen(srv, c, tab, i++);
	}
	srv.reply(ref Rmsg.Error(m.tag, Enotfound));
	return nil;
}

Styxserver.devclunk(srv: self ref Styxserver, m: ref Tmsg.Clunk): ref Chan
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

Styxserver.devstat(srv: self ref Styxserver, m: ref Tmsg.Stat,
							gen: Dirgenmod, tab: array of Dirtab)
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return;
	}
	i := 0;
	(ok, d) := gen->dirgen(srv, c, tab, i++);
	while (ok >= 0) {
		if (ok > 0 && c.qid.path == d.qid.path) {
			srv.reply(ref Rmsg.Stat(m.tag, m.fid, d));
			return;
		}
		(ok, d) = gen->dirgen(srv, c, tab, i++);
	}
	# auto-generate entry for directory if not found.
	# XXX this is asking for trouble, as the permissions given
	# on stat() of a directory can be different from those given
	# when reading the directory's entry in its parent dir.
	if (c.qid.path & Sys->CHDIR)
		srv.reply(ref Rmsg.Stat(m.tag, m.fid, devdir(c, c.qid, c.path, big(i * DIRLEN), srv.uname, Sys->CHDIR|8r555)));
	else
		srv.reply(ref Rmsg.Error(m.tag, Enotfound));
}

Styxserver.devdirread(srv: self ref Styxserver, m: ref Tmsg.Read,
							gen: Dirgenmod, tab: array of Dirtab)
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return;
	}
	data := array[m.count] of byte;
	k := int m.offset / DIRLEN;
	for (n := 0; n + DIRLEN <= m.count; k++) {
		(ok, d) := gen->dirgen(srv, c, tab, k);
		case ok {
		-1 =>
			srv.reply(ref Rmsg.Read(m.tag, m.fid, data[0:n]));
			return;
		1 =>
			convD2M(data[n:], d);
			n += DIRLEN;
		}
	}
	srv.reply(ref Rmsg.Read(m.tag, m.fid, data[0:n]));
}

Styxserver.devopen(srv: self ref Styxserver, m: ref Tmsg.Open,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	omode := m.mode;
	i := 0;
	(ok, d) := gen->dirgen(srv, c, tab, i++);
	while (ok >= 0) {
		# XXX dev.c checks vers as well... is that desirable?
		if (ok > 0 && c.qid.path == d.qid.path) {
			if (openok(omode, d.mode, c.uname, d.uid, d.gid)) {
				c.qid.vers = d.qid.vers;
				break;
			}
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
		(ok, d) = gen->dirgen(srv, c, tab, i++);
	}
	if ((c.qid.path & Sys->CHDIR) && omode != Sys->OREAD) {
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
		return nil;
	}
	if ((c.mode = openmode(omode)) == -1) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadarg));
		return nil;
	}
	c.open = 1;
	c.mode = omode;
	srv.reply(ref Rmsg.Open(m.tag, m.fid, c.qid));
	return c;
}

Styxserver.devremove(srv: self ref Styxserver, m: ref Tmsg.Remove): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	srv.chanfree(c);
	srv.reply(ref Rmsg.Error(m.tag, Eperm));
	return c;
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
	c.qid = Sys->Qid(0, 0);
	c.open = 0;
	c.mode = 0;
	c.fid = fid;
	slot := fid & (CHANHASHSIZE-1);
	srv.chans[slot] = c :: srv.chans[slot];
	return c;
}

devdir(nil: ref Chan, qid: Sys->Qid, name: string, length: big,
				user: string, perm: int): Sys->Dir
{
	d: Sys->Dir;
	d.name = name;
	d.qid = qid;
	d.dtype = 'X';
	d.dev = 0;		# XXX what should this be?
	d.mode = perm;
	if (qid.path & Sys->CHDIR)
		d.mode |= Sys->CHDIR;
	d.atime = starttime;	# XXX should be better than this.
	d.mtime = starttime;
	d.length = int length;
	d.uid = user;
	d.gid = user;
	return d;
}

readbytes(m: ref Tmsg.Read, d: array of byte): ref Rmsg.Read
{
	r := ref Rmsg.Read(m.tag, m.fid, nil);
	offset := int m.offset;
	if (offset >= len d)
		return r;
	e := offset + m.count;
	if (e > len d)
		e = len d;
	r.data = d[offset:e];
	return r;
}

readnum(m: ref Tmsg.Read, val, size: int): ref Rmsg.Read
{
	return readbytes(m, sys->aprint("%-*d", size, val));
}

readstr(m: ref Tmsg.Read, d: string): ref Rmsg.Read
{
	return readbytes(m, array of byte d);
}

dirgenmodule(): Dirgenmod
{
	return load Dirgenmod "$self";
}

dirgen(srv: ref Styxserver, c: ref Styxlib->Chan,
				tab: array of Dirtab, i: int): (int, Sys->Dir)
{
	d: Sys->Dir;
	if (tab == nil || i >= len tab)
		return (-1, d);
	return (1, devdir(c, tab[i].qid, tab[i].name, tab[i].length, srv.uname, tab[i].perm));
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
openok(omode, perm: int, uname, funame, nil: string): int
{
	# XXX what should we do about groups?
	# this is inadequate anyway:
	# OTRUNC
	# user should be allowed to open it if permission
	# is allowed to others.
	mode: int;
	if (uname == funame)
		mode = perm;
	else
		mode = perm << 6;

	t := access[omode & 3];
	return ((t & mode) == t);
}	

Chan.isdir(c: self ref Chan): int
{
	return (c.qid.path & Sys->CHDIR) != 0;
}

type2tag := array[] of {
	Tnop	=> tagof(Tmsg.Nop),
	Tflush	=> tagof(Tmsg.Flush),
	Tclone	=> tagof(Tmsg.Clone),
	Twalk	=> tagof(Tmsg.Walk),
	Topen	=> tagof(Tmsg.Open),
	Tcreate	=> tagof(Tmsg.Create),
	Tread	=> tagof(Tmsg.Read),
	Twrite	=> tagof(Tmsg.Write),
	Tclunk	=> tagof(Tmsg.Clunk),
	Tremove	=> tagof(Tmsg.Remove),
	Tstat		=> tagof(Tmsg.Stat),
	Twstat	=> tagof(Tmsg.Wstat),
	Tattach	=> tagof(Tmsg.Attach),
	*		=> -1
};

msglen := array[] of {
	Tnop	=> 3,
	Tflush	=> 5,
	Tclone	=> 7,
	Twalk	=> 33,
	Topen	=> 6,
	Tcreate	=> 38,
	Tread	=> 15,
	Twrite	=> 16,	# header only; excludes data
	Tclunk	=> 5,
	Tremove	=> 5,
	Tstat		=> 5,
	Twstat	=> 121,
	Tattach	=> 5+2*Sys->NAMELEN,

	Rnop	=> -3,
	Rerror	=> -67,
	Rflush	=> -3,
	Rclone	=> -5,
	Rwalk	=> -13,
	Ropen	=> -13,
	Rcreate	=> -13,
	Rread	=> -8,	# header only; excludes data
	Rwrite	=> -7,
	Rclunk	=> -5,
	Rremove	=> -5,
	Rstat		=> -121,
	Rwstat	=> -5,
	Rsession	=> -0,
	Rattach	=> -13,
	*		=> 0
};

d2tmsg(d: array of byte): (int, ref Tmsg)
{
	tag: int;
	gmsg: ref Tmsg;

	n := len d;
	if (n < 3)
		return (0, nil);

	t: int;
	(d, t) = gchar(d);
	if (t < 0 || t >= len msglen || msglen[t] <= 0)
		return (-1, nil);

	if (n < msglen[t])
		return (0, nil);

	(d, tag) = gshort(d);
	case t {
	Tnop	=>
			msg := ref Tmsg.Nop;
			gmsg = msg;
	Tflush	=>
			msg := ref Tmsg.Flush;
			(d, msg.oldtag) = gshort(d);
			gmsg = msg;
	Tclone	=>
			msg := ref Tmsg.Clone;
			(d, msg.fid) = gshort(d);
			(d, msg.newfid) = gshort(d);
			gmsg = msg;
	Twalk	=>
			msg := ref Tmsg.Walk;
			(d, msg.fid) = gshort(d);
			(d, msg.name) = gstring(d, Sys->NAMELEN);
			gmsg = msg;
	Topen	=>
			msg := ref Tmsg.Open;
			(d, msg.fid) = gshort(d);
			(d, msg.mode) = gchar(d);
			gmsg = msg;
	Tcreate	=>
			msg := ref Tmsg.Create;
			(d, msg.fid) = gshort(d);
			(d, msg.name) = gstring(d, Sys->NAMELEN);
			(d, msg.perm) = glong(d);
			(d, msg.mode) = gchar(d);
			gmsg = msg;
	Tread	=>
			msg := ref Tmsg.Read;
			(d, msg.fid) = gshort(d);
			(d, msg.offset) = gbig(d);
			if (msg.offset < big 0)
				msg.offset = big 0;
			(d, msg.count) = gshort(d);
			gmsg = msg;
	Twrite	=>
			count: int;
			msg := ref Tmsg.Write;
			(d, msg.fid) = gshort(d);
			(d, msg.offset) = gbig(d);
			if (msg.offset < big 0)
				msg.offset = big 0;
			(d, count) = gshort(d);
			if (count > Sys->ATOMICIO)
				return (-1, nil);
			if (len d < 1 + count)
				return (0, nil);
			d = d[1:];
			msg.data = d[0:count];
			d = d[count:];
			gmsg = msg;
	Tclunk	=>
			msg := ref Tmsg.Clunk;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Tremove	=>
			msg := ref Tmsg.Remove;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Tstat		=>
			msg := ref Tmsg.Stat;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Twstat	=>
			msg := ref Tmsg.Wstat;
			(d, msg.fid) = gshort(d);
			(d, msg.stat) = convM2D(d);
			gmsg = msg;
	Tattach	=>
			msg := ref Tmsg.Attach;
			(d, msg.fid) = gshort(d);
			(d, msg.uname) = gstring(d, Sys->NAMELEN);
			(d, msg.aname) = gstring(d, Sys->NAMELEN);
			gmsg = msg;
	*  =>
			return (-1, nil);
	}
	gmsg.tag = tag;
	return (n - len d, gmsg);
}

d2rmsg(d: array of byte): (int, ref Rmsg)
{
	tag: int;
	gmsg: ref Rmsg;

	n := len d;
	if (n < 3)
		return (0, nil);

	t: int;
	(d, t) = gchar(d);
	if (t < 0 || t >= len msglen || msglen[t] >= 0)
		return (-1, nil);

	if (n < -msglen[t])
		return (0, nil);

	(d, tag) = gshort(d);
	case t {
	Rnop	=>
			msg := ref Rmsg.Nop;
			gmsg = msg;
	Rflush	=>
			msg := ref Rmsg.Flush;
			gmsg = msg;
	Rclone	=>
			msg := ref Rmsg.Clone;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rwalk	=>
			msg := ref Rmsg.Walk;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Ropen	=>
			msg := ref Rmsg.Open;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Rcreate	=>
			msg := ref Rmsg.Create;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	Rread	=>
			count: int;
			msg := ref Rmsg.Read;
			(d, msg.fid) = gshort(d);
			(d, count) = gshort(d);
			if (count > Sys->ATOMICIO)
				return (-1, nil);
			if (len d < 1 + count)
				return (0, nil);
			d = d[1:];
			msg.data = d[0:count];
			d = d[count:];
			gmsg = msg;
	Rwrite	=>
			msg := ref Rmsg.Write;
			(d, msg.fid) = gshort(d);
			(d, msg.count) = gshort(d);
			gmsg = msg;
	Rclunk	=>
			msg := ref Rmsg.Clunk;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rremove	=>
			msg := ref Rmsg.Remove;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rstat		=>
			msg := ref Rmsg.Stat;
			(d, msg.fid) = gshort(d);
			(d, msg.stat) = convM2D(d);
			gmsg = msg;
	Rwstat	=>
			msg := ref Rmsg.Wstat;
			(d, msg.fid) = gshort(d);
			gmsg = msg;
	Rattach	=>
			msg := ref Rmsg.Attach;
			(d, msg.fid) = gshort(d);
			(d, msg.qid.path) = glong(d);
			(d, msg.qid.vers) = glong(d);
			gmsg = msg;
	*  =>
			return (-1, nil);
	}
	gmsg.tag = tag;
	return (n - len d, gmsg);
}

tag2type := array[] of {
tagof Rmsg.Nop	=> Rnop,
tagof Rmsg.Flush	=> Rflush,
tagof Rmsg.Error	=> Rerror,
tagof Rmsg.Clone	=> Rclone,
tagof Rmsg.Walk	=> Rwalk,
tagof Rmsg.Open	=> Ropen,
tagof Rmsg.Create	=> Rcreate,
tagof Rmsg.Read	=> Rread,
tagof Rmsg.Write	=> Rwrite,
tagof Rmsg.Clunk	=> Rclunk,
tagof Rmsg.Remove	=> Rremove,
tagof Rmsg.Stat	=> Rstat,
tagof Rmsg.Wstat	=> Rwstat,
tagof Rmsg.Attach	=> Rattach,
};

rmsg2d(gm: ref Rmsg, d: array of byte): int
{
	n := len d;
	d = pchar(d, tag2type[tagof gm]);
	d = pshort(d, gm.tag);
	pick m := gm {
	Nop or
	Flush =>
	Error	=>
		d = pstring(d, m.err, Sys->ERRLEN);
	Clunk or
	Remove or
	Clone or
	Wstat	=>
		d = pshort(d, m.fid);
	Walk or
	Create or
	Open or
	Attach =>
		d = pshort(d, m.fid);
		d = plong(d, m.qid.path);
		d = plong(d, m.qid.vers);
	Read =>
		d = pshort(d, m.fid);
		data := m.data;
		if (len data > Sys->ATOMICIO)
			data = data[0:Sys->ATOMICIO];
		d = pshort(d, len data);
		d = d[1:];			# pad
		d[0:] = data;
		d = d[len data:];
	Write =>
		d = pshort(d, m.fid);
		d = pshort(d, m.count);
	Stat =>
		d = pshort(d, m.fid);
		d = convD2M(d, m.stat);
	}
	return n - len d;
}

gchar(a: array of byte): (array of byte, int)
{
	return (a[1:], int a[0]);
}

gshort(a: array of byte): (array of byte, int)
{
	return (a[2:], int a[1]<<8 | int a[0]);
}

glong(a: array of byte): (array of byte, int)
{
	return (a[4:], int a[0] | int a[1]<<8 | int a[2]<<16 | int a[3]<<24);
}

gbig(a: array of byte): (array of byte, big)
{
	return (a[8:],
			big a[0] | big a[1] << 8 |
			big a[2] << 16 | big a[3] << 24 |
			big a[4] << 32 | big a[5] << 40 |
			big a[6] << 48 | big a[7] << 56);
}

gstring(a: array of byte, n: int): (array of byte, string)
{
	i: int;
	for (i = 0; i < n; i++)
		if (a[i] == byte 0)
			break;
	return (a[n:], string a[0:i]);
}

pchar(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	return a[1:];
}

pshort(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	return a[2:];
}

plong(a: array of byte, v: int): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	a[2] = byte (v >> 16);
	a[3] = byte (v >> 24);
	return a[4:];
}

pbig(a: array of byte, v: big): array of byte
{
	a[0] = byte v;
	a[1] = byte (v >> 8);
	a[2] = byte (v >> 16);
	a[3] = byte (v >> 24);
	a[4] = byte (v >> 32);
	a[5] = byte (v >> 40);
	a[6] = byte (v >> 58);
	a[7] = byte (v >> 56);
	return a[8:];
}

pstring(a: array of byte, s: string, n: int): array of byte
{
	sd := array of byte s;
	if (len sd > n - 1)
		sd = sd[0:n-1];
	a[0:] = sd;
	for (i := len sd; i < n; i++)
		a[i] = byte 0;
	return a[n:];
}

# convert from Dir to bytes
convD2M(d: array of byte, f: Sys->Dir): array of byte
{
	n := len d;
	d = pstring(d, f.name, Sys->NAMELEN);
	d = pstring(d, f.uid, Sys->NAMELEN);
	d = pstring(d, f.gid, Sys->NAMELEN);
	d = plong(d, f.qid.path);
	d = plong(d, f.qid.vers);
	d = plong(d, f.mode);
	d = plong(d, f.atime);
	d = plong(d, f.mtime);
	d = pbig(d, big f.length);	# the length field in Sys->Dir should really be big.
	d = pshort(d, f.dtype);
	d = pshort(d, f.dev);
	return d;
}

# convert from bytes to Dir
convM2D(d: array of byte): (array of byte, Sys->Dir)
{
	f: Sys->Dir;
	(d, f.name) = gstring(d, Sys->NAMELEN);
	(d, f.uid) = gstring(d, Sys->NAMELEN);
	(d, f.gid) = gstring(d, Sys->NAMELEN);
	(d, f.qid.path) = glong(d);
	(d, f.qid.vers) = glong(d);
	(d, f.mode) = glong(d);
	(d, f.atime) = glong(d);
	(d, f.mtime) = glong(d);
	length: big;
	(d, length) = gbig(d);
	f.length = int length;
	(d, f.dtype) = gshort(d);
	(d, f.dev) = gshort(d);
	return (d, f);
}


tmsgtags := array[] of {
tagof(Tmsg.Readerror) => "Readerror",
tagof(Tmsg.Nop) => "Nop",
tagof(Tmsg.Flush) => "Flush",
tagof(Tmsg.Clone) => "Clone",
tagof(Tmsg.Walk) => "Walk",
tagof(Tmsg.Open) => "Open",
tagof(Tmsg.Create) => "Create",
tagof(Tmsg.Read) => "Read",
tagof(Tmsg.Write) => "Write",
tagof(Tmsg.Clunk) => "Clunk",
tagof(Tmsg.Stat) => "Stat",
tagof(Tmsg.Remove) => "Remove",
tagof(Tmsg.Wstat) => "Wstat",
tagof(Tmsg.Attach) => "Attach",
};

rmsgtags := array[] of {
tagof(Rmsg.Nop) => "Nop",
tagof(Rmsg.Flush) => "Flush",
tagof(Rmsg.Error) => "Error",
tagof(Rmsg.Clunk) => "Clunk",
tagof(Rmsg.Remove) => "Remove",
tagof(Rmsg.Clone) => "Clone",
tagof(Rmsg.Wstat) => "Wstat",
tagof(Rmsg.Walk) => "Walk",
tagof(Rmsg.Create) => "Create",
tagof(Rmsg.Open) => "Open",
tagof(Rmsg.Attach) => "Attach",
tagof(Rmsg.Read) => "Read",
tagof(Rmsg.Write) => "Write",
tagof(Rmsg.Stat) => "Stat",
};

tmsg2s(gm: ref Tmsg): string
{
	if (gm == nil)
		return "Tmsg.nil";

	s := "Tmsg."+tmsgtags[tagof(gm)]+"("+string gm.tag;
	pick m:= gm {
	Readerror =>
		s += ", \""+m.error+"\"";
	Nop =>
	Flush =>
		s += ", " + string m.oldtag;
	Clone =>
		s += ", " + string m.fid + ", " + string m.newfid;
	Walk =>
		s += ", " + string m.fid + ", \""+m.name+"\"";
	Open =>
		s += ", " + string m.fid + ", " + string m.mode;
	Create =>
		s += ", " + string m.fid + ", " + string m.perm + ", "
			+ string m.mode + ", \""+m.name+"\"";
	Read =>
		s += ", " + string m.fid + ", " + string m.count + ", " + string m.offset;
	Write =>
		s += ", " + string m.fid + ", " + string m.offset
			+ ", data["+string len m.data+"]";
	Clunk or
	Stat or
	Remove =>
		s += ", " + string m.fid;
	Wstat =>
		s += ", " + string m.fid;
	Attach =>
		s += ", " + string m.fid + ", \""+m.uname+"\", \"" + m.aname + "\"";
	}
	return s + ")";
}

rmsg2s(gm: ref Rmsg): string
{
	if (sys == nil)
		sys = load Sys Sys->PATH;
	if (gm == nil)
		return "Rmsg.nil";

	s := "Rmsg."+rmsgtags[tagof(gm)]+"("+string gm.tag;
	pick m := gm {	
	Nop or
	Flush =>
	Error =>
		s +=", \""+m.err+"\"";
	Clunk or
	Remove or
	Clone or
	Wstat =>
		s += ", " + string m.fid;
	Walk	 or
	Create or
	Open or
	Attach =>
		s += ", " + string m.fid + sys->sprint(", %ux.%d", m.qid.path, m.qid.vers);
	Read =>
		s += ", " + string m.fid + ", data["+string len m.data+"]";
	Write =>
		s += ", " + string m.fid + ", " + string m.count;
	Stat =>
		s += ", " + string m.fid;
	}
	return s + ")";
}
