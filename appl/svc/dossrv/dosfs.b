implement Dosfs;

include "sys.m";
	sys : Sys;
	sprint: import sys;

include "iotrack.m";
	iotrack : IoTrack;
	Xfs,Xfile: import iotrack;

include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

include "dosfs.m";

include "dossubs.m";
	dos: DosSubs;
	Dosptr,Dosbpb, Dosdir, DOSDIRSIZE, DLONG, DOSEMPTY: import dos;
	QIDPATH: import dos;

g: ref dos->Global;
debug := 0;

	Enevermind,
	Eformat,
	Eio,
	Enomem,
	Enonexist,
	Eexist,
	Eperm,
	Enofilsys,
	Eauth,
	Econtig,
	Efull,
	Eopen,
	Ephase: con iota;

errmsg := array[] of {
	Enevermind	=> "never mind",
	Eformat		=> "unknown format",
	Eio		=> "I/O error",
	Enomem		=> "server out of memory",
	Enonexist	=> "file does not exist",
	Eexist		=> "file exists",
	Eperm		=> "permission denied",
	Enofilsys	=> "no file system device specified",
	Eauth		=> "authentication failed",
	Econtig =>	"out of contiguous disk space",
	Efull =>	"file system full",
	Eopen =>	"invalid open mode",
	Ephase => "phase error -- directory entry not found",
};

init(deffile: string, logfile: string, chatty: int, sect2trk: int): string
{
	g = ref dos->Global;
	sys = load Sys Sys->PATH;

	# Try to load from the normal file system,
	# if it fails try loading from kernel root

	styx = load Styx Styx->PATH;
	if(styx == nil)
		styx = load Styx "/dis/svc/dossrv/styx.dis";	# old file system location
	if(styx == nil)
		styx = load Styx "#/./styx";
	iotrack = load IoTrack IoTrack->PATH;
if(iotrack==nil)sys->print("iotrack: %r\n");
	if(iotrack == nil)
		iotrack = load IoTrack "#/./iotrack";
	dos = load DosSubs DosSubs->PATH;
	if(dos == nil)
		dos = load DosSubs "#/./dossubs";
if(styx==nil)sys->print("styx");if(iotrack==nil)sys->print("iotrack");
	if(styx == nil || iotrack == nil || dos == nil)
		return "can't load required module";
	styx->init();

	g.dos = dos;
	g.styx = styx;
	g.deffile = deffile;
	g.logfile = logfile;
	g.chatty = chatty;
	g.iotrack = iotrack;
	debug = chatty & dos->STYX_MESS;

	dos->init(g);
	iotrack->init(g, sect2trk);

	return nil;
}

setup()
{
	dos->setup();
}

e(n: int): ref Rmsg.Error
{
	if(n < 0 || n >= len errmsg)
		return ref Rmsg.Error(0, "it's thermal problems");
	return ref Rmsg.Error(0, errmsg[n]);
}

rnop(t: ref Tmsg.Nop): ref Rmsg
{
	return ref Rmsg.Nop(t.tag);
}

rflush(t: ref Tmsg.Flush): ref Rmsg
{
	return ref Rmsg.Flush(t.tag);
}

rattach(t: ref Tmsg.Attach): ref Rmsg
{
	root := iotrack->xfile(t.fid, dos->Clean);
	if(root == nil)
		return e(Eio);
	(xf, ec) := iotrack->getxfs(t.aname);
	root.xf = xf;
	if(xf == nil) {
		if(root!=nil)
			iotrack->xfile(t.fid, dos->Clunk);
		return ref Rmsg.Error(t.tag, ec);
	}
	if(xf.fmt == 0 && dos->dosfs(xf) < 0){
		if(root!=nil)
			iotrack->xfile(t.fid, dos->Clunk);
		return e(Eformat);
	}

	root.qid.path = Sys->CHDIR;
	root.qid.vers = 0;
	root.xf.rootqid = root.qid;
	return ref Rmsg.Attach(t.tag, t.fid, root.qid);
}

