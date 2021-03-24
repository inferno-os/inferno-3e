implement Styx;

include "sys.m";
	sys: Sys;

include "styx.m";

msglen := array[Tmax] of
{
Tnop=> 	3,
Rnop=> 	3,
Terror=> 	0,
Rerror=> 	67,
Tflush=> 	5,
Rflush=> 	3,
Tclone=> 	7,
Rclone=> 	5,
Twalk=> 	33,
Rwalk=> 	13,
Topen=> 	6,
Ropen=> 	13,
Tcreate=> 	38,
Rcreate=> 	13,
Tread=> 	15,
Rread=> 	8, # header only; excludes data
Twrite=> 	16, # header only; excludes data
Rwrite=> 	7,
Tclunk=> 	5,
Rclunk=> 	5,
Tremove=> 	5,
Rremove=> 	5,
Tstat=> 	5,
Rstat=> 	121,
Twstat=> 	121,
Rwstat=> 	5,
Tsession=>	0,
Rsession=>	0,
Tattach=> 	5+2*NAMELEN,
Rattach=> 	13,
};

init()
{
	sys = load Sys Sys->PATH;
}

packdirsize(nil: Sys->Dir): int
{
	return DIRLEN;	# constant in this version of Styx
}

packdir(f: Sys->Dir): array of byte
{
	a := array[DIRLEN] of byte;
	packstring(a, 0, f.name, NAMELEN);
	packstring(a, NAMELEN, f.uid, NAMELEN);
	packstring(a, 2*NAMELEN, f.gid, NAMELEN);

	O: con 3*NAMELEN;
	a[O] = byte f.qid.path;
	a[O+1] = byte (f.qid.path >> 8);
	a[O+2] = byte (f.qid.path >> 16);
	a[O+3] = byte (f.qid.path >> 24);

	a[O+4] = byte f.qid.vers;
	a[O+5] = byte (f.qid.vers >> 8);
	a[O+6] = byte (f.qid.vers >> 16);
	a[O+7] = byte (f.qid.vers >> 24);

	a[O+8] = byte f.mode;
	a[O+9] = byte (f.mode >> 8);
	a[O+10] = byte (f.mode >> 16);
	a[O+11] = byte (f.mode >> 24);

	a[O+12] = byte f.atime;
	a[O+13] = byte (f.atime >> 8);
	a[O+14] = byte (f.atime >> 16);
	a[O+15] = byte (f.atime >> 24);

	a[O+16] = byte f.mtime;
	a[O+17] = byte (f.mtime >> 8);
	a[O+18] = byte (f.mtime >> 16);
	a[O+19] = byte (f.mtime >> 24);

	a[O+20] = byte f.length;
	a[O+21] = byte (f.length >> 8);
	a[O+22] = byte (f.length >> 16);
	a[O+23] = byte (f.length >> 24);
	a[O+24] = byte 0;
	a[O+25] = byte 0;
	a[O+26] = byte 0;
	a[O+27] = byte 0;

	a[O+28] = byte f.dtype;
	a[O+29] = byte (f.dtype >> 8);

	a[O+30] = byte f.dev;
	a[O+31] = byte (f.dev >> 8);

	return a;
}

packstring(a: array of byte, o: int, s: string, lim: int): int
{
	sa := array of byte s;	# would be nice to avoid this
	n := len sa;
	if(n >= lim){
		n = lim-1;
		sa = sa[0:n];
	}
	a[o:] = sa;
	o += n;
	for(i := n; i<lim; i++)
		a[o++]= byte 0;
	return o;
}

unpackdir(f: array of byte): (int, Sys->Dir)
{
	dir: Sys->Dir;

	dir.name = stringof(f, 0, 28);
	dir.uid =  stringof(f, 28, 56);
	dir.gid =  stringof(f, 56, 84);

	# TO DO: Qid.path becomes big shortly
	dir.qid.path =	(int f[84]<<0)|
				(int f[85]<<8)|
				(int f[86]<<16)|
				(int f[87]<<24);
	dir.qid.vers =	(int f[88]<<0)|
				(int f[89]<<8)|
				(int f[90]<<16)|
				(int f[91]<<24);
	# TO DO: Qid.qtype

	dir.mode =	(int f[92]<<0)|
			(int f[93]<<8)|
			(int f[94]<<16)|
			(int f[95]<<24);
	dir.atime =	(int f[96]<<0)|
			(int f[97]<<8)|
			(int f[98]<<16)|
			(int f[99]<<24);
	dir.mtime =	(int f[100]<<0)|
			(int f[101]<<8)|
			(int f[102]<<16)|
			(int f[103]<<24);

	# TO DO: Dir.length becomes big shortly
	dir.length =	(int f[104]<<0)|
			(int f[105]<<8)|
			(int f[106]<<16)|
			(int f[107]<<24);
	dir.dtype =	(int f[112]<<0)|
			(int f[113]<<8);
	dir.dev =	(int f[114]<<0)|
			(int f[115]<<8);
	return (DIRLEN, dir);
}

