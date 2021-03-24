implement ISO9660;

include "sys.m";
	sys: Sys;

include "draw.m";

include "daytime.m";
	daytime:	Daytime;

include "string.m";
	str: String;

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;

include "iobuf.m";
	iobuf: Iobuf;
	Block, Device: import iobuf;

include "xfiles.m";
	xfiles:	Xfiles;
	Oread, Owrite, Orclose, Omodes: import Xfiles;
	Xfile, Xfs: import xfiles;

include "arg.m";

ISO9660: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Sectorsize: con 2048;

Enonexist:	con "file does not exist";
Eperm:	con "permission denied";
Enofile:	con "no file system specified";
Eauth:	con "authentication failed";
Ebadfid:	con	"invalid fid";
Efidinuse:	con	"fid already in use";
Enotdir:	con	"not a directory";
Esyntax:	con	"file name syntax";

fdata := array[Sys->ATOMICIO] of byte;

devname: string;

chatty := 0;
showstyx := 0;
progname := "9660srv";

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	sys->pctl(Sys->FORKFD|Sys->NEWPGRP, nil);
	if(args != nil)
		progname = hd args;
	styx = load Styx Styx->PATH;
	if(styx == nil)
		noload(Styx->PATH);
	styx->init();

	if(args != nil)
		progname = hd args;
	mountopt := Sys->MREPL;
	copt := 0;
	stdio := 0;

	arg := load Arg Arg->PATH;
	if(arg == nil)
		noload(Arg->PATH);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'v' or 'D' => chatty = 1; showstyx = 1;
		'r' => mountopt = Sys->MREPL;
		'a' => mountopt = Sys->MAFTER;
		'b' => mountopt = Sys->MBEFORE;
		'c' => copt = Sys->MCREATE;
		's' => stdio = 1;
		* => usage();
		}
	args = arg->argv();
	arg = nil;

	if(args == nil || tl args == nil)
		usage();
	what := hd args;
	where := hd tl args;

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		noload(Daytime->PATH);
	iobuf = load Iobuf Iobuf->PATH;
	if(iobuf==nil)
		noload(Iobuf->PATH);
	iobuf->init(Sectorsize);

	xfiles = load Xfiles Xfiles->ISOPATH;
	if(xfiles == nil)
		noload(Xfiles->ISOPATH);
	xfiles->init(iobuf, styx);

	pip := array[2] of ref Sys->FD;
	if(stdio){
		pip[0] = sys->fildes(0);
		pip[1] = sys->fildes(1);
	}else
		if(sys->pipe(pip) < 0)
			error(sys->sprint("can't create pipe: %r"));

	devname = what;

	sync := chan of int;
	spawn fileserve(pip[1], sync);
	<-sync;

	if(sys->mount(pip[0], where, mountopt|copt, nil) < 0) {
		sys->fprint(sys->fildes(2), "%s: mount %s %s failed: %r\n", progname, what, where);
		exit;
	}
}

noload(s: string)
{
	sys->fprint(sys->fildes(2), "%s: can't load %s: %r\n", progname, s);
	sys->raise("fail:load");
}

usage()
{
	sys->fprint(sys->fildes(2), "usage: %s [-rabc] cd_device dir\n", progname);
	sys->raise("fail:usage");
}

error(p: string)
{
	sys->fprint(sys->fildes(2), "9660srv: %s\n", p);
	sys->raise("fail:error");
}

fileserve(rfd: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->NEWFD|Sys->FORKNS, list of {2, rfd.fd});
	sync <-= 1;
	while((m := Tmsg.read(rfd, 0)) != nil){
		if(showstyx)
			chat(sys->sprint("%s...", m.text()));
		r: ref Rmsg;
		pick t := m {
		Readerror =>
			error(sys->sprint("mount read error: %s", t.error));
		Nop =>
 			r = rnop(t);
		Flush =>
 			r = rflush(t);
		Attach =>
 			r = rattach(t);
		Clone =>
 			r = rclone(t);
		Walk =>
 			r = rwalk(t);
		Open =>
 			r = ropen(t);
		Create =>
 			r = rcreate(t);
		Read =>
 			r = rread(t);
		Write =>
 			r = rwrite(t);
		Clunk =>
 			r = rclunk(t);
		Remove =>
 			r = rremove(t);
		Stat =>
 			r = rstat(t);
		Wstat =>
 			r = rwstat(t);
		* =>
			error(sys->sprint("invalid T-message tag: %d", tagof m));
		}
		pick e := r {
		Error =>
			r.tag = m.tag;
		}
		rbuf := r.pack();
		if(rbuf == nil)
			error("bad R-message conversion");
		if(showstyx)
			chat(r.text()+"\n");
		if(sys->write(rfd, rbuf, len rbuf) != len rbuf)
			error(sys->sprint("connection write error: %r"));
	}

	if(chatty)
		chat("server end of file\n");
}

E(s: string): ref Rmsg.Error
{
	return ref Rmsg.Error(0, s);
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
	dname := devname;
	if(t.aname != "")
		dname = t.aname;
	(dev, err) := iobuf->attach(dname, Sys->OREAD, Sectorsize);
	if(dev == nil)
		return E(err);

	xf := Xfs.new(dev);
	root := cleanfid(t.fid);
	root.qid = Sys->Qid(Sys->CHDIR, 0);
	root.xf = xf;
	err = root.attach();
	if(err != nil){
		clunkfid(t.fid);
		return E(err);
	}
	xf.rootqid = root.qid;
	return ref Rmsg.Attach(t.tag, t.fid, root.qid);
}

