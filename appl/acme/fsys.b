implement Fsys;

include "common.m";

sys : Sys;
styx : Styx;
styxaux : Styxaux;
acme : Acme;
dat : Dat;
utils : Utils;
look : Look;
windowm : Windowm;

CHDIR, Qid, ORCLOSE, OTRUNC, OREAD, OWRITE, ORDWR, Dir : import Sys;
sprint : import sys;
NAMELEN, DIRLEN : import Styx;
Tnop, Tsession, Terror, Tflush, Tclone, Twalk, Topen, Tcreate, Tread, Twrite, Tclunk, Tremove, Tstat, Twstat, Tattach : import Styx;
Rerror : import Styx;
Qdir,Qacme,Qcons,Qconsctl,Qdraw,Qeditout,Qindex,Qlabel,Qnew,QWaddr,QWbody,QWconsctl,QWctl,QWdata,QWeditout,QWevent,QWrdsel,QWwrsel,QWtag,QMAX, CHAPPEND, MAXRPC : import Dat;
TRUE, FALSE : import Dat;
cxfidalloc, cerr : import dat;
Mntdir, Fid, Dirtab, Lock, Ref, Smsg0 : import dat;
Tmsg, Rmsg : import styx;
fid, uname, aname, newfid, name, mode, offset, count, setmode : import styxaux;
Xfid : import Xfidm;
row : import dat;
Column : import Columnm;
Window : import windowm;
lookid : import look;
warning, error : import utils;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	styx = mods.styx;
	styxaux = mods.styxaux;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;
	look = mods.look;
	windowm = mods.windowm;
}

sfd, cfd : ref Sys->FD;

Nhash : con 16;
DEBUG : con 0;

fids := array[Nhash] of ref Fid;

Eperm := "permission denied";
Eexist := "file does not exist";
Enotdir := "not a directory";

dirtab := array[10] of {
	Dirtab ( ".",		Qdir|CHDIR,	8r500|CHDIR ),
	Dirtab ( "acme",	Qacme|CHDIR,	8r500|CHDIR ),
	Dirtab ( "cons",		Qcons,		8r600 ),
	Dirtab ( "consctl",	Qconsctl,		8r000 ),
	Dirtab ( "draw",		Qdraw|CHDIR,	8r000|CHDIR ),
	Dirtab ( "editout",	Qeditout,		8r200 ),
	Dirtab ( "index",	Qindex,		8r400 ),
	Dirtab ( "label",		Qlabel,		8r600 ),
	Dirtab ( "new",		Qnew,		8r500|CHDIR ),
	Dirtab ( nil,		0,			0 ),
};

dirtabw := array[12] of {
	Dirtab ( ".",		Qdir|CHDIR,	8r500|CHDIR ),
	Dirtab ( "addr",		QWaddr,		8r600 ),
	Dirtab ( "body",		QWbody,		8r600|CHAPPEND ),
	Dirtab ( "ctl",		QWctl,		8r600 ),
	Dirtab ( "consctl",	QWconsctl,	8r200 ),
	Dirtab ( "data",		QWdata,		8r600 ),
	Dirtab ( "editout",	QWeditout,	8r200 ),
	Dirtab ( "event",	QWevent,		8r600 ),
	Dirtab ( "rdsel",		QWrdsel,		8r400 ),
	Dirtab ( "wrsel",	QWwrsel,		8r200 ),
	Dirtab ( "tag",		QWtag,		8r600|CHAPPEND ),
	Dirtab ( nil, 		0,			0 ),
};

Mnt : adt {
	qlock : ref Lock;
	id : int;
	md : ref Mntdir;
};

mnt : Mnt;
user : string;
clockfd : ref Sys->FD;
closing := 0;

fsysinit() 
{
	p :  array of ref Sys->FD;

	p = array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		error("can't create pipe");
	cfd = p[0];
	sfd = p[1];
	clockfd = sys->open("/dev/time", Sys->OREAD);
	user = utils->getuser();
	if (user == nil)
		user = "Wile. E. Coyote";
	mnt.qlock = Lock.init();
	mnt.id = 0;
	spawn fsysproc();
}

