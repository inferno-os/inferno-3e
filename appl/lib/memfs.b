implement MemFS;

include "sys.m";
include "styxlib.m";
include "memfs.m";

sys : Sys;
styxlib : Styxlib;

CHDIR, OTRUNC, ORCLOSE, OREAD, OWRITE: import Sys;
Styxserver, Tmsg, Rmsg : import styxlib;

blksz : con 512;
Efull : con "filesystem full";

Memfile : adt {
	name : string;
	owner : string;
	qid : Sys->Qid;
	perm : int;
	atime : int;
	mtime : int;
	nopen : int;
	data : array of byte;			# allocated in blks
	length : int;
	parent : cyclic ref Memfile;	# Dir entry linkage
	kids : cyclic ref Memfile;
	prev : cyclic ref Memfile;
	next : cyclic ref Memfile;
	hashnext : cyclic ref Memfile;	# Qid hash linkage
};

Qidhash : adt {
	buckets : array of ref Memfile;
	nextqid : int;
	new : fn () : ref Qidhash;
	add : fn (h : self ref Qidhash, mf : ref Memfile);
	remove : fn (h : self ref Qidhash, mf : ref Memfile);
	lookup : fn (h : self ref Qidhash, qid : Sys->Qid) : ref Memfile;
};

timefd: ref Sys->FD;

init() : string
{
	sys = load Sys Sys->PATH;
	styxlib = load Styxlib Styxlib->PATH;
	if (styxlib == nil)
		return sys->sprint("cannot load styxlib: %r");
	timefd = sys->open("/dev/time", sys->OREAD);
	return nil;
}

newfs(maxsz : int) : ref Sys->FD
{
	p := array [2] of ref Sys->FD;
	if (sys->pipe(p) == -1)
		return nil;
	(tc, srv) := Styxserver.new(p[1]);
	spawn memfs(maxsz, tc, srv);
	return p[0];
}

