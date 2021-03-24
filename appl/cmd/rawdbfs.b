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
include "string.m";
	str: String;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

# to do:
# make writing & reading more like real files; don't ignore offsets.
# open with OTRUNC should work.
# provide some way of compacting a dbfs file.

Record: adt {
	id:		int;			# file number in directory (if block is allocated)
	offset:	int;			# start of data
	count:	int;			# length of block (excluding header)
	datalen:	int;			# length of data (-1 if block is free)
};

HEADLEN: con 10;
MINSIZE: con 20;

Database: adt {
	file: ref Iobuf;
	records: array of ref Record;
	maxid: int;
	build: fn(f: ref Iobuf): (ref Database, string);
	write: fn(db: self ref Database, n: int, data: array of byte): int;
	read: fn(db: self ref Database, n: int): array of byte;
	remove: fn(db: self ref Database, n: int);
	create: fn(db: self ref Database, data: array of byte): int;
};

Dbfs: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
	dirgen: fn(srv: ref Styxlib->Styxserver, c: ref Styxlib->Chan, tab: array of Styxlib->Dirtab, i: int): (int, Sys->Dir);
};

Qdir, Qnew, Qdata: con iota;

stderr: ref Sys->FD;
database: ref Database;

usage()
{
	sys->fprint(stderr, "Usage: dbfs [-abcr] file mountpoint\n");
	sys->raise("fail:usage");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	styx = load Styxlib Styxlib->PATH;
	if (styx == nil) {
		sys->fprint(stderr, "dbfs: can't load %s: %r\n", Styxlib->PATH);
		sys->raise("fail:bad module");
	}
	str = load String String->PATH;
	if (str == nil) {
		sys->fprint(stderr, "dbfs: can't load %s: %r\n", String->PATH);
		sys->raise("fail:bad module");
	}
	devgen = load Dirgenmod "$self";
	if (devgen == nil) {
		sys->fprint(stderr, "dbfs: can't load Dirgenmod from self: %r\n");
		sys->raise("fail:bad module");
	}
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil) {
		sys->fprint(stderr, "dbfs: can't load %s: %r\n", Bufio->PATH);
		sys->raise("fail:bad module");
	}
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

	df := bufio->open(file, Sys->ORDWR);
	if(df == nil && empty){
		(rc, d) := sys->stat(file);
		if(rc < 0)
			df = bufio->create(file, Sys->ORDWR, 8r600);
	}
	if(df == nil){
		sys->fprint(stderr, "dbfs: can't open %s: %r\n", file);
		sys->raise("fail:cannot open file");
	}
	(db, err) := Database.build(df);
	if(db == nil){
		sys->fprint(stderr, "dbfs: can't read %s: %s\n", file, err);
		sys->raise("fail:cannot read db");
	}
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
		sys->fprint(stderr, "dbfs: mount failed: %r\n");
		sys->raise("fail:bad mount");
	}
}

serveloop(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->FORKNS|Sys->NEWFD, stderr.fd::1::database.file.fd.fd::srv.fd.fd::nil);
	stderr = sys->fildes(stderr.fd);
	database.file.fd = sys->fildes(database.file.fd.fd);
	dirtab := array[1] of Dirtab;
	for (;;) {
		gm := <-tchan;
		if (gm == nil)
			exit;
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
			recno := id2recno(FILENO(c.qid));
			if (recno == -1)
				srv.reply(ref Rmsg.Error(m.tag, "phase error"));
			else {
				srv.reply(styx->readbytes(m, database.read(recno)));
			}
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
			recno := id2recno(FILENO(c.qid));
			if (recno == -1)
				srv.reply(ref Rmsg.Error(m.tag, "phase error"));
			else {
				if (database.write(recno, m.data) == -1)
					srv.reply(ref Rmsg.Error(m.tag, sys->sprint("%r")));
				else
					srv.reply(ref Rmsg.Write(m.tag, m.fid, len m.data));
			}
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
			recno := id2recno(FILENO(c.qid));
			if (recno == -1)
				srv.reply(ref Rmsg.Error(m.tag, "phase error"));
			else {
				database.remove(recno);
				srv.reply(ref Rmsg.Remove(m.tag, m.fid));
			}
			srv.chanfree(c);
		Wstat =>
			srv.reply(ref Rmsg.Error(m.tag, Eperm));
		Attach =>
			srv.devattach(m);
		}
	}
}

id2recno(id: int): int
{
	recs := database.records;
	for (i := 0; i < len recs; i++)
		if (recs[i].datalen >= 0 && recs[i].id == id)
			return i;
	return -1;
}