fsyscfd() : int
{
	return cfd.fd;
}

QID(w, q : int) : int
{
	return (w<<8)|q;
}

FILE(q : Qid) : int
{
	return q.path & 16rFF;
}

WIN(q : Qid) : int
{
	return ((q.path&~CHDIR)>>8) & 16rFFFFFF;
}

# nullsmsg : Smsg;
nullsmsg0 : Smsg0;

fsysproc()
{
	n, ok : int;
	x : ref Xfid;
	f : ref Fid;
	t : Smsg0;

	acme->fsyspid = sys->pctl(0, nil);
	x = nil;
	for(;;){
		if(x == nil){
			cxfidalloc <-= nil;
			x = <-cxfidalloc;
		}
		n = sys->read(sfd, x.buf, MAXRPC);
		if(n <= 0) {
			if (closing)
				break;
			error("i/o error on server channel");
		}
		(ok, x.fcall) = Tmsg.unpack(x.buf[0:n]);
		if(ok < 0)
			error("convert error in convM2S");
		if(DEBUG)
			utils->debug(sprint("%d:%s\n", x.tid, x.fcall.text()));
		pick fc := x.fcall {
			Nop =>
				f = nil;
			* =>
				f = allocfid(fid(x.fcall));
		}
		x.f = f;
		pick fc := x.fcall {
			Nop =>		x = fsysnop(x);
			Readerror =>	x = fsyserror();
			Flush =>		x = fsysflush(x);
			Clone =>		x = fsysclone(x, f);
			Walk =>		x = fsyswalk(x, f);
			Open =>		x = fsysopen(x, f);
			Create =>		x = fsyscreate(x);
			Read =>		x = fsysread(x, f);
			Write =>		x = fsyswrite(x);
			Clunk =>		x = fsysclunk(x, f);
			Remove =>	x = fsysremove(x);
			Stat =>		x = fsysstat(x, f);
			Wstat =>		x = fsyswstat(x);
			Attach =>		x = fsysattach(x, f);
			* =>
				x = respond(x, t, "bad fcall type");
		}
	}
}

fsysaddid(dir : string, ndir : int, incl : array of string, nincl : int) : ref Mntdir
{
	m : ref Mntdir;
	id : int;

	mnt.qlock.lock();
	id = ++mnt.id;
	m = ref Mntdir;
	m.id = id;
	m.dir =  dir;
	m.refs = 1;	# one for Command, one will be incremented in attach
	m.ndir = ndir;
	m.next = mnt.md;
	m.incl = incl;
	m.nincl = nincl;
	mnt.md = m;
	mnt.qlock.unlock();
	return m;
}

fsysdelid(idm : ref Mntdir)
{
	m, prev : ref Mntdir;
	i : int;
	
	if(idm == nil)
		return;
	mnt.qlock.lock();
	if(--idm.refs > 0){
		mnt.qlock.unlock();
		return;
	}
	prev = nil;
	for(m=mnt.md; m != nil; m=m.next){
		if(m == idm){
			if(prev != nil)
				prev.next = m.next;
			else
				mnt.md = m.next;
			for(i=0; i<m.nincl; i++)
				m.incl[i] = nil;
			m.incl = nil;
			m.dir = nil;
			m = nil;
			mnt.qlock.unlock();
			return;
		}
		prev = m;
	}
	mnt.qlock.unlock();
	buf := sys->sprint("fsysdelid: can't find id %d\n", idm.id);
	cerr <-= buf;
}

#
# Called only in exec.l:run(), from a different FD group
#
fsysmount(dir : string, ndir : int, incl : array of string, nincl : int) : ref Mntdir
{
	m : ref Mntdir;

	# close server side so don't hang if acme is half-exited
	# sfd = nil;
	m = fsysaddid(dir, ndir, incl, nincl);
	buf := sys->sprint("%d", m.id);
	if(sys->mount(cfd, "/mnt/acme", Sys->MREPL, buf) < 0){
		fsysdelid(m);
		return nil;
	}
	# cfd = nil;
	sys->bind("/mnt/acme", "/chan", Sys->MBEFORE);	# was MREPL
	if(sys->bind("/mnt/acme", "/dev", Sys->MBEFORE) < 0){
		fsysdelid(m);
		return nil;
	}
	return m;
}