Rmsg.unpack(f: array of byte): (int, ref Rmsg)
{
	if(len f < 3)
		return (0, nil);
	mtype := int f[0];
	if(mtype >= len msglen || (mtype&1) == 0)
		return (-1, nil);
	if(len f < msglen[mtype])
		return (0, nil);

	tag := (int f[2] << 8) | int f[1];
	fid := 0;
	if(msglen[mtype] >= 5)
		fid = (int f[4] << 8) | int f[3];
	case mtype {
	* =>
		return (-1, nil);
	Rnop =>
		return (3, ref Rmsg.Nop(tag));
	Rflush =>
		return (3, ref Rmsg.Flush(tag));
	Rerror =>
		ename := stringof(f, 3, 3+ERRLEN);
		return (3+ERRLEN, ref Rmsg.Error(tag, ename));
	Rclone =>
		return (5, ref Rmsg.Clone(tag, fid));
	Rclunk =>
		return (5, ref Rmsg.Clunk(tag, fid));
	Rremove =>
		return (5, ref Rmsg.Remove(tag, fid));
	Rwstat=>
		return (5, ref Rmsg.Wstat(tag, fid));
	Rattach =>
		return (13, ref Rmsg.Attach(tag, fid, gqid(f, 5)));
	Rwalk =>
		return (13, ref Rmsg.Walk(tag, fid, gqid(f, 5)));
	Ropen =>
		return (13, ref Rmsg.Open(tag, fid, gqid(f, 5)));
	Rcreate=>
		return (13, ref Rmsg.Create(tag, fid, gqid(f, 5)));
	Rread =>
		count := (int f[6]<<8) | int f[5];
		if(len f < msglen[mtype]+count)
			return (0, nil);
		# 7 is pad[1]
		data := f[8:8+count];
		return (8+count, ref Rmsg.Read(tag, fid, data));
	Rwrite =>
		count := (int f[6]<<8) | int f[5];
		return (7, ref Rmsg.Write(tag, fid, count));
	Rstat =>
		(ds, d) := unpackdir(f[5:]);
		return (5+ds, ref Rmsg.Stat(tag, fid, d));
	}
}

gqid(f: array of byte, i: int): Sys->Qid
{
	path := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	vers := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (path, vers);
}