memfs(maxsz : int, tc : chan of ref Tmsg, srv : ref Styxserver)
{
	freeblks := (maxsz / blksz);
	qhash := Qidhash.new();

	# init root
	root := newmf(qhash, nil, "memfs", srv.uname, 8r700 | CHDIR);
	root.parent = root;

	for (;;) {
		tmsg := <- tc;
		if (tmsg == nil)
			break;
#		sys->print("%s\n", styxlib->tmsg2s(tmsg));
		pick tm := tmsg {
		Readerror =>
			return;
		Nop =>
			srv.reply(ref Rmsg.Nop(tm.tag));
		Flush =>
			srv.reply(ref Rmsg.Flush(tm.tag));
		Clone =>
			(err, nil, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.devclone(tm);
		Walk =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			wmf := dirlookup(mf, tm.name);
			if (wmf == nil) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxlib->Enotfound));
				continue;
			}
			c.qid = wmf.qid;
			srv.reply(ref Rmsg.Walk(tm.tag, tm.fid, wmf.qid));
		Open =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && c.open)
				err = Styxlib->Eopen;
			if (err == "" && !modeok(tm.mode, mf.perm, c.uname, mf.owner))
				err = Styxlib->Eperm;
			if (err == "" && (mf.perm & CHDIR) && (tm.mode & (OTRUNC|OWRITE|ORCLOSE)))
				err = Styxlib->Eperm;
			if (err == "" && (tm.mode & ORCLOSE)) {
				p := mf.parent;
				if (p == nil || !modeok(OWRITE, p.perm, c.uname, p.owner))
					err = Styxlib->Eperm;
			}

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			c.open = 1;
			c.mode = tm.mode;
			c.qid.vers = mf.qid.vers;
			mf.nopen++;
			if (tm.mode & OTRUNC) {
				# OTRUNC cannot be set for a directory
				# always at least one blk so don't need to check fs limit
				freeblks += (len mf.data) / blksz;
				mf.data = nil;
				freeblks--;
				mf.data = array[blksz] of byte;
				mf.length = 0;
				mf.mtime = now();
			}
			srv.reply(ref Rmsg.Open(tm.tag, tm.fid, mf.qid));
		Create =>
			(err, c, parent) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && c.open)
				err = Styxlib->Eopen;
			if (err == "" && !(parent.qid.path & CHDIR))
				err = Styxlib->Enotdir;
			if (err == "" && !modeok(OWRITE, parent.perm, c.uname, parent.owner))
				err = Styxlib->Eperm;
			if (err == "" && (tm.perm & CHDIR) && (tm.mode & (OTRUNC|OWRITE|ORCLOSE)))
				err = Styxlib->Eperm;
			if (err == "" && dirlookup(parent, tm.name) != nil)
				err = Styxlib->Eexists;

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			isdir := tm.perm & CHDIR;
			if (!isdir && freeblks <= 0) {
				srv.reply(ref Rmsg.Error(tm.tag, Efull));
				continue;
			}

			# modify perms as per Styx specification...
			perm : int;
			if (isdir)
				perm = (tm.perm&~8r777) | (parent.perm&tm.perm&8r777);
			else
				perm = (tm.perm&(~8r777|8r111)) | (parent.perm&tm.perm& 8r666);

			nmf := newmf(qhash, parent, tm.name, c.uname, perm);
			if (!isdir) {
				freeblks--;
				nmf.data = array [blksz] of byte;
			}

			# link in the new MemFile
			nmf.next = parent.kids;
			if (parent.kids != nil)
				parent.kids.prev = nmf;
			parent.kids = nmf;

			c.open = 1;
			c.mode = tm.mode;
			c.qid = nmf.qid;
			nmf.nopen = 1;
			srv.reply(ref Rmsg.Create(tm.tag, tm.fid, nmf.qid));
		Read =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err == "" && !c.open)
				err = Styxlib->Ebadfid;

			if (err != "") {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			data : array of byte = nil;
			offset := int tm.offset;
			if (mf.perm & CHDIR) {
				nskip := offset / Styxlib->DIRLEN;
				nread := tm.count / Styxlib->DIRLEN;
				data = dirdata(mf, nskip, nread);
			} else if (offset < mf.length) {
				max := offset + tm.count;
				if (max > mf.length)
					max = mf.length;
				data = mf.data[offset:max];
			}
			mf.atime = now();
			srv.reply(ref Rmsg.Read(tm.tag, tm.fid, data));
		Write =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (c != nil && !c.open)
				err = Styxlib->Ebadfid;
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			offset := int tm.offset;
			wbytes := len tm.data;
			newlen := offset + wbytes;
			newblks := ((newlen + blksz - 1) / blksz);
			oldblks := len mf.data / blksz;
			delta := newblks - oldblks;
			if (delta > 0) {
				# allocate as many blks as needed/available
				if (delta > freeblks)
					delta = freeblks;
				newlen = (oldblks + delta) * blksz;
				# being a little harsh here
				# - may be able to write some of the bytes
				if (newlen < offset + wbytes) {
					# cannot extend the file
					srv.reply(ref Rmsg.Error(tm.tag, Efull));
					continue;
				}
#				wbytes = min(offset + wbytes, newlen) - offset;
				newdata := array [newlen] of byte;
				freeblks -= delta;
				newdata[0:] = mf.data;
				mf.data = newdata;
			}
			if (wbytes)
				mf.data[offset:] = tm.data[:wbytes];
			mf.length = max(mf.length, offset + wbytes);
			mf.mtime = now();
			srv.reply(ref Rmsg.Write(tm.tag, tm.fid, wbytes));
		Clunk =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (c != nil)
				srv.chanfree(c);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			if (c.open) {
				if (c.mode & ORCLOSE)
					unlink(mf);
				mf.nopen--;
				freeblks += delfile(qhash, mf);
			}
			srv.reply(ref Rmsg.Clunk(tm.tag, tm.fid));
		Stat =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.reply(ref Rmsg.Stat(tm.tag, tm.fid, fileinfo(mf)));
		Remove =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			srv.chanfree(c);
			parent := mf.parent;
			if (!modeok(OWRITE, parent.perm, c.uname, parent.owner))
				err = Styxlib->Eperm;
			if (err == "" && (mf.perm & CHDIR) && mf.kids != nil)
				err = "directory not empty";
			if (err == "" && mf == root)
				err = "root directory";
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}

			unlink(mf);
			if (c.open)
				mf.nopen--;
			freeblks += delfile(qhash, mf);
			srv.reply(ref Rmsg.Remove(tm.tag, tm.fid));
		Wstat =>
			(err, c, mf) := fidtomf(srv, qhash, tm.fid);
			stat := tm.stat;
			perm := mf.perm & ~CHDIR;
			if (err == nil && stat.name != mf.name) {
				parent := mf.parent;
				if (!modeok(OWRITE, parent.perm, c.uname, parent.owner))
					err = Styxlib->Eperm;
				else if (dirlookup(parent, stat.name) != nil)
					err = Styxlib->Eexists;
			}
			if (err == nil && (stat.mode != mf.perm || stat.mtime != mf.mtime)) {
				if (c.uname != mf.owner)
					err = Styxlib->Eperm;
			}
			if (err != nil) {
				srv.reply(ref Rmsg.Error(tm.tag, err));
				continue;
			}
			isdir := mf.perm & CHDIR;
			mf.name = stat.name;
			mf.perm = stat.mode | isdir;
			mf.mtime = stat.mtime;
			t := now();
			mf.atime = t;
			mf.parent.mtime = t;
			# not supporting group id at the moment
			srv.reply(ref Rmsg.Wstat(tm.tag, tm.fid));
		Attach =>
			c := srv.newchan(tm.fid);
			if (c == nil) {
				srv.reply(ref Rmsg.Error(tm.tag, Styxlib->Einuse));
				continue;
			}
			c.uname = tm.uname;
			c.qid = root.qid;
			srv.reply(ref Rmsg.Attach(tm.tag, tm.fid, c.qid));
		}
	}
}