fsysclose()
{
	closing = 1;
	# sfd = cfd = nil;
}

respond(x : ref Xfid, t0 : Smsg0, err : string) : ref Xfid
{
	t : ref Rmsg;

	# t = nullsmsg;
	tag := x.fcall.tag;
	fid := fid(x.fcall);
	qid := t0.qid;
	pick fc := x.fcall {
		Nop =>		t = ref Rmsg.Nop(tag);
		Readerror =>	t = ref Rmsg.Error(tag, err);
		Flush =>		t = ref Rmsg.Flush(tag);
		Clone =>		t = ref Rmsg.Clone(tag, fid);
		Walk =>		t = ref Rmsg.Walk(tag, fid, qid);
		Open =>		t = ref Rmsg.Open(tag, fid, qid);
		Create =>		t = ref Rmsg.Create(tag, fid, qid);
		Read =>		if(t0.count == len t0.data)
						t = ref Rmsg.Read(tag, fid, t0.data);
					else
						t = ref Rmsg.Read(tag, fid, t0.data[0: t0.count]);
		Write =>		t = ref Rmsg.Write(tag, fid, t0.count);
		Clunk =>		t = ref Rmsg.Clunk(tag, fid);
		Remove =>	t = ref Rmsg.Remove(tag, fid);
		Stat =>		t = ref Rmsg.Stat(tag, fid, t0.stat);
		Wstat =>		t = ref Rmsg.Wstat(tag, fid);
		Attach =>		t = ref Rmsg.Attach(tag, fid, qid);
	}
	# t.qid = t0.qid;
	# t.count = t0.count;
	# t.data = t0.data;
	# t.stat = t0.stat;
	if(err != nil)
		t = ref Rmsg.Error(tag, err);
	# t.fid = x.fcall.fid;
	# t.tag = x.fcall.tag;
	buf := t.pack();
	if(buf == nil)
		error("convert error in convS2M");
	if(sys->write(sfd, buf, len buf) != len buf)
		error("write error in respond");
	buf = nil;
	if(DEBUG)
		utils->debug(sprint("%d:r: %s\n", x.tid, t.text()));
	return x;
}

fsysnop(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, nil);
}

fsyserror() : ref Xfid
{
	error("sys error : Terror");
	return nil;
}

fsyssession(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	# BUG: should shut everybody down ??
	t = nullsmsg0;
	return respond(x, t, nil);
}

fsysflush(x : ref Xfid) : ref Xfid
{
	x.c <-= Xfidm->Xflush;
	return nil;
}

fsysattach(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	id : int;
	m : ref Mntdir;

	if (uname(x.fcall) != user)
		return respond(x, t, Eperm);
	f.busy = TRUE;
	f.open = FALSE;
	f.qid = (Qid)(CHDIR|Qdir, 0);
	f.dir = dirtab;
	f.nrpart = 0;
	f.w = nil;
	t.qid = f.qid;
	f.mntdir = nil;
	id = int aname(x.fcall);
	mnt.qlock.lock();
	for(m=mnt.md; m != nil; m=m.next)
		if(m.id == id){
			f.mntdir = m;
			m.refs++;
			break;
		}
	if(m == nil)
		cerr <-= "unknown id in attach";
	mnt.qlock.unlock();
	return respond(x, t, nil);
}

fsysclone(x : ref Xfid, f : ref Fid) : ref Xfid
{
	nf : ref Fid;
	t : Smsg0;

	if(f.open)
		return respond(x, t, "is open");
	# BUG: check exists
	nf = allocfid(newfid(x.fcall));
	nf.busy = TRUE;
	nf.open = FALSE;
	nf.mntdir = f.mntdir;
	if(f.mntdir != nil)
		f.mntdir.refs++;
	nf.dir = f.dir;
	nf.qid = f.qid;
	nf.w = f.w;
	nf.nrpart = 0;	# not open, so must be zero
	if(nf.w != nil)
		nf.w.refx.inc();
	return respond(x, t, nil);
}