dirslot(n: int): int
{
	for(i := 0; i < len database.records; i++){	# n² but the file will be small
		r := database.records[i];
		if(r.datalen >= 0){
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
	r := database.records[j];
	return (1, styx->devdir(c, QID(r.id,Qdata), sys->sprint("%d", r.id), big 0, srv.uname, 8r600));
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
			r := database.create(array[0] of byte);
			if (r == -1) {
				srv.reply(ref Rmsg.Error(m.tag, "cannot create ENtry"));
				return nil;
			}
			c.qid = QID(database.records[r].id, Qdata);
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

Database.build(f: ref Iobuf): (ref Database, string)
{
	rl: list of ref Record;
	offset := 0;
	maxid := 0;
	for (;;) {
		d := array[HEADLEN] of byte;
		n := f.read(d, HEADLEN);
		if (n < HEADLEN)
			break;
		orig := s := string d;
		if (len s != HEADLEN)
			return (nil, "found bad header");
		r := ref Record;
		(r.count, s) = str->toint(s, 10);
		(r.datalen, s) = str->toint(s, 10);
		if (s != "\n")
			return (nil, sys->sprint("found bad header '%s'\n", orig));
		r.offset = offset + HEADLEN;
		offset += r.count + HEADLEN;
		f.seek(offset, Bufio->SEEKSTART);
		r.id = maxid++;
		rl = r :: rl;
	}
	db := ref Database(f, array[len rl] of ref Record, maxid);
	for (i := len db.records - 1; i >= 0; i--) {
		db.records[i] = hd rl;
		rl = tl rl;
	}
	return (db, nil);
}

Database.write(db: self ref Database, recno: int, data: array of byte): int
{
	r := db.records[recno];
	if (len data <= r.count) {
		if (r.count - len data >= HEADLEN + MINSIZE)
			splitrec(db, recno, len data);
		writerec(db, recno, data);
		db.file.flush();
	} else {
		freerec(db, recno);
		n := allocrec(db, len data);
		if (n == -1)
			return -1;		# BUG: we lose the original data in this case.
		db.records[n].id = r.id;
		db.write(n, data);
	}
	return 0;
}

Database.create(db: self ref Database, data: array of byte): int
{
	n := allocrec(db, len data);
	if (n == -1)
		return -1;
	db.records[n].id = db.maxid++;
	e := db.write(n, data);
	if (e == -1)
		n = -1;
	return n;
}

Database.read(db: self ref Database, recno: int): array of byte
{
	r := db.records[recno];
	if (r.datalen <= 0)
		return nil;
	db.file.seek(r.offset, Bufio->SEEKSTART);
	d := array[r.datalen] of byte;
	n := db.file.read(d, r.datalen);
	if (n != r.datalen) {
		sys->fprint(stderr, "dbfs: only read %d bytes (expected %d)\n", n, r.datalen);
		return nil;
	}
	return d;
}

Database.remove(db: self ref Database, recno: int)
{
	freerec(db, recno);
	db.file.flush();
}

freerec(db: ref Database, recno: int)
{
	nr := len db.records;
	db.records[recno].datalen = -1;
	for (i := recno; i >= 0; i--)
		if (db.records[i].datalen != -1)
			break;
	f := i + 1;
	nb := 0;
	for (i = f; i < nr; i++) {
		if (db.records[i].datalen != -1)
			break;
		nb += db.records[i].count + HEADLEN;
	}
	db.records[f].count = nb - HEADLEN;
	writeheader(db.file, db.records[f]);
	# could blank out freed entries here if we cared.
	if (i < nr && f < i)
		db.records[f+1:] = db.records[i:];
	db.records = db.records[0:nr - (i - f - 1)];
}

splitrec(db: ref Database, recno: int, pos: int)
{
	a := array[len db.records + 1] of ref Record;
	a[0:] = db.records[0:recno+1];
	if (recno < len db.records - 1)
		a[recno+2:] = db.records[recno+1:];
	db.records = a;
	r := a[recno];
	a[recno+1] = ref Record(-1, r.offset + pos + HEADLEN, r.count - HEADLEN - pos, -1);
	r.count = pos;
	writeheader(db.file, a[recno+1]);
}

writerec(db: ref Database, recno: int, data: array of byte): int
{
	db.records[recno].datalen = len data;
	if (writeheader(db.file, db.records[recno]) == -1)
		return -1;
	if (db.file.write(data, len data) == Bufio->ERROR)
		return -1;
	return 0;
}

writeheader(f: ref Iobuf, r: ref Record): int
{
	f.seek(r.offset - HEADLEN, Bufio->SEEKSTART);
	if (f.puts(sys->sprint("%4d %4d\n", r.count, r.datalen)) == Bufio->ERROR) {
		sys->fprint(stderr, "dbfs: error writing header (id %d, offset %d, count %d, datalen %d): %r\n",
					r.id, r.offset, r.count, r.datalen);
		return -1;
	}
	return 0;
}

# finds or creates a record of the requisite size; does not mark it as allocated.
allocrec(db: ref Database, nb: int): int
{
	if (nb < MINSIZE)
		nb = MINSIZE;
	best := -1;
	n := -1;
	for (i := 0; i < len db.records; i++) {
		r := db.records[i];
		if (r.datalen == -1) {
			avail := r.count - nb;
			if (avail >= 0 && (n == -1 || avail < best)) {
				best = avail;
				n = i;
			}
		}
	}
	if (n != -1)
		return n;
	nr := len db.records;
	a := array[nr + 1] of ref Record;
	a[0:] = db.records[0:];
	offset := 0;
	if (nr > 0)
		offset = a[nr-1].offset + a[nr-1].count;
	db.file.seek(offset, Bufio->SEEKSTART);
	if (db.file.write(array[nb + HEADLEN] of {* => byte(0)}, nb + HEADLEN) == Bufio->ERROR
			|| db.file.flush() == Bufio->ERROR) {
		sys->fprint(stderr, "dbfs: write of new entry failed: %r\n");
		return -1;
	}
	a[nr] = ref Record(-1, offset + HEADLEN, nb, -1);
	db.records = a;
	return nr;
}
