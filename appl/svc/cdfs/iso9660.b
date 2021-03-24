implement Xfiles;

include "sys.m";
	sys: Sys;
	Dir, Qid, CHDIR, NAMELEN: import sys;

include "draw.m";

include "iobuf.m";
	iobuf: Iobuf;
	Block, Device: import iobuf;

include "styx.m";
	styx: Styx;

include "xfiles.m";

VOLDESC: con 16;	# sector number
Sectorsize: con 2048;

Drec: adt {
	reclen:	int;
	attrlen:	int;
	addr:	int;	# should be big?
	size:	int;	# should be big?
	date:	array of byte;
	time:	int;
	tzone:	int;	# not in high sierra
	flags:	int;
	unitsize:	int;
	gapsize:	int;
	vseqno:	int;
	name:	array of byte;
	data:	array of byte;	# system extensions
};

Isofile: adt {
	fmt:	int;	# 'z' if iso, 'r' if high sierra
	blksize:	int;
	offset:	int;	# true offset when reading directory
	doffset:	int;	# styx (DIRLEN) offset when reading directory
	d:	ref Drec;
};

chatty: con 0;

Enonexist:	con "file does not exist";
Eperm:	con "permission denied";

fdata := array[1] of ref Isofile;
freelist: list of int;	# free elements of fdata
stderr: ref Sys->FD;

init(io: Iobuf, astyx: Styx)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	iobuf = io;
	styx = astyx;
}

Xfile.new(): ref Xfile
{
	f := ref Xfile;
	return f.clean();
}

Xfile.clean(f: self ref Xfile): ref Xfile
{
	if(f.xf != nil){
		f.xf.decref();
		f.xf = nil;
	}
	f.ptr = 0;
	f.flags = 0;
	f.qid = Qid(0, 0);
	return f;
}

Xfile.attach(root: self ref Xfile): string
{
	fmt, blksize: int;

	p := Block.get(root.xf.d, VOLDESC);
	if(p == nil)
		return "can't read volume descriptor";
	dp := ref Drec;
	v := p.data;	# Voldesc
	if(eqs(v[0:7], "\u0001CD001\u0001")){		# ISO
		fmt = 'z';
		convM2Drec(v[156:], dp, 0);	# v.z.desc.rootdir
		blksize = l16(v[128:]);	# v.z.desc.blksize
		if(chatty)
			chat(sys->sprint("iso, blksize=%d...", blksize));
	}else if(eqs(v[8:8+7], "\u0001CDROM\u0001")){	# high sierra
		fmt = 'r';
		convM2Drec(v[180:], dp, 1);	# v.r.desc.rootdir
		blksize = l16(v[136:]);	# v.r.desc.blksize
		if(chatty)
			chat(sys->sprint("high sierra, blksize=%d...", blksize));
	}else{
		p.put();
		return "not ISO or High Sierra";
	}
	if(chatty)
		showdrec(stderr, fmt, dp);
	if(blksize > Sectorsize){
		p.put();
		return "blocksize too big";
	}
	fp := iso(root);
	root.xf.isplan9 = eqs(v[8:8+6], "PLAN 9");	# v.z.boot.sysid
	fp.fmt = fmt;
	fp.blksize = blksize;
	fp.offset = 0;
	fp.doffset = 0;
	fp.d = dp;
	root.qid.path = CHDIR | dp.addr;
	p.put();
	dp = ref Drec;
	if(getdrec(root, dp) >= 0){
		s := dp.data;
		n := len s;
		if(n >= 7 && s[0] == byte 'S' && s[1] == byte 'P' && s[2] == byte 7 &&
		   s[3] == byte 1 && s[4] == byte 16rBE && s[5] == byte 16rEF){
			root.xf.issusp = 1;
			root.xf.suspoff = int s[6];
			n -= root.xf.suspoff;
			s = s[root.xf.suspoff:];
			while(n >= 4){
				l := int s[2];
				if(s[0] == byte 'E' && s[1] == byte 'R'){
					if(int s[4] == 10 && eqs(s[8:18], "RRIP_1991A"))
						root.xf.isrock = 1;
					break;
				} else if(s[0] == byte 'C' && s[1] == byte 'E' && int s[2] >= 28){
					(s, n) = getcontin(root.xf.d, s);
					continue;
				} else if(s[0] == byte 'R' && s[1] == byte 'R'){
					root.xf.isrock = 1;
					break;	# can skip search for ER
				} else if(s[0] == byte 'S' && s[1] == byte 'T')
					break;
				s = s[l:];
				n -= l;
			}
		}
	}
	fp.offset = 0;
	fp.doffset = 0;
	return nil;
}