rclone(t: ref Tmsg.Clone): ref Rmsg
{
	ofl := iotrack->xfile(t.fid, dos->Asis);
	if(ofl == nil)
		return e(Eio);
	nfl := iotrack->xfile(t.newfid, dos->Clean);
	if(nfl == nil)
		return e(Eio);
	next := nfl.next;
	dp := nfl.ptr;
	*nfl = *ofl;
	nfl.ptr = dp;
	nfl.next = next;
	nfl.fid = t.newfid;
	iotrack->refxfs(nfl.xf, 1);
	*nfl.ptr = *ofl.ptr;
	dp.p = nil;
	return ref Rmsg.Clone(t.tag, t.fid);
}

rwalk(t: ref Tmsg.Walk): ref Rmsg
{
	f := iotrack->xfile(t.fid, dos->Asis);
	if(f==nil) {
		if(debug)
			dos->chat("no xfile...");
		return e(Enonexist);
	}

	if((f.qid.path & Sys->CHDIR) == 0){
		if(debug)
			dos->chat(sprint("qid.path=0x%x...", f.qid.path));
		return e(Enonexist);
	}

	if(t.name == ".")	# can't happen
		return ref Rmsg.Walk(t.tag, t.fid, f.qid);

	if(t.name== "..") {
		if(f.qid.path==f.xf.rootqid.path) {
			if (debug)
				dos->chat("walkup from root...");
			return ref Rmsg.Walk(t.tag, t.fid, f.qid);
		}
		(r,dp) := dos->walkup(f);
		if(r < 0)
			return e(Enonexist);

		f.ptr=dp;
		if(dp.addr == 0)
			f.qid.path = f.xf.rootqid.path;
		else
			f.qid.path = Sys->CHDIR | QIDPATH(dp);
	}
	else {
		if(dos->getfile(f) < 0)
			return e(Enonexist);
		(r,dp) := dos->searchdir(f, t.name, 0,1);
		dos->putfile(f);
		if(r < 0)
			return e(Enonexist);

		f.ptr=dp;
		f.qid.path = QIDPATH(dp);
		if(dp.addr == 0)
			f.qid.path = f.xf.rootqid.path;
		else {
			d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
			if((int d.attr & dos->DDIR) !=  0)
				f.qid.path |= Sys->CHDIR;
		}
		dos->putfile(f);
	}
	return ref Rmsg.Walk(t.tag, t.fid, f.qid);
}

ropen(t: ref Tmsg.Open): ref Rmsg
{
	attr: int;

	omode := 0;
	f := iotrack->xfile(t.fid, dos->Asis);
	if(f == nil || (f.flags&dos->Omodes) != 0)
		return e(Eio);

	dp := f.ptr;
	if(dp.paddr && (t.mode & Styx->ORCLOSE) != 0) {
		# check on parent directory of file to be deleted
		p := iotrack->getsect(f.xf, dp.paddr);
		if(p == nil)
			return e(Eio);
		# 11 is the attr byte offset in a FAT directory entry
		attr = int p.iobuf[dp.poffset+11];
		iotrack->putsect(p);
		if((attr & int dos->DRONLY) != 0)
			return e(Eperm);
		omode |= dos->Orclose;
	} else if(t.mode & Styx->ORCLOSE)
		omode |= dos->Orclose;

	if(dos->getfile(f) < 0)
		return e(Enonexist);

	if(dp.addr != 0) {
		d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
		attr = int d.attr;
	} else
		attr = int dos->DDIR;

	case t.mode & 7 {
	Styx->OREAD or
	Styx->OEXEC =>
		omode |= dos->Oread;
	Styx->ORDWR =>
		omode |= dos->Oread;
		omode |= dos->Owrite;
		if(attr & int (dos->DRONLY|dos->DDIR)) {
			dos->putfile(f);
			return e(Eperm);
		}
	Styx->OWRITE =>
		omode |= dos->Owrite;
		if(attr & int (dos->DRONLY|dos->DDIR)) {
			dos->putfile(f);
			return e(Eperm);
		}
	* =>
		dos->putfile(f);
		return e(Eopen);
	}

	if(t.mode & Styx->OTRUNC) {
		if((attr & int dos->DDIR)!=0 || (attr & int dos->DRONLY) != 0) {
			dos->putfile(f);
			return e(Eperm);
		}

		if(dos->truncfile(f) < 0) {
			dos->putfile(f);
			return e(Eio);
		}
	}

	f.flags |= omode;
	dos->putfile(f);
	return ref Rmsg.Open(t.tag, t.fid, f.qid);
}