Qidhash.new() : ref Qidhash
{
	qh := ref Qidhash;
	qh.buckets = array [256] of ref Memfile;
	qh.nextqid = 0;
	return qh;
}

Qidhash.add(h : self ref Qidhash, mf : ref Memfile)
{
	qid := h.nextqid++ & ~CHDIR;
	mf.qid = Sys->Qid(qid, 0);
	bix := qid % len h.buckets;
	mf.hashnext = h.buckets[bix];
	h.buckets[bix] = mf;
}

Qidhash.remove(h : self ref Qidhash, mf : ref Memfile)
{

	bix := (mf.qid.path & ~CHDIR) % len h.buckets;
	prev : ref Memfile;
	for (cur := h.buckets[bix]; cur != nil; cur = cur.hashnext) {
		if (cur == mf)
			break;
		prev = cur;
	}
	if (cur != nil) {
		if (prev != nil)
			prev.hashnext = cur.hashnext;
		else
			h.buckets[bix] = cur.hashnext;
		cur.hashnext = nil;
	}
}

Qidhash.lookup(h : self ref Qidhash, qid : Sys->Qid) : ref Memfile
{
#	sys->print("HASH DUMP\n");
#	for (i := 0; i < len h.buckets; i++) {
#		if (h.buckets[i] != nil) {
#			sys->print("[%d]", i);
#			for (mf := h.buckets[i]; mf != nil; mf = mf.hashnext)
#				sys->print("%s(%x)->", mf.name, mf.qid.path);
#			sys->print("nil\n");
#		}
#	}

	bix := (qid.path & ~CHDIR) % len h.buckets;
	for (mf := h.buckets[bix]; mf != nil; mf = mf.hashnext)
		if (mf.qid.path == qid.path)
			break;
	return mf;
}