glong(f: array of byte, i: int): int
{
	return (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
}

gbig(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

stringof(a: array of byte, l: int, u: int): string
{
	for(i := l; i < u; i++)
		if(int a[i] == 0)
			break;
	return string a[l:i];
}

ttag2type := array[] of {
tagof Tmsg.Readerror => -1,
tagof Tmsg.Nop => Tnop,
tagof Tmsg.Flush => Tflush,
tagof Tmsg.Clone => Tclone,
tagof Tmsg.Walk => Twalk,
tagof Tmsg.Open => Topen,
tagof Tmsg.Create => Tcreate,
tagof Tmsg.Read => Tread,
tagof Tmsg.Write => Twrite,
tagof Tmsg.Clunk => Tclunk,
tagof Tmsg.Stat => Tstat,
tagof Tmsg.Remove => Tremove,
tagof Tmsg.Wstat => Twstat,
tagof Tmsg.Attach => Tattach,
};

Tmsg.packedsize(t: self ref Tmsg): int
{
	mtype := ttag2type[tagof t];
	ml := msglen[mtype];
	pick m := t {
	Write =>
		n := len m.data;
		if(n > MAXFDATA)
			return 0;
		ml += n;
	}
	return ml;
}

Tmsg.pack(t: self ref Tmsg): array of byte
{
	if(t == nil)
		return nil;
	d := array[t.packedsize()] of byte;
	if(len d == 0)
		return nil;
	d[0] = byte ttag2type[tagof t];
	d[1] = byte t.tag;
	d[2] = byte (t.tag >> 8);
	pick m := t {
	Nop =>
		;
	Flush =>
		v := m.oldtag;
		d[3] = byte v;
		d[4] = byte (v>>8);
	Attach =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		packstring(d, 5, m.uname, NAMELEN);
		packstring(d, 5+NAMELEN, m.aname, NAMELEN);
	Clone =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		d[5] = byte m.newfid;
		d[6] = byte (m.newfid>>8);
	Walk =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		packstring(d, 5, m.name, NAMELEN);
	Open =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		d[5] = byte m.mode;
	Create =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		packstring(d, 5, m.name, NAMELEN);
		d[5+NAMELEN] = byte m.perm;
		d[6+NAMELEN] = byte (m.perm>>8);
		d[7+NAMELEN] = byte (m.perm>>16);
		d[8+NAMELEN] = byte (m.perm>>24);
		d[9+NAMELEN] = byte m.mode;
	Read =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		v := int m.offset;
		d[5] = byte v;
		d[6] = byte (v>>8);
		d[7] = byte (v>>16);
		d[8] = byte (v>>24);
		v = int (m.offset >> 32);
		d[9] = byte v;
		d[10] = byte (v>>8);
		d[11] = byte (v>>16);
		d[12] = byte (v>>24);
		d[13] = byte m.count;
		d[14] = byte (m.count>>8);
	Write =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		v := int m.offset;
		d[5] = byte v;
		d[6] = byte (v>>8);
		d[7] = byte (v>>16);
		d[8] = byte (v>>24);
		v = int (m.offset >> 32);
		d[9] = byte v;
		d[10] = byte (v>>8);
		d[11] = byte (v>>16);
		d[12] = byte (v>>24);
		n := len m.data;
		d[13] = byte n;
		d[14] = byte (n>>8);
		d[15] = byte 0;	# pad[1]
		d[16:] = m.data;
	Clunk or Remove or Stat =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
	Wstat =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		stat := packdir(m.stat);
		d[5:] = stat;
	* =>
		return nil;	# can't happen
	}
	return d;
}

Tmsg.unpack(d: array of byte): (int, ref Tmsg)
{
	n := len d;
	if (n < 3)
		return (0, nil);
	t := int d[0];
	if(t >= len msglen || (t&1) != 0)
		return (-1, nil);
	if (n < msglen[t])
		return (0, nil);

	tag := (int d[2] << 8) | int d[1];
	fid := 0;
	if(msglen[t] >= 5)
		fid = (int d[4] << 8) | int d[3];
	case t {
	Tnop =>
		return (3, ref Tmsg.Nop(tag));
	Tflush =>
		oldtag := fid;
		return (5, ref Tmsg.Flush(tag, oldtag));
	Tclone =>
		newfid := (int d[6]<<8) | int d[5];
		return (5, ref Tmsg.Clone(tag, fid, newfid));
	Twalk =>
		name := stringof(d, 5, 5+Sys->NAMELEN);
		return (5+Sys->NAMELEN, ref Tmsg.Walk(tag, fid, name));
	Topen =>
		return (6, ref Tmsg.Open(tag, fid, int d[5]));
	Tcreate =>
		name := stringof(d, 5, 5+Sys->NAMELEN);
		perm := glong(d, 5+Sys->NAMELEN);
		mode := int d[5+Sys->NAMELEN+4];
		return (5+Sys->NAMELEN+4+1, ref Tmsg.Create(tag, fid, perm, mode, name));
	Tread =>
		offset := gbig(d, 5);
		if(offset < big 0)
			offset = big 0;
		count := (int d[14]<<8) | int d[13];
		return (15, ref Tmsg.Read(tag, fid, count, offset));
	Twrite =>
		offset := gbig(d, 5);
		if(offset < big 0)
			offset = big 0;
		count := (int d[14]<<8) | int d[13];
		if(count > Sys->ATOMICIO)
			return (-1, nil);
		# 15 is pad[1]
		if(count > len d-16)
			return (0, nil);
		data := d[16:16+count];
		return (16, ref Tmsg.Write(tag, fid, offset, data));
	Tclunk =>
		return (5, ref Tmsg.Clunk(tag, fid));
	Tremove =>
		return (5, ref Tmsg.Remove(tag, fid));
	Tstat =>
		return (5, ref Tmsg.Stat(tag, fid));
	Twstat =>
		(ds, stat) := unpackdir(d[5:]);
		return (5+ds, ref Tmsg.Wstat(tag, fid, stat));
	Tattach =>
		uname := stringof(d, 5, 5+NAMELEN);
		aname := stringof(d, 5+NAMELEN, 5+2*NAMELEN);
		return (5+2*NAMELEN, ref Tmsg.Attach(tag, fid, uname, aname));
	}
	return (-1, nil);		# not reached
}

tmsgname := array[] of {
tagof Tmsg.Readerror => "Readerror",
tagof Tmsg.Nop => "Nop",
tagof Tmsg.Flush => "Flush",
tagof Tmsg.Clone => "Clone",
tagof Tmsg.Walk => "Walk",
tagof Tmsg.Open => "Open",
tagof Tmsg.Create => "Create",
tagof Tmsg.Read => "Read",
tagof Tmsg.Write => "Write",
tagof Tmsg.Clunk => "Clunk",
tagof Tmsg.Stat => "Stat",
tagof Tmsg.Remove => "Remove",
tagof Tmsg.Wstat => "Wstat",
tagof Tmsg.Attach => "Attach",
};

Tmsg.text(t: self ref Tmsg): string
{
	if(t == nil)
		return "nil";
	s := sys->sprint("Tmsg.%s(%ud", tmsgname[tagof t], t.tag);
	pick m:= t {
	Readerror =>
		return s + sys->sprint(",\"%s\")", m.error);
	Nop =>
		;
	Flush =>
		return s + sys->sprint(",%ud)", m.oldtag);
	Clone =>
		return s + sys->sprint(",%ud,%ud)", m.fid, m.newfid);
	Walk =>
		return s + sys->sprint(",%ud,\"%s\")", m.fid, m.name);
	Open =>
		return s + sys->sprint(",%ud,%d)", m.fid, m.mode);
	Create =>
		return s + sys->sprint(",%ud,8r%uo,%d,\"%s\")", m.fid, m.perm, m.mode, m.name);
	Read =>
		return s + sys->sprint(",%ud,%d,%ubo)", m.fid, m.count, m.offset);
	Write =>
		return s + sys->sprint(",%ud,%ubo,data[%d])", m.fid, m.offset, len m.data);
	Clunk or
	Stat or
	Remove =>
		return s + sys->sprint(",%ud)", m.fid);
	Wstat =>
		return s + sys->sprint(",%ud,%s)", m.fid, dir2text(m.stat));
	Attach =>
		return s + sys->sprint(",%ud,\"%s\",\"%s\")", m.fid, m.uname, m.aname);
	}
	return s + ")";
}

Tmsg.read(fd: ref Sys->FD, msglim: int): ref Tmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Tmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Tmsg.unpack(msg);
	if(m == nil)
		return ref Tmsg.Readerror(0, "bad Styx T-message format");
	return m;
}

rtag2type := array[] of {
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

Rmsg.packedsize(r: self ref Rmsg): int
{
	mtype := rtag2type[tagof r];
	ml := msglen[mtype];
	pick m := r {
	Read =>
		n := len m.data;
		if(n > MAXFDATA)
			return 0;
		ml += n;
	}
	return ml;
}

Rmsg.pack(r: self ref Rmsg): array of byte
{
	if(r == nil)
		return nil;
	d := array[r.packedsize()] of byte;
	if(d == nil)
		return nil;
	d[0] = byte rtag2type[tagof r];
	d[1] = byte r.tag;
	d[2] = byte (r.tag >> 8);
	pick m := r {
	Nop or
	Flush =>
	Error	=>
		packstring(d, 3, m.ename, ERRLEN);
	Clunk or
	Remove or
	Clone or
	Wstat =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
	Walk or
	Create or
	Open or
	Attach =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		v := m.qid.path;
		d[5] = byte v;
		d[6] = byte (v>>8);
		d[7] = byte (v>>16);
		d[8] = byte (v>>24);
		v = m.qid.vers;
		d[9] = byte v;
		d[10] = byte (v>>8);
		d[11] = byte (v>>16);
		d[12] = byte (v>>24);
	Read =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		data := m.data;
		v := len data;
		d[5] = byte v;
		d[6] = byte (v>>8);
		d[7] = byte 0;	# pad[1]
		d[8:] = data;
	Write =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		v := m.count;
		d[5] = byte v;
		d[6] = byte (v>>8);
	Stat =>
		d[3] = byte m.fid;
		d[4] = byte (m.fid>>8);
		stat := packdir(m.stat);
		d[5:] = stat;	# should avoid copy?
	* =>
		return nil;	# can't happen
	}
	return d;
}

rmsgname := array[] of {
tagof Rmsg.Nop => "Nop",
tagof Rmsg.Flush => "Flush",
tagof Rmsg.Error => "Error",
tagof Rmsg.Clunk => "Clunk",
tagof Rmsg.Remove => "Remove",
tagof Rmsg.Clone => "Clone",
tagof Rmsg.Wstat => "Wstat",
tagof Rmsg.Walk => "Walk",
tagof Rmsg.Create => "Create",
tagof Rmsg.Open => "Open",
tagof Rmsg.Attach => "Attach",
tagof Rmsg.Read => "Read",
tagof Rmsg.Write => "Write",
tagof Rmsg.Stat => "Stat",
};

Rmsg.text(r: self ref Rmsg): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(r == nil)
		return "nil";
	s := sys->sprint("Rmsg.%s(%ud", rmsgname[tagof r], r.tag);
	pick m := r {	
	Nop or
	Flush =>
		;
	Error =>
		return s+sys->sprint(",\"%s\")", m.ename);
	Clunk or
	Remove or
	Clone or
	Wstat =>
		return s+sys->sprint(",%ud)", m.fid);
	Walk	 or
	Create or
	Open or
	Attach =>
		return s+sys->sprint(",%ud,%s)", m.fid, qid2text(m.qid));
	Read =>
		return s+sys->sprint(",%ud,data[%d])", m.fid, len m.data);
	Write =>
		return s+sys->sprint(",%ud,%d)", m.fid, m.count);
	Stat =>
		return s+sys->sprint("%ud,%s)", m.fid, dir2text(m.stat));
	}
	return s + ")";
}

Rmsg.read(fd: ref Sys->FD, msglim: int): ref Rmsg
{
	(msg, err) := readmsg(fd, msglim);
	if(err != nil)
		return ref Rmsg.Readerror(0, err);
	if(msg == nil)
		return nil;
	(nil, m) := Rmsg.unpack(msg);
	if(m == nil)
		return ref Rmsg.Readerror(0, "bad Styx R-message format");
	return m;
}

dir2text(d: Sys->Dir): string
{
	dt := sys->sprint("'%c'", d.dtype);
	if(d.dtype < 8r40)
		dt = sys->sprint("%d", d.dtype);
	return sys->sprint("Dir(\"%s\",\"%s\",\"%s\",%s,8r%uo,%ud,%ud,%ud,%s,%d)",
		d.name, d.uid, d.gid, qid2text(d.qid), d.mode, d.atime, d.mtime, d.length, dt, d.dev);
}

qid2text(q: Sys->Qid): string
{
	return sys->sprint("Qid(16r%ux,%d)", q.path, q.vers);
}

readmsg(fd: ref Sys->FD, msglim: int): (array of byte, string)
{
	if(msglim <= 0)
		msglim = MAXRPC;
	buf := array[IOHDRSZ] of byte;
	if((n := readn(fd, buf, 3)) != 3){
		if(n == 0)
			return (nil, nil);
		return (nil, sys->sprint("%r"));
	}
	mtype := int buf[0];
	if(mtype >= len msglen || (ml := msglen[mtype]) == 0)
		return (nil, "invalid Styx message type");
	if((n = readn(fd, buf[3:], ml-3)) != ml-3){
		if(n == 0)
			return (nil, "Styx message truncated");
		return (nil, sys->sprint("%r"));
	}
	# special cases
	count := 0;
	case mtype {
	* =>
		return (buf[0:ml], nil);
	Twrite =>	# count[2] at 1+2+2+8
		count = (int buf[14] << 8) | int buf[13];
	Rread =>	# count[2] at 1+2+2
		count = (int buf[6] << 8) | int buf[5];
	}
	buflen := ml+count;
	if(buflen > msglim)
		return (nil, "Styx message longer than agreed");
	if(buflen > len buf)
		buf = (array[buflen] of byte)[0:] = buf[0:ml];
	if((n = readn(fd, buf[ml:], count)) != count){
		if(n == 0)
			return (nil, "Styx message truncated");
		return (nil, sys->sprint("%r"));
	}
	if(buflen < len buf)
		buf = buf[0:buflen];
	return (buf, nil);
}

readn(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	for(nr := 0; nr < nb;){
		n := sys->read(fd, buf, nb-nr);
		if(n <= 0){
			if(nr == 0)
				return n;
			break;
		}
		nr += n;
	}
	return nr;
}

istmsg(f: array of byte): int
{
	if(len f < 1)
		return -1;
	return (int f[0] & 1) == 0;
}

# only here to support an implementation of this module that talks the previous version of Styx
write(fd: ref Sys->FD, buf: array of byte, nb: int): int
{
	return sys->write(fd, buf, nb);
}