mkdentry(xf: ref Xfs, ndp: ref Dosptr, name: string, sname: string, islong: int, nattr: byte, start: array of byte, length: array of byte): int
{
	ndp.p = iotrack->getsect(xf, ndp.addr);
	if(ndp.p == nil)
		return Eio;
	if(islong && (r := dos->putlongname(xf, ndp, name, sname)) < 0){
		iotrack->putsect(ndp.p);
		if(r == -2)
			return Efull;
		return Eio;
	}

	nd := ref Dosdir(".       ","   ",byte 0,array[10] of { * => byte 0},
			array[2] of { * => byte 0}, array[2] of { * => byte 0},
			array[2] of { * => byte 0},array[4] of { * => byte 0});

	nd.attr = nattr;
	dos->puttime(nd);
	nd.start[0: ] = start[0: 2];
	nd.length[0: ] = length[0: 4];

	if(islong)
		dos->putname(sname[0:8]+"."+sname[8:11], nd);
	else
		dos->putname(name, nd);
	ndp.p.iobuf[ndp.offset: ] = Dosdir.Dd2arr(nd);
	ndp.p.flags |= IoTrack->BMOD;
	return 0;
}

rcreate(t: ref Tmsg.Create): ref Rmsg
{
	bp: ref Dosbpb;
	omode:=0;
	start:=0;
	sname := "";
	islong :=0;

	f := iotrack->xfile(t.fid, dos->Asis);
	if(f == nil || (f.flags&dos->Omodes) || dos->getfile(f)<0)
		return e(Eio);

	pdp := f.ptr;
	if(pdp.addr != 0)
		pd := Dosdir.arr2Dd(pdp.p.iobuf[pdp.offset:pdp.offset+DOSDIRSIZE]);
	else
		pd = nil;

	if(pd != nil)
		attr := int pd.attr;
	else
		attr = dos->DDIR;

	if(!(attr & dos->DDIR) || (attr & dos->DRONLY)) {
		dos->putfile(f);
		return e(Eperm);
	}

	if(t.mode & Styx->ORCLOSE)
		omode |= dos->Orclose;

	case (t.mode & 7) {
	Styx->OREAD or
	Styx->OEXEC =>
		omode |= dos->Oread;
	Styx->OWRITE or
	Styx->ORDWR =>
		if ((t.mode & 7) == Styx->ORDWR)
			omode |= dos->Oread;
		omode |= dos->Owrite;
		if(t.perm & Sys->CHDIR){
			dos->putfile(f);
			return e(Eperm);
		}
	* =>
		dos->putfile(f);
		return e(Eopen);
	}

	if(t.name=="." || t.name=="..") {
		dos->putfile(f);
		return e(Eperm);
	}

	(r,ndp) := dos->searchdir(f, t.name, 1, 1);
	if(r < 0) {
		dos->putfile(f);
		if(r == -2)
			return e(Efull);
		return e(Eexist);
	}

	nds := dos->name2de(t.name);
	if(nds > 0) {
		# long file name, find "new" short name
		i := 1;
		for(;;) {
			sname = dos->long2short(t.name, i);
			(r1, tmpdp) := dos->searchdir(f, sname, 0, 0);
			if(r1 < 0)
				break;
			iotrack->putsect(tmpdp.p);
			i++;
		}
		islong = 1;
	}

	# allocate first cluster, if making directory
	if(t.perm & Sys->CHDIR) {
		bp = f.xf.ptr;
		start = dos->falloc(f.xf);
		if(start <= 0) {
			dos->putfile(f);
			return e(Efull);
		}
	}

	 # now we're committed
	if(pd != nil) {
		dos->puttime(pd);
		pdp.p.flags |= IoTrack->BMOD;
	}

	f.ptr = ndp;
	ndp.p = iotrack->getsect(f.xf, ndp.addr);
	if(ndp.p == nil ||
	   islong && dos->putlongname(f.xf, ndp, t.name, sname) < 0){
		iotrack->putsect(pdp.p);
		if(ndp.p != nil)
			iotrack->putsect(ndp.p);
		return e(Eio);
	}

	nd := ref Dosdir(".       ","   ",byte 0,array[10] of { * => byte 0},
			array[2] of { * => byte 0}, array[2] of { * => byte 0},
			array[2] of { * => byte 0},array[4] of { * => byte 0});

	if((t.perm & 8r222) == 0)
		nd.attr |= byte dos->DRONLY;

	dos->puttime(nd);
	nd.start[0] = byte start;
	nd.start[1] = byte (start>>8);

	if(islong)
		dos->putname(sname[0:8]+"."+sname[8:11], nd);
	else
		dos->putname(t.name, nd);

	f.qid.path = QIDPATH(ndp);
	if(t.perm & Sys->CHDIR) {
		nd.attr |= byte dos->DDIR;
		f.qid.path |= Sys->CHDIR;
		xp := iotrack->getsect(f.xf, bp.dataaddr+(start-2)*bp.clustsize);
		if(xp == nil) {
			if(ndp.p!=nil)
				dos->putfile(f);
			iotrack->putsect(pdp.p);
			return e(Eio);
		}
		xd := ref *nd;
		xd.name = ".       ";
		xd.ext = "   ";
		xp.iobuf[0:] = Dosdir.Dd2arr(xd);
		if(pd!=nil)
			xd = ref *pd;
		else{
			xd = ref Dosdir("..      ","   ",byte 0,
				array[10] of { * => byte 0},
				array[2] of { * => byte 0},
				array[2] of { * => byte 0},
				array[2] of { * => byte 0},
				array[4] of { * => byte 0});

			dos->puttime(xd);
			xd.attr = byte dos->DDIR;
		}
		xd.name="..      ";
		xd.ext="   ";
		xp.iobuf[DOSDIRSIZE:] = Dosdir.Dd2arr(xd);
		xp.flags |= IoTrack->BMOD;
		iotrack->putsect(xp);
	}

	ndp.p.flags |= IoTrack->BMOD;
	tmp := Dosdir.Dd2arr(nd);
	ndp.p.iobuf[ndp.offset:]= tmp;
	dos->putfile(f);
	iotrack->putsect(pdp.p);

	f.flags |= omode;
	return ref Rmsg.Create(t.tag, t.fid, f.qid);
}