Xfile.clone(oldf: self ref Xfile, newf: ref Xfile)
{
	*newf = *oldf;
	newf.ptr = 0;
	newf.xf.incref();
	ip := iso(oldf);
	np := iso(newf);
	*np = *ip;	# might not be right; shares ip.d
}

Xfile.walkup(f: self ref Xfile): string
{
	pf := Xfile.new();
	ppf := Xfile.new();
	e := walkup(f, pf, ppf);
	pf.clunk();
	ppf.clunk();
	return e;
}

walkup(f, pf, ppf: ref Xfile): string
{
	e := opendotdot(f, pf);
	if(e != nil)
		return sys->sprint("can't open pf: %s", e);
	paddr := iso(pf).d.addr;
	if(iso(f).d.addr == paddr)
		return nil;
	e = opendotdot(pf, ppf);
	if(e != nil)
		return sys->sprint("can't open ppf: %s", e);
	d := ref Drec;
	while(getdrec(ppf, d) >= 0){
		if(d.addr == paddr){
			newdrec(f, d);
			f.qid.path = paddr|CHDIR;
			return nil;
		}
	}
	return "can't find addr of ..";
}

Xfile.walk(f: self ref Xfile, name: string): string
{
	ip := iso(f);
	if(!f.xf.isplan9){
		for(i := 0; i < len name; i++)
			if(name[i] == ';')
				break;
		if(i > Sys->NAMELEN)
			i = Sys->NAMELEN;
		name = name[0:i];
	}
	if(chatty)
		chat(sys->sprint("%d \"%s\"...", len name, name));
	ip.offset = 0;
	dir := ref Dir;
	d := ref Drec;
	while(getdrec(f, d) >= 0) {
		dvers := rzdir(f.xf, dir, 'z', d);
		if(name != dir.name)
			continue;
		newdrec(f, d);
		f.qid.path = dir.qid.path;
		if(dvers);
		return nil;
	}
	return Enonexist;
}

Xfile.open(f: self ref Xfile, mode: int): string
{
	if(mode != Sys->OREAD)
		return Eperm;
	ip := iso(f);
	ip.offset = 0;
	ip.doffset = 0;
	return nil;
}

Xfile.create(nil: self ref Xfile, nil: string, nil: int, nil: int): string
{
	return Eperm;
}

Xfile.readdir(f: self ref Xfile, buf: array of byte, offset: int, count: int): (int, string)
{
	ip := iso(f);
	d := ref Dir;
	drec := ref Drec;
	if(offset < ip.doffset){
		ip.offset = 0;
		ip.doffset = 0;
	}
	rcnt := 0;
	while(rcnt < count && getdrec(f, drec) >= 0){
		if(len drec.name == 1){
			if(drec.name[0] == byte 0)
				continue;
			if(drec.name[0] == byte 1)
				continue;
		}
		if(ip.doffset < offset){
			ip.doffset += Styx->DIRLEN;
			continue;
		}
		rzdir(f.xf, d, ip.fmt, drec);
		d.qid.vers = f.qid.vers;
		a := styx->packdir(*d);
		buf[rcnt:] = a;		# BOTCH: copy
		rcnt += len a;
	}
	ip.doffset += rcnt;
	return (rcnt, nil);
}

Xfile.read(f: self ref Xfile, buf: array of byte, offset: int, count: int): (int, string)
{
	ip := iso(f);
	if(offset >= ip.d.size)
		return (0, nil);
	if(offset+count > ip.d.size)
		count = ip.d.size - offset;
	addr := (ip.d.addr+ip.d.attrlen)*ip.blksize + offset;
	o := addr % Sectorsize;
	addr /= Sectorsize;
	if(chatty)
		chat(sys->sprint("d.addr=0x%x, addr=0x%x, o=0x%x...", ip.d.addr, addr, o));
	n := Sectorsize - o;
	rcnt := 0;
	while(count > 0){
		if(n > count)
			n = count;
		p := Block.get(f.xf.d, addr);
		if(p == nil)
			return (-1, "i/o error");
		buf[rcnt:] = p.data[o:o+n];
		p.put();
		count -= n;
		rcnt += n;
		addr++;
		o = 0;
		n = Sectorsize;
	}
	return (rcnt, nil);
}