fsyswalk(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	c, i, id : int;
	qid : int;
	d : array of Dirtab;
	w : ref Window;

	if((f.qid.path & CHDIR) == 0)
		return respond(x, t, Enotdir);
	name := name(x.fcall);
	if(name == ".."){
		qid = Qdir|CHDIR;
		id = 0;
	}
	else {
		# is it a numeric name?
		regular := 0;
		for(i=0; i < len name; i++) {
			c = name[i];
			if(c<'0' || '9'<c) {
				regular = 1;
				break;
			}
		}
		if (!regular) {
			# yes: it's a directory
			id = int name;
			row.qlock.lock();
			w = lookid(id, FALSE);
			if(w == nil){
				row.qlock.unlock();
				return respond(x, t, Eexist);
			}
			w.refx.inc();
			qid = CHDIR|Qdir;
			row.qlock.unlock();
			f.dir = dirtabw;
			f.w = w;
		}
		else {
			if(FILE(f.qid) == Qacme) 	# empty directory
				return respond(x, t, Eexist);
			id = WIN(f.qid);
			if(id == 0)
				d = dirtab;
			else
				d = dirtabw;
			k := 1;	# skip '.'
			found := 0;
			for( ; d[k].name != nil; k++)
				if(name == d[k].name){
					found = 1;
					qid = d[k].qid;
					f.dir = d[k:];
					break;
				}
			if (!found)
				return respond(x, t, Eexist);
		}
	}

	f.qid = (Qid)(QID(id, qid), 0);
	if(name == "new"){
		f.dir = dirtabw;
		x.c <-= Xfidm->Xwalk;
		return nil;
	}
	t.qid = f.qid;
	return respond(x, t, nil);
}

fsysopen(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	m : int;

	# can't truncate anything, so just disregard
	setmode(x.fcall, mode(x.fcall)&~OTRUNC);
	# can't execute or remove anything
	if(mode(x.fcall)&ORCLOSE)
		return respond(x, t, Eperm);
	case(mode(x.fcall)){
	OREAD =>
		m = 8r400;
	OWRITE =>
		m = 8r200;
	ORDWR =>
		m = 8r600;
	* =>
		return respond(x, t, Eperm);
	}
	if(((f.dir[0].perm&~(CHDIR|CHAPPEND))&m) != m)
		return respond(x, t, Eperm);
	x.c <-= Xfidm->Xopen;
	return nil;
}