rread(t: ref Tmsg.Read): ref Rmsg
{
	r : int;
	data : array of byte;

	if(((f:=iotrack->xfile(t.fid, dos->Asis))==nil) ||
	    (f.flags&dos->Oread == 0))
		return e(Eio);

	if((f.qid.path & Sys->CHDIR) != 0) {
		t.count = (t.count/Styx->DIRLEN)*Styx->DIRLEN;
		if(t.count < Styx->DIRLEN || int t.offset%Styx->DIRLEN) {
			if(debug)
				dos->chat(sprint("count=%d,offset=%bd,DIRLEN=%d...",
					t.count, t.offset, Styx->DIRLEN));
			return e(Eio);
		}
		if(dos->getfile(f) < 0)
			return e(Eio);
		(r, data) = dos->readdir(f, int t.offset, t.count);
	} else {
		if(dos->getfile(f) < 0)
			return e(Eio);
		(r,data) = dos->readfile(f, int t.offset, t.count);
	}
	dos->putfile(f);

	if(r < 0)
		return e(Eio);
	return ref Rmsg.Read(t.tag, t.fid, data[0:r]);	# TO DO: check whether slice is needed
}

rwrite(t: ref Tmsg.Write): ref Rmsg
{
	if(((f:=iotrack->xfile(t.fid, dos->Asis))==nil) ||
	   !(f.flags&dos->Owrite))
		return e(Eio);
	if(dos->getfile(f) < 0)
		return e(Eio);
	r := dos->writefile(f, t.data, int t.offset, len t.data);
	dos->putfile(f);
	if(r < 0){
		if(r == -2)
			return e(Efull);
		return e(Eio);
	}
	return ref Rmsg.Write(t.tag, t.fid, r);
}

rclunk(t: ref Tmsg.Clunk): ref Rmsg
{
	iotrack->xfile(t.fid, dos->Clunk);
	iotrack->sync();
	return ref Rmsg.Clunk(t.tag, t.fid);
}