Xfile.write(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string)
{
	return (-1, Eperm);
}

Xfile.clunk(f: self ref Xfile)
{
	if(f.ptr != 0) {
		fdata[f.ptr] = nil;
		freelist = f.ptr :: freelist;
		f.ptr = 0;
	}
}

Xfile.remove(nil: self ref Xfile): string
{
	return Eperm;
}

Xfile.stat(f: self ref Xfile): (ref Dir, string)
{
	ip := iso(f);
	d := ref Dir;
	rzdir(f.xf, d, ip.fmt, ip.d);
	d.qid.vers = f.qid.vers;
	if(d.qid.path==f.xf.rootqid.path)
		d.qid.path = CHDIR;
	return (d, nil);
}

Xfile.wstat(nil: self ref Xfile, nil: ref Dir): string
{
	return Eperm;
}

Xfs.new(d: ref Device): ref Xfs
{
	xf := ref Xfs;
	xf.inuse = 1;
	xf.d = d;
	xf.isplan9 = 0;
	xf.issusp = 0;
	xf.isrock = 0;
	xf.suspoff = 0;
	xf.ptr = 0;
	xf.rootqid = Qid(CHDIR, 0);
	return xf;
}

Xfs.incref(xf: self ref Xfs)
{
	xf.inuse++;
}

Xfs.decref(xf: self ref Xfs)
{
	xf.inuse--;
	if(xf.inuse == 0){
		if(xf.d != nil)
			xf.d.detach();
	}
}

showdrec(fd: ref Sys->FD, fmt: int, d: ref Drec)
{
	if(d.reclen == 0)
		return;
	sys->fprint(fd, "%d %d %d %d ",
		d.reclen, d.attrlen, d.addr, d.size);
	sys->fprint(fd, "%s 0x%2.2x %d %d %d ",
		rdate(d.date, fmt), d.flags,
		d.unitsize, d.gapsize, d.vseqno);
	sys->fprint(fd, "%d %s", len d.name, nstr(d.name));
	syslen := len d.data;
	if(syslen != 0)
		sys->fprint(fd, " %s", nstr(d.data));
	sys->fprint(fd, "\n");
}

newdrec(f: ref Xfile, dp: ref Drec)
{
	x := iso(f);
	n := ref Isofile;
	n.fmt = x.fmt;
	n.blksize = x.blksize;
	n.offset = 0;
	n.doffset = 0;
	n.d = dp;
	fdata[f.ptr] = n;
}

getdrec(f: ref Xfile, d: ref Drec): int
{
	if(f.ptr == 0 || fdata[f.ptr] == nil)
		return -1;
	boff := 0;
	ip := iso(f);
	size := ip.d.size;
	while(ip.offset<size){
		addr := (ip.d.addr+ip.d.attrlen)*ip.blksize + ip.offset;
		boff = addr % Sectorsize;
		if(boff > Sectorsize-34){
			ip.offset += Sectorsize-boff;
			continue;
		}
		p := Block.get(f.xf.d, addr/Sectorsize);
		if(p == nil)
			return -1;
		nb := int p.data[boff];
		if(nb >= 34) {
			convM2Drec(p.data[boff:], d, ip.fmt=='r');
			#chat(sys->sprint("off %d", ip.offset));
			#showdrec(stderr, ip.fmt, d);
			p.put();
			ip.offset += nb + (nb&1);
			return 0;
		}
		p.put();
		p = nil;
		ip.offset += Sectorsize-boff;
	}
	return -1;
}

# getcontin returns a slice of the Iobuf, valid until next i/o call
getcontin(d: ref Device, a: array of byte): (array of byte, int)
{
	bn := l32(a[4:]);
	off := l32(a[12:]);
	n := l32(a[20:]);
	p := Block.get(d, bn);
	if(p == nil)
		return (nil, 0);
	return (p.data[off:off+n], n);
}