newmf(qh : ref Qidhash, parent : ref Memfile, name, owner : string, perm : int) : ref Memfile
{
	# qid gets set by Qidhash.add()
	t := now();
	mf := ref Memfile (name, owner, Sys->Qid(0,0), perm, t, t, 0, nil, 0, parent, nil, nil, nil, nil);
	qh.add(mf);
	mf.qid.path |= (perm & CHDIR);
	return mf;
}

fidtomf(srv : ref Styxserver, qh : ref Qidhash, fid : int) : (string, ref Styxlib->Chan, ref Memfile)
{
	c := srv.fidtochan(fid);
	if (c == nil)
		return (Styxlib->Ebadfid, nil, nil);
	mf := qh.lookup(c.qid);
	if (mf == nil)
		return (Styxlib->Enotfound, c, nil);
	return (nil, c, mf);
}

unlink(mf : ref Memfile)
{
	parent := mf.parent;
	if (parent == nil)
		return;
	if (mf.next != nil)
		mf.next.prev = mf.prev;
	if (mf.prev != nil)
		mf.prev.next = mf.next;
	else
		mf.parent.kids = mf.next;
	mf.parent = nil;
	mf.prev = nil;
	mf.next = nil;
}

delfile(qh : ref Qidhash, mf : ref Memfile) : int
{
	if (mf.nopen <= 0 && mf.parent == nil && mf.kids == nil
	&& mf.prev == nil && mf.next == nil) {
		qh.remove(mf);
		nblks := len mf.data / blksz;
		mf.data = nil;
		return nblks;
	}
	return 0;
}

dirlookup(dir : ref Memfile, name : string) : ref Memfile
{
	if (name == ".")
		return dir;
	if (name == "..")
		return dir.parent;
	for (mf := dir.kids; mf != nil; mf = mf.next) {
		if (mf.name == name)
			break;
	}
	return mf;
}

access := array[] of {8r400, 8r200, 8r600, 8r100};
modeok(mode, perm : int, user, owner : string) : int
{
	if(mode >= (OTRUNC|ORCLOSE|OREAD|OWRITE))
		return 0;

	# not handling groups!
	if (user != owner)
		perm <<= 6;
	
	if ((mode & OTRUNC) && !(perm & 8r200))
		return 0;

	a := access[mode &3];
	if ((a & perm) != a)
		return 0;
	return 1;
}

dirdata(dir : ref Memfile, start, n : int) : array of byte
{
	nfiles := 0;
	startmf : ref Memfile;
	for (k := dir.kids; k != nil; k = k.next) {
		if (start-- == 0)
			startmf = k;
		if (startmf != nil)
			nfiles++;
	}
	if (nfiles > n)
		nfiles = n;

	data := array [Styxlib->DIRLEN * nfiles] of byte;
	for (k = startmf; nfiles > 0; k = k.next) {
		nfiles--;
		styxlib->convD2M(data[nfiles * Styxlib->DIRLEN:], fileinfo(k));
	}
	return data;
}

fileinfo(f : ref Memfile) : Sys->Dir
{
	dir : Sys->Dir;
	dir.name = f.name;
	dir.uid = f.owner;
	dir.gid = "memfs";
	dir.qid = f.qid;
	dir.mode = f.perm;
	dir.atime = f.atime;
	dir.mtime = f.mtime;
	dir.length = f.length;
	dir.dtype = 'X';
	dir.dev = 0;		# what should this be?
	return dir;
}

min(a, b : int) : int
{
	if (a < b)
		return a;
	return b;
}

max(a, b : int) : int
{
	if (a > b)
		return a;
	return b;
}

now(): int
{
	if (timefd == nil)
		return 0;
	buf := array[128] of byte;
	sys->seek(timefd, 0, 0);
	n := sys->read(timefd, buf, len buf);
	if(n < 0)
		return 0;

	t := (big string buf[0:n]) / big 1000000;
	return int t;
}