doremove(f: ref Xfs, dp: ref Dosptr)
{
	dp.p.iobuf[dp.offset] = byte DOSEMPTY;
	dp.p.flags |= IoTrack->BMOD;
	for(prevdo := dp.offset-DOSDIRSIZE; prevdo >= 0; prevdo-=DOSDIRSIZE){
		if (dp.p.iobuf[prevdo+11] != byte DLONG)
			break;
		dp.p.iobuf[prevdo] = byte DOSEMPTY;
	}

	if (prevdo <= 0 && dp.prevaddr != -1){
		p := iotrack->getsect(f,dp.prevaddr);
		for(prevdo = f.ptr.sectsize-DOSDIRSIZE; prevdo >= 0; prevdo-=DOSDIRSIZE) {
			if(p.iobuf[prevdo+11] != byte DLONG)
				break;
			p.iobuf[prevdo] = byte DOSEMPTY;
			p.flags |= IoTrack->BMOD;
		}
		iotrack->putsect(p);
	}
}

rremove(t: ref Tmsg.Remove): ref Rmsg
{
	f := iotrack->xfile(t.fid, dos->Asis);
	if(f == nil) {
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eio);
	}

	if(!f.ptr.addr) {
		if(debug)
			dos->chat("root...");
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eperm);
	}

	# check on parent directory of file to be deleted
	parp := iotrack->getsect(f.xf, f.ptr.paddr);
	if(parp == nil) {
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eio);
	}

	pard := Dosdir.arr2Dd(parp.iobuf[f.ptr.poffset:f.ptr.poffset+DOSDIRSIZE]);
	if(f.ptr.paddr && (int pard.attr & dos->DRONLY)) {
		if(debug)
			dos->chat("parent read-only...");
		iotrack->putsect(parp);
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eperm);
	}

	if(dos->getfile(f) < 0){
		if(debug)
			dos->chat("getfile failed...");
		iotrack->putsect(parp);
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eio);
	}

	dattr := int f.ptr.p.iobuf[f.ptr.offset+11];
	if(dattr & dos->DDIR && dos->emptydir(f) < 0){
		if(debug)
			dos->chat("non-empty dir...");
		dos->putfile(f);
		iotrack->putsect(parp);
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eperm);
	}
	if(f.ptr.paddr == 0 && dattr&dos->DRONLY) {
		if(debug)
			dos->chat("read-only file in root directory...");
		dos->putfile(f);
		iotrack->putsect(parp);
		iotrack->xfile(t.fid, dos->Clunk);
		iotrack->sync();
		return e(Eperm);
	}

	doremove(f.xf, f.ptr);

	if(f.ptr.paddr) {
		dos->puttime(pard);
		parp.flags |= IoTrack->BMOD;
	}

	parp.iobuf[f.ptr.poffset:] = Dosdir.Dd2arr(pard);
	iotrack->putsect(parp);
	err := 0;
	if(dos->truncfile(f) < 0)
		err = Eio;

	dos->putfile(f);
	iotrack->xfile(t.fid, dos->Clunk);
	iotrack->sync();
	if(err)
		return e(err);
	return ref Rmsg.Remove(t.tag, t.fid);
}

rstat(t: ref Tmsg.Stat): ref Rmsg
{
	f := iotrack->xfile(t.fid, dos->Asis);
	if(f == nil || dos->getfile(f) < 0)
		return e(Eio);
	dir := dostat(f);
	dos->putfile(f);
	return ref Rmsg.Stat(t.tag, t.fid, *dir);
}