fsyscreate(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

idcmp(a, b : int) : int
{
	return a-b;
}

qsort(a : array of int, n : int)
{
	i, j : int;
	t : int;

	while(n > 1) {
		i = n>>1;
		t = a[0]; a[0] = a[i]; a[i] = t;
		i = 0;
		j = n;
		for(;;) {
			do
				i++;
			while(i < n && idcmp(a[i], a[0]) < 0);
			do
				j--;
			while(j > 0 && idcmp(a[j], a[0]) > 0);
			if(j < i)
				break;
			t = a[i]; a[i] = a[j]; a[j] = t;
		}
		t = a[0]; a[0] = a[j]; a[j] = t;
		n = n-j-1;
		if(j >= n) {
			qsort(a, j);
			a = a[j+1:];
		} else {
			qsort(a[j+1:], n);
			n = j;
		}
	}
}

fsysread(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;
	b : array of byte;
	i, id, n, o, e, j, k, nids : int;
	ids : array of int;
	d : array of Dirtab;
	dt : Dirtab;
	c : ref Column;
	clock : int;

	b = nil;
	if(f.qid.path & CHDIR){
		if(int offset(x.fcall) % DIRLEN)
			return respond(x, t, "illegal offset in directory");
		if(FILE(f.qid) == Qacme){	# empty dir
			t.data = nil;
			t.count = 0;
			respond(x, t, nil);
			return x;
		}
		o = int offset(x.fcall);
		e = int offset(x.fcall)+count(x.fcall);
		clock = getclock();
		b = array[Dat->BUFSIZE] of byte;
		id = WIN(f.qid);
		n = 0;
		if(id > 0)
			d = dirtabw;
		else
			d = dirtab;
		k = 1;	# first entry is '.' 
		for(i=0; d[k].name!=nil && i+DIRLEN<e; i+=DIRLEN){
			if(i >= o){
				bb := styx->packdir(dostat(WIN(x.f.qid), d[k], clock));
				for (kk := 0; kk < DIRLEN; kk++)
					b[kk+n] = bb[kk];
				bb = nil;
				n += DIRLEN;
			}
			k++;
		}
		if(id == 0){
			row.qlock.lock();
			nids = 0;
			ids = nil;
			for(j=0; j<row.ncol; j++){
				c = row.col[j];
				for(k=0; k<c.nw; k++){
					oids := ids;
					ids = array[nids+1] of int;
					ids[0:] = oids[0:nids];
					oids = nil;
					ids[nids++] = c.w[k].id;
				}
			}
			row.qlock.unlock();
			qsort(ids, nids);
			j = 0;
			for(; j<nids && i+DIRLEN<e; i+=DIRLEN){
				if(i >= o){
					k = ids[j];
					dt.name = sys->sprint("%d", k);
					dt.qid = QID(k, CHDIR);
					dt.perm = CHDIR|8r700;
					bb := styx->packdir(dostat(k, dt, clock));
					for (kk := 0; kk < DIRLEN; kk++)
						b[kk+n] = bb[kk];
					bb = nil;
					n += DIRLEN;
				}
				j++;
			}
			ids = nil;
		}
		t.data = b;
		t.count = n;
		respond(x, t, nil);
		b = nil;
		return x;
	}
	x.c <-= Xfidm->Xread;
	return nil;
}

fsyswrite(x : ref Xfid) : ref Xfid
{
	x.c <-= Xfidm->Xwrite;
	return nil;
}

fsysclunk(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;

	fsysdelid(f.mntdir);
	if(f.open){
		f.busy = FALSE;
		f.open = FALSE;
		x.c <-= Xfidm->Xclose;
		return nil;
	}
	if(f.w != nil)
		f.w.close();
	f.busy = FALSE;
	f.open = FALSE;
	return respond(x, t, nil);
}

fsysremove(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

fsysstat(x : ref Xfid, f : ref Fid) : ref Xfid
{
	t : Smsg0;

	t.stat = dostat(WIN(x.f.qid), f.dir[0], getclock());
	return respond(x, t, nil);
}

fsyswstat(x : ref Xfid) : ref Xfid
{
	t : Smsg0;

	return respond(x, t, Eperm);
}

allocfid(fid : int) : ref Fid
{	
	f, ff : ref Fid;
	fh : int;

	ff = nil;
	fh = fid&(Nhash-1);
	for(f=fids[fh]; f != nil; f=f.next)
		if(f.fid == fid)
			return f;
		else if(ff==nil && f.busy==FALSE)
			ff = f;
	if(ff != nil){
		ff.fid = fid;
		return ff;
	}
	f = ref Fid;
	f.rpart = array[Sys->UTFmax] of byte;
	f.nrpart = 0;
	f.fid = fid;
	f.next = fids[fh];
	fids[fh] = f;
	return f;
}

cbuf := array[32] of byte;

getclock() : int
{
	sys->seek(clockfd, 0, 0);
	n := sys->read(clockfd, cbuf, len cbuf);
	return int string cbuf[0:n];
}

dostat(id : int, dir : Dirtab, clock : int) : Sys->Dir
{
	d : Dir;

	d.qid.path = QID(id, dir.qid);
	d.qid.vers = 0;
	d.mode = dir.perm;
	d.length = 0;	# would be nice to do better
	d.name = dir.name;
	d.uid = user;
	d.gid = user;
	d.atime = clock;
	d.mtime = clock;
	d.dtype = d.dev = 0;
	return d;
	# buf := styx->convD2M(d);
	# d = nil;
	# return buf;
}