iso(f: ref Xfile): ref Isofile
{
	if(f.ptr == 0){
		if(freelist != nil){
			f.ptr = hd freelist;
			freelist = tl freelist;
		}else{
			n := len fdata;
			a := array[n+1] of ref Isofile;
			if(n > 0)
				a[0:] = fdata[0:];
			fdata = a;
			f.ptr = n;
		}
		fdata[f.ptr] = ref Isofile;
		fdata[f.ptr].d = ref Drec;
	}
	return fdata[f.ptr];
}

opendotdot(f: ref Xfile, pf: ref Xfile): string
{
	d := ref Drec;
	ip := iso(f);
	ip.offset = 0;
	if(getdrec(f, d) < 0)
		return "opendotdot: getdrec(.) failed";
	if(len d.name != 1 || d.name[0] != byte 0)
		return "opendotdot: no . entry";
	if(d.addr != ip.d.addr)
		return "opendotdot: bad . address";
	if(getdrec(f, d) < 0)
		return "opendotdot: getdrec(..) failed";
	if(len d.name != 1 || d.name[0] != byte 1)
		return "opendotdot: no .. entry";

	pf.xf = f.xf;
	pip := iso(pf);
	pip.fmt = ip.fmt;
	pip.blksize = ip.blksize;
	pip.offset = 0;
	pip.doffset = 0;
	pip.d = d;
	return nil;
}

rzdir(fs: ref Xfs, d: ref Dir, fmt: int, dp: ref Drec): int
{
	Hmode, Hname: con 1<<iota;
	vers := -1;
	have := 0;
	d.qid.path = int dp.addr;
	d.qid.vers = 0;
	n := len dp.name;
	if(n == 1) {
		case int dp.name[0] {
		0 => d.name = "."; have |= Hname;
		1 =>	d.name = ".."; have |= Hname;
		* =>	d.name = ""; d.name[0] = tolower(int dp.name[0]);
		}
	} else {
		if(n >= NAMELEN)
			n = NAMELEN-1;
		d.name = "";
		for(i:=0; i<n; i++)
			d.name[i] = tolower(int dp.name[i]);
	}

	if(fs.isplan9 && dp.reclen>34+len dp.name) {
		#
		# get gid, uid, mode and possibly name
		# from plan9 directory extension
		#
		s := dp.data;
		n = int s[0];
		if(n)
			d.name = string s[1:1+n];
		l := 1+n;
		n = int s[l++];
		d.uid = string s[l:l+n];
		l += n;
		n = int s[l++];
		d.gid = string s[l:l+n];
		l += n;
		if(l & 1)
			l++;
		d.mode = l32(s[l:]);
		if(d.mode & CHDIR)
			d.qid.path |= CHDIR;
	} else {
		d.mode = 8r444;
		case fmt {
		'z' =>	if(fs.isrock)
					d.gid = "ridge";
				else
					d.gid = "iso";
		'r' =>		d.gid = "sierra";
		* =>		d.gid = "???";
		}
		flags := dp.flags;
		if(flags & 2){
			d.qid.path |= CHDIR;
			d.mode |= CHDIR|8r111;
		}
		d.uid = "cdrom";
		for(i := 0; i < len d.name; i++)
			if(d.name[i] == ';') {
				vers = int string d.name[i+1:];	# inefficient
				d.name = d.name[0:i];	# inefficient
				break;
			}
		n = len dp.data - fs.suspoff;
		if(fs.isrock && n >= 4){
			s := dp.data[fs.suspoff:];
			nm := 0;
			while(n >= 4 && have != (Hname|Hmode)){
				l := int s[2];
				if(s[0] == byte 'P' && s[1] == byte 'X' && s[3] == byte 1){
					# posix file attributes
					mode := l32(s[4:12]);
					d.mode = mode & 8r777;
					if((mode & 8r170000) == 8r0040000){
						d.mode |= CHDIR;
						d.qid.path |= CHDIR;
					}
					have |= Hmode;
				} else if(s[0] == byte 'N' && s[1] == byte 'M' && s[3] == byte 1){
					# alternative name
					flags = int s[4];
					if((flags & ~1) == 0){
						if(nm == 0){
							d.name = string s[5:l];
							nm = 1;
						} else
							d.name += string s[5:l];
						if(flags == 0)
							have |= Hname;	# no more
					}
				} else if(s[0] == byte 'C' && s[1] == byte 'E' && int s[2] >= 28){
					(s, n) = getcontin(fs.d, s);
					continue;
				} else if(s[0] == byte 'S' && s[1] == byte 'T')
					break;
				n -= l;
				s = s[l:];
			}
		}
	}
	d.length = 0;
	if((d.mode & CHDIR) == 0)
		d.length = dp.size;
	d.dtype = 0;
	d.dev = 0;
	d.atime = dp.time;
	d.mtime = d.atime;
	return vers;
}