dostat(f: ref Xfile): ref Sys->Dir
{
	islong :=0;
	prevdo : int;
	longnamebuf:="";

	# get file info.
	dir := dos->getdir(f.ptr.p.iobuf[f.ptr.offset:f.ptr.offset+DOSDIRSIZE],
					f.ptr.addr, f.ptr.offset);
	# get previous entry
	if(f.ptr.prevaddr == -1) {
		# maybe extended, but will never cross sector boundary...
		# short filename at beginning of sector..
		if(f.ptr.offset!=0) {
			for(prevdo = f.ptr.offset-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE) {
				prevdattr := f.ptr.p.iobuf[prevdo+11];
				if(prevdattr != byte DLONG)
					break;
				islong = 1;
				longnamebuf += dos->getnamesect(f.ptr.p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
			}
		}
	} else {
		# extended and will cross sector boundary.
		for(prevdo = f.ptr.offset-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE) {
			prevdattr := f.ptr.p.iobuf[prevdo+11];
			if(prevdattr != byte DLONG)
				break;
			islong = 1;
			longnamebuf += dos->getnamesect(f.ptr.p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
		}
		if (prevdo < 0) {
			p := iotrack->getsect(f.xf,f.ptr.prevaddr);
			for(prevdo = f.xf.ptr.sectsize-DOSDIRSIZE; prevdo >=0; prevdo-=DOSDIRSIZE){
				prevdattr := p.iobuf[prevdo+11];
				if(prevdattr != byte DLONG)
					break;
				islong = 1;
				longnamebuf += dos->getnamesect(p.iobuf[prevdo:prevdo+DOSDIRSIZE]);
			}
			iotrack->putsect(p);
		}
	}
	if(islong)
		dir.name = longnamebuf;
	return dir;
}

nameok(elem : string) : int
{
	isfrog := array[256] of {
	# NUL
	1, 1, 1, 1, 1, 1, 1, 1,
	# BKS
	1, 1, 1, 1, 1, 1, 1, 1,
	# DLE
	1, 1, 1, 1, 1, 1, 1, 1,
	# CAN
	1, 1, 1, 1, 1, 1, 1, 1,
#	' ' =>	1,
	'/' =>	1, 16r7f =>	1, * => 0
	};

	for(i:=0; i < len elem; i++) {
		if(isfrog[elem[i]])
			return -1;
	}
	if(i >= Styx->NAMELEN)
		return -1;
	return 0;
}

rwstat(t: ref Tmsg.Wstat): ref Rmsg
{
	f := iotrack->xfile(t.fid, dos->Asis);
	if(f == nil)
		return e(Eio);

	if(dos->getfile(f) < 0)
		return e(Eio);

	dp := f.ptr;

	if(dp.addr == 0){	# root
		dos->putfile(f);
		return e(Eperm);
	}

	changes := 0;
	dir := dostat(f);
	wdir := ref t.stat;

	if(dir.uid != wdir.uid || dir.gid != wdir.gid){
		dos->putfile(f);
		return e(Eperm);
	}

	if(dir.mtime != wdir.mtime || ((dir.mode^wdir.mode) & 8r777))
		changes = 1;

	if((wdir.mode & 7) != ((wdir.mode >> 3) & 7)
	|| (wdir.mode & 7) != ((wdir.mode >> 6) & 7)){
		dos->putfile(f);
		return e(Eperm);
	}

	if(dir.name != wdir.name){
		# temporarily disable this
		# g.errno = Eperm;
		# dos->putfile(f);
		# return;

		#
		# grab parent directory of file to be changed and check for write perm
		# rename also disallowed for read-only files in root directory
		#
		parp := iotrack->getsect(f.xf, dp.paddr);
		if(parp == nil){
			dos->putfile(f);
			return e(Eio);
		}
		# pard := Dosdir.arr2Dd(parp.iobuf[dp.poffset: dp.poffset+DOSDIRSIZE]);
		pardattr := int parp.iobuf[dp.poffset+11];
		dpd := Dosdir.arr2Dd(dp.p.iobuf[dp.offset: dp.offset+DOSDIRSIZE]);
		if(dp.paddr != 0 && int pardattr & dos->DRONLY
		|| dp.paddr == 0 && int dpd.attr & dos->DRONLY){
			iotrack->putsect(parp);
			dos->putfile(f);
			return e(Eperm);
		}

		#
		# retrieve info from old entry
		#
		oaddr := dp.addr;
		ooffset := dp.offset;
		d := dpd;
		od := *d;
		# start := getstart(f.xf, d);
		start := d.start;
		length := d.length;
		attr := d.attr;

		#
		# temporarily release file to allow other directory ops:
		# walk to parent, validate new name
		# then remove old entry
		#
		dos->putfile(f);
		pf := ref *f;
		pdp := ref Dosptr(dp.paddr, dp.poffset, 0, 0, 0, 0, -1, -1, parp, nil);
		# if(pdp.addr != 0)
		# 	pdpd := Dosdir.arr2Dd(parp.iobuf[pdp.offset: pdp.offset+DOSDIRSIZE]);
		# else
		# 	pdpd = nil;
		pf.ptr = pdp;
		if(wdir.name == "." || wdir.name == ".."){
			iotrack->putsect(parp);
			return e(Eperm);
		}
		islong := 0;
		sname := "";
		nds := dos->name2de(wdir.name);
		if(nds > 0) {
			# long file name, find "new" short name
			i := 1;
			for(;;) {
				sname = dos->long2short(wdir.name, i);
				(r1, tmpdp) := dos->searchdir(f, sname, 0, 0);
				if(r1 < 0)
					break;
				iotrack->putsect(tmpdp.p);
				i++;
			}
			islong = 1;
		}else{
			(b, e) := dos->dosname(wdir.name);
			sname = b+e;
		}
		# (r, ndp) := dos->searchdir(pf, wdir.name, 1, 1);
		# if(r < 0){
		#	iotrack->putsect(parp);
		#	g.errno = Eperm;
		#	return;
		# }
		if(dos->getfile(f) < 0){
			iotrack->putsect(parp);
			return e(Eio);
		}
		doremove(f.xf, dp);
		dos->putfile(f);

		#
		# search for dir entry again, since we may be able to use the old slot,
		# and we need to set up the naddr field if a long name spans the block.
		# create new entry.
		#
		r := 0;
		(r, dp) = dos->searchdir(pf, sname, 1, islong);
		if(r < 0){
			iotrack->putsect(parp);
			return e(Ephase);
		}
		if((r = mkdentry(pf.xf, dp, wdir.name, sname, islong, attr, start, length)) != 0){
			iotrack->putsect(parp);
			return e(r);
		}
		iotrack->putsect(parp);

		#
		# relocate up other fids to the same file, if it moved
		#
		f.ptr = dp;
		f.qid.path = (f.qid.path & Sys->CHDIR) | QIDPATH(dp);
		if(oaddr != dp.addr || ooffset != dp.offset)
			iotrack->dosptrreloc(f, dp, oaddr, ooffset);
		changes = 1;
		# f = nil;
	}

	if(changes){
		d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
		dos->putdir(d, wdir);
		dp.p.iobuf[dp.offset: ] = Dosdir.Dd2arr(d);
		dp.p.flags |= IoTrack->BMOD;
	}
	if(f != nil)
		dos->putfile(f);
	iotrack->sync();
	return ref Rmsg.Wstat(t.tag, t.fid);
}

dossrv(rfd : ref Sys->FD)
{
	data := array[Styx->MAXRPC] of byte;
	while((t := Tmsg.read(rfd, 0)) != nil){
		if(debug)
			dos->chat(sys->sprint("%s...", t.text()));

		r: ref Rmsg;
		pick m := t {
		Readerror =>
			dos->panic(sys->sprint("mount read error: %s", m.error));
		Nop =>
 			r = rnop(m);
		Flush =>
 			r = rflush(m);
		Attach =>
 			r = rattach(m);
		Clone =>
 			r = rclone(m);
		Walk =>
 			r = rwalk(m);
		Open =>
 			r = ropen(m);
		Create =>
 			r = rcreate(m);
		Read =>
 			r = rread(m);
		Write =>
 			r = rwrite(m);
		Clunk =>
 			r = rclunk(m);
		Remove =>
 			r = rremove(m);
		Stat =>
 			r = rstat(m);
		Wstat =>
 			r = rwstat(m);
		* =>
			dos->panic("Styx mtype");
		}
		pick m := r {
		Error =>
			r.tag = t.tag;
		}
		rbuf := r.pack();
		if(rbuf == nil)
			dos->panic("Rmsg.pack");
		if(debug)
			dos->chat(sys->sprint("%s\n", r.text()));
		if(sys->write(rfd, rbuf, len rbuf) != len rbuf)
			dos->panic("mount write");
	}

	if(debug)
		dos->chat("server EOF\n");
}
