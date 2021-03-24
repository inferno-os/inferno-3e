implement Dbfs;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "styxlib.m";
	styx: Styxlib;
	Dirtab, Styxserver, Tmsg, Rmsg, Chan: import styx;
	Eperm, Ebadfid: import styx;
	devgen: Dirgenmod;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

Record: adt {
	id:		int;		# file number in directory
	x:		int;		# index in file
	dirty:	int;		# modified but not written
	data:		array of byte;
};

Database: adt {
	name:	string;
	file:	ref Iobuf;
	records:	array of ref Record;
	dirty:	int;
};

Dbfs: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
	dirgen:	fn(srv: ref Styxlib->Styxserver, c: ref Styxlib->Chan, tab: array of Styxlib->Dirtab, i: int): (int, Sys->Dir);
};

Qdir, Qnew, Qdata: con iota;

clockfd: ref Sys->FD;
stderr: ref Sys->FD;
database: ref Database;

usage()
{
	sys->fprint(stderr, "Usage: dbfs [-abcr] file mountpoint\n");
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	styx = load Styxlib Styxlib->PATH;
	if (styx == nil)
		sys->raise(sys->sprint("can't load %s: %r", Styxlib->PATH));
	devgen = load Dirgenmod "$self";
	if (devgen == nil)
		sys->raise(sys->sprint("can't load Dirgenmod: %r"));
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		sys->raise(sys->sprint("can't load Bufio: %r"));
	stderr = sys->fildes(2);
	flags := Sys->MREPL;
	copt := 0;
	empty := 0;
	if(args != nil)
		args = tl args;
	for(; args != nil; args = tl args){
		s := hd args;
		if(s[0] != '-')
			break;
		for(i := 1; i < len s; i++)
			case s[i] {
			'a' =>	flags = Sys->MAFTER;
			'b' =>	flags = Sys->MBEFORE;
			'r' =>		flags = Sys->MREPL;
			'c' =>	copt = 1;
			'e' =>	empty = 1;
			* =>		usage();
			}
	}
	if(len args != 2)
		usage();
	if(copt)
		flags |= Sys->MCREATE;
	file := hd args;
	args = tl args;
	mountpt := hd args;

	df := bufio->open(file, Sys->OREAD);
	if(df == nil && empty){
		(rc, d) := sys->stat(file);
		if(rc < 0)
			df = bufio->create(file, Sys->OREAD, 8r600);
	}
	if(df == nil){
		sys->fprint(stderr, "dbfs: can't open %s: %r\n", file);
		exit;
	}
	(db, err) := dbread(ref Database(file, df, nil, 0));
	if(db == nil){
		sys->fprint(stderr, "dbfs: can't read %s: %s\n", file, err);
		exit;
	}
	db.file = nil;
#	dbprint(db);
	database = db;

	sys->pctl(Sys->FORKFD, nil);
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	(tchan, srv) := Styxserver.new(fds[0]);
	fds[0] = nil;

	pidc := chan of int;
	spawn serveloop(tchan, srv, pidc);
	<-pidc;
	if(sys->mount(fds[1], mountpt, flags, nil) == -1) {
		sys->print("mount failed: %r\n");
		return;
	}
}

dbread(db: ref Database): (ref Database, string)
{
	db.file.seek(0, Sys->SEEKSTART);
	rl: list of ref Record;
	for(;;){
		(r, err) := getrec(db);
		if(err != nil)
			return (nil, err);		# could press on without it, or make it the `file' contents
		if(r == nil)
			break;
		rl = r :: rl;
	}
	n := len rl;
	db.records = array[n] of ref Record;
	for(; rl != nil; rl = tl rl){
		r := hd rl;
		n--;
		r.id = n;
		r.x = n;
		db.records[n] = r;
	}
	return (db, nil);
}

#
# a record is (.+\n)*\n
#
getrec(db: ref Database): (ref Record, string)
{
	r := ref Record(-1, -1, 0, nil);
	data := "";
	for(;;){
		s := db.file.gets('\n');
		if(s == nil){
			if(data == nil)
				return (nil, nil);		# BUG: distinguish i/o error from EOF?
			break;
		}
		if(s[len s - 1] != '\n')
#			return (nil, "file missing newline");	# possibly truncated
			s += "\n";
		if(s == "\n")
			break;
		data += s;
	}
	r.data = array of byte data;
	return (r, nil);
}

dbsync(db: ref Database): int
{
	if(db.dirty){
		db.file = bufio->create(db.name, Sys->OWRITE, 8r666);
		if(db.file == nil)
			return -1;
		for(i := 0; i < len db.records; i++){
			r := db.records[i];
			if(r != nil && r.data != nil){
				if(db.file.write(r.data, len r.data) != len r.data)
					return -1;
				db.file.putc('\n');
			}
		}
		if(db.file.flush())
			return -1;
		db.file = nil;
		db.dirty = 0;
	}
	return 0;
}

dbprint(db: ref Database)
{
	stdout := sys->fildes(1);
	for(i := 0; i < len db.records; i++){
		printrec(stdout, db.records[i]);
		sys->print("\n");
	}
}

newrecord(fields: array of byte): ref Record
{
	n := len database.records;
	r := ref Record(n, n, 0, fields);
	a := array[n+1] of ref Record;
	if(n)
		a[0:] = database.records[0:];
	a[n] = r;
	database.records = a;
	return r;
}