rclone(t: ref Tmsg.Clone): ref Rmsg
{
	oldf := findfid(t.fid);
	if(oldf == nil)
		return E(Ebadfid);
	newf := cleanfid(t.newfid);
	if(newf == nil)
		return E(Efidinuse);
	oldf.clone(newf);
	return ref Rmsg.Clone(t.tag, t.fid);
}

rwalk(t: ref Tmsg.Walk): ref Rmsg
{
	f:=findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if(!(f.qid.path & Sys->CHDIR))
		return E(Enotdir);
	e: string;
	name := t.name;
	if(name == ".")
		;	# nop, but shouldn't happen
	else if(name == ".."){
		if(f.qid.path!=f.xf.rootqid.path)
			e = f.walkup();
	}else
		e = f.walk(name);
	if(e != nil)
		return E(e);
	return ref Rmsg.Walk(t.tag, t.fid, f.qid);
}

ropen(t: ref Tmsg.Open): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if(f.flags&Omodes)
		return E("open on open file");
	e := f.open(t.mode);
	if(e != nil)
		return E(e);
	f.flags = openflags(t.mode);
	return ref Rmsg.Open(t.tag, t.fid, f.qid);
}

rcreate(t: ref Tmsg.Create): ref Rmsg
{
	name := t.name;
	if(name == "." || name == "..")
		return E(Esyntax);
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if(f.flags&Omodes)
		return E("create on open file");
	if(!(f.qid.path&Sys->CHDIR))
		return E("create in non-directory");
	e := f.create(name, t.perm, t.mode);
	if(e != nil)
		return E(e);
	f.flags = openflags(t.mode);
	return ref Rmsg.Create(t.tag, t.fid, f.qid);
}

rread(t: ref Tmsg.Read): ref Rmsg
{
	err: string;

	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	if (!(f.flags&Oread))
		return E("file not opened for reading");
	count: int;
	if(f.qid.path & Sys->CHDIR){
		if(t.count%Styx->DIRLEN || int t.offset%Styx->DIRLEN)
			return E("bad offset or count");
		(count, err) = f.readdir(fdata, int t.offset, t.count);
	}else
		(count, err) = f.read(fdata, int t.offset, t.count);
	if(err != nil)
		return E(err);
	b := fdata;
	if(count != len fdata)
		b = fdata[0:count];
	return ref Rmsg.Read(t.tag, t.fid, b);
}

rwrite(nil: ref Tmsg.Write): ref Rmsg
{
	return E(Eperm);
}

rclunk(t: ref Tmsg.Clunk): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	f.clunk();
	clunkfid(t.fid);
	return ref Rmsg.Clunk(t.tag, t.fid);
}

rremove(t: ref Tmsg.Remove): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	f.clunk();
	clunkfid(t.fid);
	return E(Eperm);
}

rstat(t: ref Tmsg.Stat): ref Rmsg
{
	f := findfid(t.fid);
	if(f == nil)
		return E(Ebadfid);
	(dir, nil) := f.stat();
	return ref Rmsg.Stat(t.tag, t.fid, *dir);
}

rwstat(nil: ref Tmsg.Wstat): ref Rmsg
{
	return E(Eperm);
}

openflags(mode: int): int
{
	flags := 0;
	case mode & ~(Sys->OTRUNC|Sys->ORCLOSE) {
	Sys->OREAD =>
		flags = Oread;
	Sys->OWRITE =>
		flags = Owrite;
	Sys->ORDWR =>
		flags = Oread|Owrite;
	}
	if(mode & Sys->ORCLOSE)
		flags |= Orclose;
	return flags;
}

chat(s: string)
{
	if(chatty)
		sys->fprint(sys->fildes(2), "%s", s);
}

Fid: adt {
	fid:	int;
	file:	ref Xfile;
};

FIDMOD: con 127;	# prime
fids := array[FIDMOD] of list of ref Fid;

hashfid(fid: int): (ref Fid, array of list of ref Fid)
{
	nl: list of ref Fid;

	hp := fids[fid%FIDMOD:];
	nl = nil;
	for(l := hp[0]; l != nil; l = tl l){
		f := hd l;
		if(f.fid == fid){
			l = tl l;	# excluding f
			for(; nl != nil; nl = tl nl)
				l = (hd nl) :: l;	# put examined ones back, in order
			hp[0] = l;
			return (f, hp);
		} else
			nl = f :: nl;
	}
	return (nil, hp);
}

findfid(fid: int): ref Xfile
{
	(f, hp) := hashfid(fid);
	if(f == nil){
		chat("unassigned fid");
		return nil;
	}
	hp[0] = f :: hp[0];
	return f.file;
}

cleanfid(fid: int): ref Xfile
{
	(f, hp) := hashfid(fid);
	if(f != nil){
		chat("fid in use");
		return nil;
	}
	f = ref Fid;
	f.fid = fid;
	f.file = Xfile.new();
	hp[0] = f :: hp[0];
	return f.file.clean();
}

clunkfid(fid: int)
{
	(f, nil) := hashfid(fid);
	if(f != nil)
		f.file.clean();
}