convM2Drec(a: array of byte, d: ref Drec, highsierra: int)
{
	d.reclen = int a[0];
	d.attrlen = int a[1];
	d.addr = int l32(a[2:10]);
	d.size = int l32(a[10:18]);
	d.time = gtime(a[18:24]);
	d.date = array[7] of byte;
	d.date[0:] = a[18:25];
	if(highsierra){
		d.tzone = 0;
		d.flags = int a[24];
		d.unitsize = 0;
		d.gapsize = 0;
		d.vseqno = 0;
	} else {
		d.tzone = int a[24];
		d.flags = int a[25];
		d.unitsize = int a[26];
		d.gapsize = int a[27];
		d.vseqno = l32(a[28:32]);
	}
	n := int a[32];
	d.name = array[n] of byte;
	d.name[0:] = a[33:33+n];
	n += 33;
	if(n & 1)
		n++;	# check this
	syslen := d.reclen - n;
	if(syslen > 0){
		d.data = array[syslen] of byte;
		d.data[0:] = a[n:n+syslen];
	} else
		d.data = nil;
}

nstr(p: array of byte): string
{
	q := "";
	n := len p;
	for(i := 0; i < n; i++){
		if(int p[i] == '\\')
			q[len q] = '\\';
		if(' ' <= int p[i] && int p[i] <= '~')
			q[len q] = int p[i];
		else
			q += sys->sprint("\\%2.2ux", int p[i]);
	}
	return q;
}

rdate(p: array of byte, fmt: int): string
{
	c: int;

	s := sys->sprint("%2.2d.%2.2d.%2.2d %2.2d:%2.2d:%2.2d",
		int p[0], int p[1], int p[2], int p[3], int p[4], int p[5]);
	if(fmt == 'z'){
		htz := int p[6];
		if(htz >= 128){
			htz = 256-htz;
			c = '-';
		}else
			c = '+';
		s += sys->sprint(" (%c%.1f)", c, real htz/2.0);
	}
	return s;
}

dmsize := array[] of {
	31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
};

dysize(y: int): int
{
	if((y%4) == 0)
		return 366;
	return 365;
}

gtime(p: array of byte): int	# yMdhms
{
	y:=int p[0]; M:=int p[1]; d:=int p[2];
	h:=int p[3]; m:=int p[4]; s:=int p[5];;
	if(y < 70)
		return 0;
	if(M < 1 || M > 12)
		return 0;
	if(d < 1 || d > dmsize[M-1])
		return 0;
	if(h > 23)
		return 0;
	if(m > 59)
		return 0;
	if(s > 59)
		return 0;
	y += 1900;
	t := 0;
	for(i:=1970; i<y; i++)
		t += dysize(i);
	if(dysize(y)==366 && M >= 3)
		t++;
	M--;
	while(M-- > 0)
		t += dmsize[M];
	t += d-1;
	t = 24*t + h;
	t = 60*t + m;
	t = 60*t + s;
	return t;
}

l16(p: array of byte): int
{
	v := (int p[1]<<8)| int p[0];
	if (v >= 16r8000)
		v -= 16r10000;
	return v;
}

l32(p: array of byte): int
{
	return (((((int p[3]<<8)| int p[2])<<8)| int p[1])<<8)| int p[0];
}

eqs(a: array of byte, b: string): int
{
	if(len a != len b)
		return 0;
	for(i := 0; i < len a; i++)
		if(int a[i] != b[i])
			return 0;
	return 1;
}

chat(s: string)
{
	if(chatty)
		sys->fprint(stderr, "%s\n", s);
}

tolower(c: int): int
{
	if(c >= 'A' && c <= 'Z')
		return c-'A' + 'a';
	return c;
}