printrec(fd: ref Sys->FD, r: ref Record)
{
	if(r.data != nil)
		sys->write(fd, r.data, len r.data);
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, 1::srv.fd.fd::nil);
	dirtab := array[1] of Dirtab;
	for (;;) {
		gm := <-tchan;
		if (gm == nil) {
			#sys->print("server got EOF: exiting\n");
			exit;
		}
		pick m := gm {
		Readerror =>
			sys->fprint(stderr, "dbfs: fatal read error: %s\n", m.error);
			exit;
		Nop =>
			srv.reply(ref Rmsg.Nop(m.tag));
		Flush =>
			srv.devflush(m);
		Clone =>
			srv.devclone(m);
		Walk =>
			srv.devwalk(m, devgen, dirtab);
		Open =>
			devopen(srv, m);
		Create =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Read =>
			c := srv.fidtochan(m.fid);
			if (c == nil) {
				srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
				break;
			}
			if (c.isdir()){
				srv.devdirread(m, devgen, dirtab);
				break;
			}
			r := database.records[FILENO(c.qid)];
			if(r == nil)
				srv.reply(ref Rmsg.Error(m.tag, "phase error"));
			else
				srv.reply(styx->readbytes(m, r.data));
		Write =>
			c := srv.fidtochan(m.fid);
			if(c == nil || !c.open){
				srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
				break;
			}
			if(TYPE(c.qid) != Qdata){
				srv.reply(ref Rmsg.Error(m.tag, Eperm));
				break;
			}
			(r, err) := data2rec(m.data);
			if(err != nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
				break;
			}
			database.records[FILENO(c.qid)] = r;		# TO DO: r.vers++
			database.dirty++;
			if(dbsync(database) == 0)
				srv.reply(ref Rmsg.Write(m.tag, m.fid, len m.data));
			else
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
		Clunk =>
			srv.devclunk(m);
		Stat =>
			srv.devstat(m, devgen, dirtab);
		Remove =>
			c := srv.fidtochan(m.fid);
			if(c == nil || c.isdir() || TYPE(c.qid) != Qdata){
				srv.devremove(m);
				break;
			}
			r := database.records[FILENO(c.qid)];
			if(r != nil)
				r.data = nil;
			database.dirty++;
			srv.chanfree(c);
			if(dbsync(database) == 0)
				srv.reply(ref Rmsg.Remove(m.tag, m.fid));
			else
				srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
		Wstat =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Attach =>
			srv.devattach(m);
		}
	}
}

dirslot(n: int): int
{
	for(i := 0; i < len database.records; i++){	# n² but the file will be small
		r := database.records[i];
		if(r != nil && r.data != nil){
			if(n == 0)
				return i;
			n--;
		}
	}
	return -1;
}

dirgen(srv: ref Styxserver, c: ref Styxlib->Chan, nil: array of Dirtab, i: int): (int, Sys->Dir)
{
	d: Sys->Dir;
	if(i == 0)
		return (1, styx->devdir(c, QID(0, Qnew), "new", big 0, srv.uname, 8r600));
	i--;
	j := dirslot(i);
	if(j < 0 || j >= len database.records)
		return (-1, d);
	return (1, styx->devdir(c, QID(j,Qdata), sys->sprint("%d", j), big 0, srv.uname, 8r600));
}
	
devopen(srv: ref Styxserver, m: ref Tmsg.Open): ref Chan
{
	c := srv.fidtochan(m.fid);
	if (c == nil) {
		srv.reply(ref Rmsg.Error(m.tag, Ebadfid));
		return nil;
	}
	if(c.qid.path & Sys->CHDIR){
		if(m.mode != Sys->OREAD) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
	} else {
		if(c.uname != srv.uname) {
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
			return nil;
		}
		if(TYPE(c.qid) == Qnew){
			# generate new file
			r := newrecord(array[0] of byte);
			c.qid = QID(r.x, Qdata);
		}
		c.qid.vers = 0;		# TO DO: r.vers
	}
	if ((c.mode = styx->openmode(m.mode)) == -1) {
		srv.reply(ref Rmsg.Error(m.tag, styx->Ebadarg));
		return nil;
	}
	c.open = 1;
	srv.reply(ref Rmsg.Open(m.tag, m.fid, c.qid));
	return c;
}

QID(w, q: int): Sys->Qid
{
	return Sys->Qid((w<<8)|q, 0);
}

TYPE(q: Sys->Qid): int
{
	return q.path & 16rFF;
}

FILENO(q : Sys->Qid) : int
{
	return ((q.path&~Sys->CHDIR)>>8) & 16rFFFFFF;
}

#
# a record is (.+\n)*, without final empty line
#
data2rec(data: array of byte): (ref Record, string)
{
	r := ref Record(-1, -1, 0, nil);
	s: string;
	for(b := data; len b > 0;){
		(b, s) = getline(b);
		if(s == nil || s[len s - 1] != '\n' || s == "\n")
			return (nil, "partial or malformed record");	# possibly truncated
	}
	r.data = data;
	return (r, nil);
}

getline(b: array of byte): (array of byte, string)
{
	n := len b;
	for(i := 0; i < n; i++){
		(ch, l, nil) := sys->byte2char(b, i);
		i += l;
		if(l == 0 || ch == '\n')
			break;
	}
	return (b[i:], string b[0:i]);
}
