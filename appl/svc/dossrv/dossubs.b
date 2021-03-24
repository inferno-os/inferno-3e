implement DosSubs;

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "dossubs.m";

include "iotrack.m";
	iotrack : IoTrack;
	Xfs, Xfile: import iotrack;

include "styx.m";
	styx: Styx;

include "dosfs.m";

include "daytime.m";
	daytime: Daytime;

debug := 0;

fd: ref Sys->FD;
g: ref Global;
nowt, nowt1: int;
tzoff: int;

#
# because we map all incoming short names from all upper to all lower case,
# and FAT cannot store mixed case names in short name form,
# we'll declare upper case as unacceptable to decide whether a long name
# is needed on output.  thus, long names are always written in the case
# in the system call, and are always read back as written; short names
# are produced by the common case of writing all lower case letters
#
isdos := array[256] of {
	'a' to 'z' => 1, 'A' to 'Z' => 0, '0' to '9' => 1,
	' ' => 1, '$' => 1, '%' => 1, '"' => 1, '-' => 1, '_' => 1, '@' => 1,
	'~' => 1, '`' => 1, '!' => 1, '(' => 1, ')' => 1, '{' => 1, '}' => 1, '^' => 1,
	'#' => 1, '&' => 1,
	* => 0
};
	
init(thisg: ref Global)
{
	g = thisg;
	iotrack = g.iotrack;
	debug = g.chatty & VERBOSE;

	sys = load Sys Sys->PATH;
	styx = g.styx;
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		panic(sys->sprint("can't load %s: %r", Daytime->PATH));
	tzoff = daytime->local(0).tzoff;
}

setup()
{
	if(g.logfile != "")
		fd = sys->create(g.logfile, Sys->OWRITE, 8r644);
	if(fd == nil)
		fd = sys->fildes(1);

	nowt = daytime->now();
	nowt1 = sys->millisec();
	tzoff = daytime->local(0).tzoff;
}

# make xf into a Dos file system... or die trying to.
dosfs(xf : ref Xfs) : int
{
	mbroffset := 0;
	i: int;
	p: ref IoTrack->Iosect;

Dmddo:
	for(;;) {
		for(i=2; i>0; i--) {
			p = iotrack->getsect(xf, 0);
			if(p == nil)
				return -1;

			if((mbroffset == 0) && (p.iobuf[0] == byte 16re9))
				break;
			
			# Check if the jump displacement (magic[1]) is too 
			# short for a FAT. DOS 4.0 MBR has a displacement of 8.
			if(p.iobuf[0] == byte 16reb &&
			   p.iobuf[2] == byte 16r90 &&
			   p.iobuf[1] != byte 16r08)
				break;

			if(i < 2 ||
			   p.iobuf[16r1fe] != byte 16r55 ||
			   p.iobuf[16r1ff] != byte 16raa) {
				i = 0;
				break;
			}

			dp := 16r1be;
			for(j:=4; j>0; j--) {
				if(debug) {
					chat(sprint("16r%2.2ux (%d,%d) 16r%2.2ux (%d,%d) %d %d...",
					int p.iobuf[dp], int p.iobuf[dp+1], 
					bytes2short(p.iobuf[dp+2: dp+4]),
					int p.iobuf[dp+4], int p.iobuf[dp+5], 
					bytes2short(p.iobuf[dp+6: dp+8]),
					bytes2int(p.iobuf[dp+8: dp+12]), 
					bytes2int(p.iobuf[dp+12:dp+16])));
				}

				# Check for a disc-manager partition in the MBR.
				# Real MBR is at lba 63. Unfortunately it starts
				# with 16rE9, hence the check above against magic.
				if(int p.iobuf[dp+4] == DMDDO) {
					mbroffset = 63*IoTrack->Sectorsize;
					iotrack->putsect(p);
					iotrack->purgebuf(xf);
					xf.offset += mbroffset;
					break Dmddo;
				}
				
				# Make sure it really is the right type, other
				# filesystems can look like a FAT
				# (e.g. OS/2 BOOT MANAGER).
				if(p.iobuf[dp+4] == FAT12 ||
				   p.iobuf[dp+4] == FAT16 ||
				   p.iobuf[dp+4] == FATHUGE)
					break;
				dp+=16;
			}

			if(j <= 0) {
				if(debug)
					chat("no active partition...");
				iotrack->putsect(p);
				return -1;
			}

			offset := bytes2int(p.iobuf[dp+8:dp+12])* IoTrack->Sectorsize;
			iotrack->putsect(p);
			iotrack->purgebuf(xf);
			xf.offset = mbroffset+offset;
		}
		break;
	}
	if(i <= 0) {
		if(debug)
			chat("bad magic...");
		iotrack->putsect(p);
		return -1;
	}

	b := Dosboot.arr2Db(p.iobuf);
	if(g.chatty)
		bootdump(b);

	bp := ref Dosbpb;
	xf.ptr = bp;
	xf.fmt = 1;

	bp.sectsize = bytes2short(b.sectsize);
	bp.clustsize = int b.clustsize;
	bp.nresrv = bytes2short(b.nresrv);
	bp.nfats = int b.nfats;
	bp.rootsize = bytes2short(b.rootsize);
	bp.volsize = bytes2short(b.volsize);
	if(bp.volsize == 0)
		bp.volsize = bytes2int(b.bigvolsize);
	bp.mediadesc = int b.mediadesc;
	bp.fatsize = bytes2short(b.fatsize);

	bp.fataddr = int bp.nresrv;
	bp.rootaddr = bp.fataddr + bp.nfats*bp.fatsize;
	i = bp.rootsize*DOSDIRSIZE + bp.sectsize-1;
	i /= bp.sectsize;
	bp.dataaddr = bp.rootaddr + i;
	bp.fatclusters = FATRESRV+(bp.volsize - bp.dataaddr)/bp.clustsize;
	if(bp.fatclusters < 4087)
		bp.fatbits = 12;
	else
		bp.fatbits = 16;
	bp.freeptr = 2;
	if(debug){
		chat(sprint("fatbits=%d (%d clusters)...",
			bp.fatbits, bp.fatclusters));
		for(i=0; i< int b.nfats; i++)
			chat(sprint("fat %d: %d...",
				i, bp.fataddr+i*bp.fatsize));
		chat(sprint("root: %d...", bp.rootaddr));
		chat(sprint("data: %d...", bp.dataaddr));
	}
	iotrack->putsect(p);
	return 0;
}

QIDPATH(dp: ref Dosptr): int
{
	return dp.addr*(IoTrack->Sectorsize/DOSDIRSIZE) + dp.offset/DOSDIRSIZE;
}

isroot(addr: int): int
{
	return addr == 0;
}

getfile(f: ref Xfile): int
{
	dp := f.ptr;
	if(dp.p!=nil)
		panic("getfile");
	if(dp.addr < 0)
		panic("getfile address");
	p := iotrack->getsect(f.xf, dp.addr);
	if(p == nil)
		return -1;

	dp.d = nil;
	if(!isroot(dp.addr)) {
		if((f.qid.path & ~Sys->CHDIR) != QIDPATH(dp)){
			if(debug) {
				chat(sprint("qid mismatch f=0x%x d=0x%x...",
					f.qid.path, QIDPATH(dp)));
			}
			iotrack->putsect(p);
			return -1;
		}
	#	dp.d = Dosdir.arr2Dd(p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	}
	dp.p = p;
	return 0;
}

putfile(f : ref Xfile)
{
	dp := f.ptr;
	if(dp.p==nil)
		panic("putfile");
	iotrack->putsect(dp.p);
	dp.p = nil;
	dp.d = nil;
}

getstart(nil: ref Xfs, d: ref Dosdir): int
{
	start := bytes2short(d.start);
#	if(xf.isfat32)
#		start |= bytes2short(d.hstart)<<16;
	return start;
}

putstart(nil: ref Xfs, d: ref Dosdir, start: int)
{
	d.start[0] = byte start;
	d.start[1] = byte (start>>8);
#	if(xf.isfat32){
#		d.hstart[0] = start>>16;
#		d.hstart[1] = start>>24;
#	}
}

#
# return the disk cluster for the iclust cluster in f
#
fileclust(f: ref Xfile, iclust: int, cflag: int): int
{

	bp := f.xf.ptr;
	dp := f.ptr;
	if(isroot(dp.addr))
		return -1;		# root directory for old FAT format does not start on a cluster boundary
	d := dp.d;
	if(d == nil){
		if(dp.p == nil)
			panic("fileclust");
		d = Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	}
	next := 0;
	start := getstart(f.xf, d);
	if(start == 0) {
		if(!cflag)
			return -1;
		start = falloc(f.xf);
		if(start <= 0)
			return -1;
		puttime(d);
		putstart(f.xf, d, start);
		dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
		dp.p.flags |= IoTrack->BMOD;
		dp.clust = 0;
	}

	clust, nskip: int;
	if(dp.clust == 0 || iclust < dp.iclust) {
		clust = start;
		nskip = iclust;
	} else {
		clust = dp.clust;
		nskip = iclust - dp.iclust;
	}

	if(g.chatty & CLUSTER_INFO  && nskip > 0 && debug)
		chat(sprint("clust %d, skip %d...", clust, nskip));

	if(clust <= 0)
		return -1;

	if(nskip > 0) {
		while(--nskip >= 0) {
			next = getfat(f.xf, clust);
			if(g.chatty & CLUSTER_INFO && debug)
				chat(sprint(".%d", next));
			if(next <= 0){
				if(!cflag)
					break;
				next = falloc(f.xf);
				if(next <= 0)
					return -1;
				putfat(f.xf, clust, next);
			}
			clust = next;
		}
		if(next <= 0)
			return -1;
		dp.clust = clust;
		dp.iclust = iclust;
	}
	if(g.chatty & CLUSTER_INFO && debug)
		chat(sprint(" clust(%d)=0x%x...", iclust, clust));
	return clust;
}

#
# return the disk sector for the isect disk sector in f,
# allocating space if necessary and cflag is set
#
fileaddr(f: ref Xfile, isect: int, cflag: int) : int
{
	bp := f.xf.ptr;
	dp := f.ptr;
	if(isroot(dp.addr)) {
		if(isect*bp.sectsize >= bp.rootsize*DOSDIRSIZE)
			return -1;
		return bp.rootaddr + isect;
	}
	clust := fileclust(f, isect/bp.clustsize, cflag);
	if(clust < 0)
		return -1;
	return clust2sect(bp, clust) + isect%bp.clustsize;
}

#
# look for a directory entry matching name
# always searches for long names which match a short name
#
# if creating (cflag is set), set address of available slot and allocate next cluster if necessary
#
searchdir(f: ref Xfile, name: string, cflag: int, lflag: int): (int, ref Dosptr)
{
	xf := f.xf;
	bp := xf.ptr;
	addr1 := -1;
	addr2 := -1;
	prevaddr1 := -1;
	o1 := 0;
	dp :=  ref Dosptr(0,0,0,0,0,0,-1,-1,nil,nil);	# prevaddr and naddr are -1
	dp.paddr = f.ptr.addr;
	dp.poffset = f.ptr.offset;
	islong :=0;
	buf := "";

	need := 1;
	if(lflag && cflag)
		need += name2de(name);
	if(!lflag) {
		name = name[0:8]+"."+name[8:11];
		i := len name -1;
		while(i >= 0 && (name[i]==' ' || name[i] == '.'))
			i--;
		name = name[0:i+1];
	}

	addr := -1;
	prevaddr: int;
	have := 0;
	for(isect:=0;; isect++) {
		prevaddr = addr;
		addr = fileaddr(f, isect, cflag);
		if(addr < 0)
			break;
		p := iotrack->getsect(xf, addr);
		if(p == nil)
			break;
		for(o:=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			dattr := int p.iobuf[o+11];
			dname0 := p.iobuf[o];
			if(dname0 == byte 16r00) {
				if(debug)
					chat("end dir(0)...");
				iotrack->putsect(p);
				if(!cflag)
					return (-1, nil);

				#
				# addr1 and o1 are the start of the dirs
				# addr2 is the optional second cluster used if the long name
				# entry does not fit within the addr1 cluster
				# have tells us the number of contiguous free dirs
				# starting at addr1.o1; need is the number needed to hold the long name
				#
				if(addr1 < 0){
					addr1 = addr;
					prevaddr1 = prevaddr;
					o1 = o;
				}
				nleft := (bp.sectsize-o)/DOSDIRSIZE;
				if(addr2 < 0 && nleft+have < need){
					addr2 = fileaddr(f, isect+1, cflag);
					if(addr2 < 0){
						if(debug)
							chat("end dir(2)...");
						return (-2, nil);
					}
				}else if(addr2 < 0)
					addr2 = addr;
				if(addr2 == addr1)
					addr2 = -1;
				if(debug)
					chat(sys->sprint("allocate addr1=%d,%d addr2=%d for %s nleft=%d have=%d need=%d", addr1, o1, addr2, name, nleft, have, need));
				dp.addr = addr1;
				dp.offset = o1;
				dp.prevaddr = prevaddr1;
				dp.naddr = addr2;
				return (0, dp);
			}

			if(dname0 == byte DOSEMPTY) {
				if(g.chatty & VERBOSE)
					chat("empty...");
				have++;
				if(addr1 == -1){
					addr1 = addr;
					o1 = o;
					prevaddr1 = prevaddr;
				}
				if(addr2 == -1 && have >= need)
					addr2 = addr;
				continue;
			}
			have = 0;
			if(addr2 == -1)
				addr1 = -1;

			if(0 && lflag && debug)
				dirdump(p.iobuf[o:o+DOSDIRSIZE],addr,o);

			if((dattr & DMLONG) == DLONG) {
				if(!islong)
					buf = "";
				islong = 1;
				buf = getnamesect(p.iobuf[o:o+DOSDIRSIZE]) + buf;	# getnamesect should return sum
				continue;
			}
			if(dattr & DVLABEL) {
				islong = 0;
				continue;
			}

			if(!islong || !lflag) 
				buf = getname(p.iobuf[o:o+DOSDIRSIZE]);
			islong = 0;

			if(g.chatty & VERBOSE)
				chat(sys->sprint("cmp: [%s] [%s]", buf, name));
			if(mystrcmp(buf, name) != 0) {
				buf="";
				continue;
			}
			if(g.chatty & VERBOSE)
				chat("found\n");

			if(cflag) {
				iotrack->putsect(p);
				return (-1,nil);
			}

			dp.addr = addr;
			dp.prevaddr = prevaddr;
			dp.offset = o;
			dp.p = p;
			#dp.d = Dosdir.arr2Dd(p.iobuf[o:o+DOSDIRSIZE]);
			return (0, dp);
		}
		iotrack->putsect(p);
	}
	if(debug)
		chat("end dir(1)...");
	if(!cflag)
		return (-1, nil);
	#
	# end of root directory or end of non-root directory on cluster boundary
	#
	if(addr1 < 0){
		addr1 = fileaddr(f, isect, 1);
		if(addr1 < 0)
			return (-2, nil);
		prevaddr1 = prevaddr;
		o1 = 0;
	}else{
		if(addr2 < 0 && have < need){
			addr2 = fileaddr(f, isect, 1);
			if(addr2 < 0)
				return (-2, nil);
		}
	}
	if(addr2 == addr1)
		addr2 = -1;
	dp.addr = addr1;
	dp.offset = o1;
	dp.prevaddr = prevaddr1;
	dp.naddr = addr2;
	return (0, dp);
}

emptydir(f: ref Xfile): int
{
	for(isect:=0;; isect++) {
		addr := fileaddr(f, isect, 0);
		if(addr < 0)
			break;

		p := iotrack->getsect(f.xf, addr);
		if(p == nil)
			return -1;

		for(o:=0; o<f.xf.ptr.sectsize; o+=DOSDIRSIZE) {
			dname0 := p.iobuf[o];
			dattr := int p.iobuf[o+11];

			if(dname0 == byte 16r00) {
				iotrack->putsect(p);
				return 0;
			}

			if(dname0 == byte DOSEMPTY || dname0 == byte '.')
				continue;

			if(dattr & DVLABEL)
				continue;		# ignore any long name entries: it's empty if there are no short ones

			iotrack->putsect(p);
			return -1;
		}
		iotrack->putsect(p);
	}
	return 0;
}

readdir(f:ref Xfile, offset: int, count: int) : (int, array of byte)
{
	xf := f.xf;
	bp := xf.ptr;
	rcnt := 0;
	buf := array[Styx->MAXFDATA] of byte;
	islong :=0;
	longnamebuf:="";

	if(count <= 0)
		return (0, nil);

	for(isect:=0;; isect++) {
		addr := fileaddr(f, isect, 0);
		if(addr < 0)
			break;
		p := iotrack->getsect(xf, addr);
		if(p == nil)
			return (-1,nil);

		for(o:=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			dname0 := int p.iobuf[o];
			dattr := int p.iobuf[o+11];

			if(dname0 == 16r00) {
				iotrack->putsect(p);
				return (rcnt,buf[0:rcnt]);
			}

			if(dname0 == DOSEMPTY)
				continue;

			if(dname0 == '.') {
				dname1 := int p.iobuf[o+1];
				if(dname1 == ' ' || dname1 == 0)
					continue;
				dname2 := int p.iobuf[o+2];
				if(dname1 == '.' &&
				  (dname2 == ' ' || dname2 == 0))
					continue;
			}

			if((dattr & DMLONG) == DLONG) {
				if(!islong)
					longnamebuf = "";
				longnamebuf = getnamesect(p.iobuf[o:o+DOSDIRSIZE]) + longnamebuf;
				islong = 1;
				continue;
			}
			if(dattr & DVLABEL) {
				islong = 0;
				continue;
			}

			if(offset > 0) {
				offset -= Styx->DIRLEN;
				islong = 0;
				continue;
			}
			dir := getdir(p.iobuf[o:o+DOSDIRSIZE], addr, o);
			if(islong) {
				dir.name = longnamebuf;
				longnamebuf = "";
				islong = 0;
			}
			tmpbuf := styx->packdir(*dir);
			buf[rcnt:] = tmpbuf;
			rcnt += len tmpbuf;
			if(rcnt >= count) {
				iotrack->putsect(p);
				return (rcnt, buf[0:rcnt]);
			}
		}
		iotrack->putsect(p);
	}

	return (rcnt, buf[0:rcnt]);
}

walkup(f: ref Xfile) : (int, ref Dosptr)
{
	bp := f.xf.ptr;
	dp := f.ptr;
	o : int;
	ndp:= ref Dosptr(0,0,0,0,0,0,-1,-1,nil,nil);
	ndp.addr = dp.paddr;
	ndp.offset = dp.poffset;

	if(debug)
		chat(sprint("walkup: paddr=0x%x...", dp.paddr));

	if(dp.paddr == 0)
		return (0,ndp);

	p := iotrack->getsect(f.xf, dp.paddr);
	if(p == nil)  
		return (-1,nil);

	if(debug)
		dirdump(p.iobuf[dp.poffset:dp.poffset+DOSDIRSIZE],dp.paddr,dp.poffset);

	xd := Dosdir.arr2Dd(p.iobuf[dp.poffset:dp.poffset+DOSDIRSIZE]);
	start := getstart(f.xf, xd);
	if(g.chatty & CLUSTER_INFO)
		if(debug)
			chat(sprint("start=0x%x...", start));
	iotrack->putsect(p);
	if(start == 0)
		return (-1,nil);

	#
	# check that parent's . points to itself
	#
	p = iotrack->getsect(f.xf, bp.dataaddr + (start-2)*bp.clustsize);
	if(p == nil)
		return (-1,nil);

	if(debug)
		dirdump(p.iobuf,0,0);

	xd = Dosdir.arr2Dd(p.iobuf);
	if(p.iobuf[0]!= byte '.' ||
	   p.iobuf[1]!= byte ' ' ||
	   start != getstart(f.xf, xd)) { 
 		if(p!=nil) 
			iotrack->putsect(p);
		return (-1,nil);
	}

	if(debug)
		dirdump(p.iobuf[DOSDIRSIZE:],0,0);

	#
	# parent's .. is the next entry, and has start of parent's parent
	#
	xd = Dosdir.arr2Dd(p.iobuf[DOSDIRSIZE:]);
	if(p.iobuf[32] != byte '.' || p.iobuf[33] != byte '.') { 
 		if(p != nil) 
			iotrack->putsect(p);
		return (-1,nil);
	}

	#
	# we're done if parent is root
	#
	pstart := getstart(f.xf, xd);
	iotrack->putsect(p);
	if(pstart == 0)
		return (0, ndp);

	#
	# check that parent's . points to itself
	#
	p = iotrack->getsect(f.xf, clust2sect(bp, pstart));
	if(p == nil) {
		if(debug)
			chat(sprint("getsect %d failed\n", pstart));
		return (-1,nil);
	}
	if(debug)
		dirdump(p.iobuf,0,0);
	xd = Dosdir.arr2Dd(p.iobuf);
	if(p.iobuf[0]!= byte '.' ||
	   p.iobuf[1]!=byte ' ' || 
	   pstart!=getstart(f.xf, xd)) { 
 		if(p != nil) 
			iotrack->putsect(p);
		return (-1,nil);
	}

	#
	# parent's parent's .. is the next entry, and has start of parent's parent's parent
	#
	if(debug)
		dirdump(p.iobuf[DOSDIRSIZE:],0,0);

	xd = Dosdir.arr2Dd(p.iobuf[DOSDIRSIZE:]);
	if(xd.name[0] != '.' || xd.name[1] !=  '.') { 
 		if(p != nil) 
			iotrack->putsect(p);
		return (-1,nil);
	}
	ppstart :=getstart(f.xf, xd);
	iotrack->putsect(p);

	#
	# open parent's parent's parent, and walk through it until parent's paretn is found
	# need this to find parent's parent's addr and offset
	#
	ppclust := ppstart;
	# TO DO: FAT32
	if(ppclust != 0)
		k := clust2sect(bp, ppclust);
	else
		k = bp.rootaddr;
	p = iotrack->getsect(f.xf, k);
	if(p == nil) {
		if(debug)
			chat(sprint("getsect %d failed\n", k));
		return (-1,nil);
	}

	if(debug)
		dirdump(p.iobuf,0,0);

	if(ppstart) {
		xd = Dosdir.arr2Dd(p.iobuf);
		if(p.iobuf[0]!= byte '.' ||
		   p.iobuf[1]!= byte ' ' || 
		   ppstart!=getstart(f.xf, xd)) { 
 			if(p!=nil) 
				iotrack->putsect(p);
			return (-1,nil);
		}
	}

	for(so:=1; ;so++) {
		for(o=0; o<bp.sectsize; o+=DOSDIRSIZE) {
			xdname0 := p.iobuf[o];
			if(xdname0 == byte 16r00) {
				if(debug)
					chat("end dir\n");
 				if(p != nil) 
					iotrack->putsect(p);
				return (-1,nil);
			}

			if(xdname0 == byte DOSEMPTY)
				continue;

			#xd = Dosdir.arr2Dd(p.iobuf[o:o+DOSDIRSIZE]);
			xdstart:= p.iobuf[o+26:o+28];	# TO DO: getstart
			if(bytes2short(xdstart) == pstart) {
				iotrack->putsect(p);
				ndp.paddr = k;
				ndp.poffset = o;
				return (0,ndp);
			}
		}
		if(ppclust) {
			if(so%bp.clustsize == 0) {
				ppstart = getfat(f.xf, ppstart);
				if(ppstart < 0){
					if(debug)
						chat(sprint("getfat %d fail\n", 
							ppstart));
 					if(p != nil) 
						iotrack->putsect(p);
					return (-1,nil);
				}
			}
			k = clust2sect(bp, ppclust) + 
				so%bp.clustsize;
		}
		else {
			if(so*bp.sectsize >= bp.rootsize*DOSDIRSIZE) { 
 				if(p != nil) 
					iotrack->putsect(p);
				return (-1,nil);
			}
			k = bp.rootaddr + so;
		}
		iotrack->putsect(p);
		p = iotrack->getsect(f.xf, k);
		if(p == nil) {
			if(debug)
				chat(sprint("getsect %d failed\n", k));
			return (-1,nil);
		}
	}
	iotrack->putsect(p);
	ndp.paddr = k;
	ndp.poffset = o;
	return (0,ndp);
}

readfile(f: ref Xfile, offset: int, count: int): (int, array of byte)
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;

	length := bytes2int(dp.p.iobuf[dp.offset+28:dp.offset+32]);
	rcnt := 0;
	if(offset >= length)
		return (0,nil);
 	buf := array[Styx->MAXFDATA] of byte;
	if(offset+count >= length)
		count = length - offset;
	isect := offset/bp.sectsize;
	o := offset%bp.sectsize;
	while(count > 0) {
		addr := fileaddr(f, isect++, 0);
		if(addr < 0)
			break;
		c := bp.sectsize - o;
		if(c > count)
			c = count;
		p := iotrack->getsect(xf, addr);
		if(p == nil)
			return (-1, nil);
		buf[rcnt:] = p.iobuf[o:o+c];
		iotrack->putsect(p);
		count -= c;
		rcnt += c;
		o = 0;
	}
	return (rcnt, buf[0:rcnt]);
}

writefile(f: ref Xfile, buf: array of byte, offset,count: int): int
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;
	addr := 0;
	c : int;
	rcnt := 0;
	p : ref iotrack->Iosect;

	d := dp.d;
	if(d == nil)
		d = Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);
	isect := offset/bp.sectsize;

	o := offset%bp.sectsize;
	while(count > 0) {
		addr = fileaddr(f, isect++, 1);
		if(addr < 0)
			break;
		c = bp.sectsize - o;
		if(c > count)
			c = count;
		if(c == bp.sectsize){
			p = iotrack->getosect(xf, addr);
			if(p == nil)
				return -1;
			p.flags = 0;
		}else{
			p = iotrack->getsect(xf, addr);
			if(p == nil)
				return -1;
		}
		p.iobuf[o:] = buf[rcnt:rcnt+c];
		p.flags |= IoTrack->BMOD;
		iotrack->putsect(p);
		count -= c;
		rcnt += c;
		o = 0;
	}
	if(rcnt <= 0 && addr < 0)
		return -2;
	length := 0;
	dlen := bytes2int(d.length);
	if(rcnt > 0)
		length = offset+rcnt;
	else if(dp.addr && dp.clust) {
		c = bp.clustsize*bp.sectsize;
		if(dp.iclust > (dlen+c-1)/c)
			length = c*dp.iclust;
	}
	if(length > dlen) {
		d.length[0] = byte length;
		d.length[1] = byte (length>>8);
		d.length[2] = byte (length>>16);
		d.length[3] = byte (length>>24);
	}
	puttime(d);
	dp.p.flags |= IoTrack->BMOD;
	dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
	return rcnt;
}

truncfile(f : ref Xfile) : int
{
	xf := f.xf;
	bp := xf.ptr;
	dp := f.ptr;
	d := Dosdir.arr2Dd(dp.p.iobuf[dp.offset:dp.offset+DOSDIRSIZE]);

	clust := getstart(f.xf, d);
	putstart(f.xf, d, 0);
	while(clust > 0) {
		next := getfat(xf, clust);
		putfat(xf, clust, 0);
		clust = next;
	}

	d.length[0] = byte 0;
	d.length[1] = byte 0;
	d.length[2] = byte 0;
	d.length[3] = byte 0;

	dp.p.iobuf[dp.offset:] = Dosdir.Dd2arr(d);
	dp.iclust = 0;
	dp.clust = 0;
	dp.p.flags |= IoTrack->BMOD;

	return 0;
}

getdir(arr : array of byte, addr,offset: int) :ref Sys->Dir 
{
	dp := ref Sys->Dir;

	if(arr == nil || addr == 0) {
		dp.name = "";
		dp.qid.path = Sys->CHDIR;
		dp.length =0;
		dp.mode = Sys->CHDIR|8r777;
	}
	else {
		dp.name = getname(arr);
		for(i:=0; i < len dp.name; i++)
			if(dp.name[i]>='A' && dp.name[i]<='Z')
				dp.name[i] = dp.name[i]-'A'+'a';

		# dp.qid.path = bytes2short(d.start); 
		dp.qid.path = addr*(IoTrack->Sectorsize/DOSDIRSIZE) + offset/DOSDIRSIZE;
		dattr := int arr[11];

		if(dattr & DRONLY)
			dp.mode = 8r444;
		else
			dp.mode = 8r666;

		dp.atime = gtime(arr);
		dp.mtime = dp.atime;
		if(dattr & DDIR) {
			dp.length = 0;
			dp.qid.path |= Sys->CHDIR;
			dp.mode |= Sys->CHDIR|8r111;
		}
		else 
			dp.length = bytes2int(arr[28:32]);

		if(dattr & DSYSTEM)
			dp.mode |= Styx->CHEXCL;
	}

	dp.qid.vers = 0;
	dp.dtype = 0;
	dp.dev = 0;
	dp.uid = "dos";
	dp.gid = "srv";

	return dp;
}

putdir(d: ref Dosdir, dp: ref Sys->Dir)
{
	if(dp.mode & 2)
		d.attr &= byte ~DRONLY;
	else
		d.attr |= byte DRONLY;

	if(dp.mode & Styx->CHEXCL)
		d.attr |= byte DSYSTEM;
	else
		d.attr &= byte ~DSYSTEM;
	xputtime(d, dp.mtime);
}

getname(arr : array of byte) : string
{
	p: string;
	for(i:=0; i<8; i++) {
		c := int arr[i];
		if(c == 0 || c == ' ')
			break;
		if(i == 0 && c == 16r05)
			c = 16re5;
		p[len p] = c;
	}
	for(i=8; i<11; i++) {
		c := int arr[i];
		if(c == 0 || c == ' ')
			break;
		if(i == 8)
			p[len p] = '.';
		p[len p] = c;
	}

	return p;
}

dosname(p: string): (string, string)
{
	name := "        ";
	for(i := 0; i < len p && i < 8; i++) {
		c := p[i];
		if(c >= 'a' && c <= 'z')
			c += 'A'-'a';
		else if(c == '.')
			break;
		name[i] = c;
	}
	ext := "   ";
	for(j := len p - 1; j >= i; j--) {
		if(p[j] == '.') {
			q := 0;
			for(j++; j < len p && q < 3; j++) {
				c := p[j];
				if(c >= 'a' && c <= 'z')
					c += 'A'-'a';
				ext[q++] = c;
			}
			break;
		}
	}
	return (name, ext);
}

putname(p: string, d: ref Dosdir)
{
	if ((int d.attr & DLONG) == DLONG)
		panic("putname of long name");
	(d.name, d.ext) = dosname(p);
}

mystrcmp(s1, s2 : string) : int
{
	n := len s1;
	if(n != len s2)
		return 1;

	for(i := 0; i < n; i++) {
		c := s1[i];
		if(c >= 'A' && c <= 'Z')
			c -= 'A'-'a';
		d := s2[i];
		if(d >= 'A' && d <= 'Z')
			d -= 'A'-'a';
		if(c != d)
			return 1;
	}
	return 0;
}

#
# return the length of a long name in directory
# entries or zero if it's normal dos
#
name2de(p: string): int
{
	ext := 0;
	name := 0;

	for(end := len p; --end >= 0 && p[end] != '.';)
		ext++;

	if(end > 0) {
		name = end;
		for(i := 0; i < end; i++) {
			if(p[i] == '.')
				return (len p+DOSRUNES-1)/DOSRUNES;
		}
	}
	else {
		name = ext;
		ext = 0;
	}

	if(name <= 8 && ext <= 3 && isvalidname(p))
		return 0;

	return (len p+DOSRUNES-1)/DOSRUNES;
}

isvalidname(s: string): int
{
	dot := 0;
	for(i := 0; i < len s; i++)
		if(s[i] == '.') {
			if(++dot > 1 || i == len s-1)
				return 0;
		} else if(s[i] > len isdos || isdos[s[i]] == 0)
			return 0;
	return 1;
}

getnamesect(arr : array of byte) : string
{
	s: string;
	c: int;

	for(i := 1; i < 11; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	for(i = 14; i < 26; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	for(i = 28; i < 32; i += 2) {
		c = int arr[i] | (int arr[i+1] << 8);
		if(c == 0)
			return s;
		s[len s] = c;
	}
	return s;
}

# takes a long filename and converts to a short dos name, with a tag number.
long2short(src : string,val : int) : string
{
	dst :="           ";
	skip:=0;
	xskip:=0;
	ext:=len src-1;
	while(ext>=0 && src[ext]!='.')
		ext--;

	if (ext < 0)
		ext=len src -1;

	# convert name eliding periods 
	j:=0;
	for(name := 0; name < ext && j<8; name++){
		c := src[name];
		if(c!='.' && c!=' ' && c!='\t') {
			if(c>='a' && c<='z')
				dst[j++] = c-'a'+'A';
			else
				dst[j++] = c;
		}	
		else
			skip++;
	}

	# convert extension 
	j=8;
	for(xname := ext+1; xname < len src && j<11; xname++) {
		c := src[xname];
		if(c!=' ' && c!='\t'){
			if (c>='a' && c<='z')
				dst[j++] = c-'a'+'A';
			else
				dst[j++] = c;
		}else
			xskip++;
	}
	
	# add tag number
	j =1; 
	for(i:=val; i > 0; i/=10)
		j++;

	if (8-j<name) 
		name = 8-j;
	else
		name -= skip;

	dst[name]='~';
	for(; val > 0; val /= 10)
		dst[name+ --j] = (val%10)+'0';

	if(debug)
		chat(sprint("returning dst [%s] src [%s]\n",dst,src));

	return dst;			
}

getfat(xf: ref Xfs, n: int): int
{
	bp := xf.ptr;
	k := 0; 

	if(n < 2 || n >= bp.fatclusters)
		return -1;
	fb := bp.fatbits;
	k = (fb*n) >> 3;
	if(k < 0 || k >= bp.fatsize*bp.sectsize)
		panic("getfat");

	sect := k/bp.sectsize + bp.fataddr;
	o := k%bp.sectsize;
	p := iotrack->getsect(xf, sect);
	if(p == nil)
		return -1;
	k = int p.iobuf[o++];
	if(o >= bp.sectsize) {
		iotrack->putsect(p);
		p = iotrack->getsect(xf, sect+1);
		if(p == nil)
			return -1;
		o = 0;
	}
	k |= int p.iobuf[o++]<<8;
	if(fb == 32){
		# fat32 is really fat28
		k |= int p.iobuf[o++] << 16;
		k |= (int p.iobuf[o] & 16r0F) << 24;
		fb = 28;
	}
	iotrack->putsect(p);
	if(fb == 12) {
		if(n&1)
			k >>= 4;
		else
			k &= 16rfff;
	}

	if(g.chatty & FAT_INFO)
		if(debug)
			chat(sprint("fat(0x%x)=0x%x...", n, k));

	#
	# check for out of range
	#
	if(k >= (1<<fb) - 8)
		return -1;
	return k;
}

putfat(xf: ref Xfs, n, val: int)
{
	bp := xf.ptr;
	if(n < 2 || n >= bp.fatclusters)
		panic(sprint("putfat n=%d", n));
	k := (bp.fatbits*n) >> 3;
	if(k >= bp.fatsize*bp.sectsize)
		panic("putfat");
	sect := k/bp.sectsize + bp.fataddr;
	for(; sect<bp.rootaddr; sect+=bp.fatsize) {
		o := k%bp.sectsize;
		p := iotrack->getsect(xf, sect);
		if(p == nil)
			continue;
		case bp.fatbits {
		12 =>
			if(n&1) {
				p.iobuf[o] &= byte 16r0f;
				p.iobuf[o++] |= byte (val<<4);
				if(o >= bp.sectsize) {
					p.flags |= IoTrack->BMOD;
					iotrack->putsect(p);
					p = iotrack->getsect(xf, sect+1);
					if(p == nil)
						continue;
					o = 0;
				}
				p.iobuf[o] = byte (val>>4);
			}
			else {
				p.iobuf[o++] = byte val;
				if(o >= bp.sectsize) {
					p.flags |= IoTrack->BMOD;
					iotrack->putsect(p);
					p = iotrack->getsect(xf, sect+1);
					if(p == nil)
						continue;
					o = 0;
				}
				p.iobuf[o] &= byte 16rf0;
				p.iobuf[o] |= byte ((val>>8)&16r0f);
			}
		16 =>
			p.iobuf[o++] = byte val;
			p.iobuf[o] = byte (val>>8);
		32 =>	# fat32 is really fat28
			p.iobuf[o++] = byte val;
			p.iobuf[o++] = byte (val>>8);
			p.iobuf[o++] = byte (val>>16);
			p.iobuf[o] = byte ((int p.iobuf[o] & 16rF0) | ((val>>24) & 16r0F));
		* =>
			panic("putfat fatbits");
		}

		p.flags |= IoTrack->BMOD;
		iotrack->putsect(p);
	}
}

falloc(xf: ref Xfs): int
{
	bp := xf.ptr;
	n := bp.freeptr;
	for(;;) {
		if(getfat(xf, n) == 0)
			break;
		if(++n >= bp.fatclusters)
			n = FATRESRV;
		if(n == bp.freeptr)
			return 0;
	}
	bp.freeptr = n+1;
	if(bp.freeptr >= bp.fatclusters)
		bp.freeptr = FATRESRV;
	putfat(xf, n, int 16rffffffff);
	k := clust2sect(bp, n);
	for(i:=0; i<bp.clustsize; i++) {
		p := iotrack->getosect(xf, k+i);
		if(p == nil)
			return -1;
		for(j:=0; j<len p.iobuf; j++)
			p.iobuf[j] = byte 0;
		p.flags = IoTrack->BMOD;
		iotrack->putsect(p);
	}
	return n;
}

clust2sect(bp: ref Dosbpb, clust: int): int
{
	return bp.dataaddr + (clust - FATRESRV)*bp.clustsize;
}

sect2clust(bp: ref Dosbpb, sect: int): int
{
	c := (sect - bp.dataaddr) / bp.clustsize + FATRESRV;
	# assert(sect == clust2sect(bp, c));
	return c;
}

bootdump(b : ref Dosboot)
{
	if(!(g.chatty & VERBOSE))
		return;

	if(debug) {
		chat(sprint("magic: 0x%2.2x 0x%2.2x 0x%2.2x\n",
			int b.magic[0], int b.magic[1], int b.magic[2]));
		chat(sprint("version: \"%8.8s\"\n", string b.version));
		chat(sprint("sectsize: %d\n", bytes2short(b.sectsize)));
		chat(sprint("allocsize: %d\n", int b.clustsize));
		chat(sprint("nresrv: %d\n", bytes2short(b.nresrv)));
		chat(sprint("nfats: %d\n", int b.nfats));
		chat(sprint("rootsize: %d\n", bytes2short(b.rootsize)));
		chat(sprint("volsize: %d\n", bytes2short(b.volsize)));
		chat(sprint("mediadesc: 0x%2.2x\n", int b.mediadesc));
		chat(sprint("fatsize: %d\n", bytes2short(b.fatsize)));
		chat(sprint("trksize: %d\n", bytes2short(b.trksize)));
		chat(sprint("nheads: %d\n", bytes2short(b.nheads)));
		chat(sprint("nhidden: %d\n", bytes2int(b.nhidden)));
		chat(sprint("bigvolsize: %d\n", bytes2int(b.bigvolsize)));
		chat(sprint("driveno: %d\n", int b.driveno));
		chat(sprint("bootsig: 0x%2.2x\n", int b.bootsig));
		chat(sprint("volid: 0x%8.8x\n", bytes2int(b.volid)));
		chat(sprint("label: \"%11.11s\"\n", string b.label));
	}
}

xputtime(d : ref Dosdir, s: int)
{
	if(s == 0)
		t := daytime->local((sys->millisec() - nowt1)/1000 + nowt);
	else
		t = daytime->local(s);
	x := (t.hour<<11) | (t.min<<5) | (t.sec>>1);
	d.time[0] = byte x;
	d.time[1] = byte (x>>8);
	x = ((t.year-80)<<9) | ((t.mon+1)<<5) | t.mday;
	d.date[0] = byte x;
	d.date[1] = byte (x>>8);
}

puttime(d : ref Dosdir)
{
	xputtime(d, 0);
}

gtime(a: array of byte): int
{
	tm := ref Daytime->Tm;
	i := bytes2short(a[22:24]);	# dos time
	tm.hour = i >> 11;
	tm.min = (i>>5) & 63;
	tm.sec = (i & 31) << 1;
	i = bytes2short(a[24:26]);	# dos date
	tm.year = 80 + (i>>9);
	tm.mon = ((i>>5) & 15) - 1;
	tm.mday = i & 31;
	tm.tzoff = tzoff;	# DOS time is local time
	return daytime->tm2epoch(tm);
}

dirdump(arr : array of byte, addr, offset : int) : string
{
	if(!g.chatty)
		return "";
	attrchar:= "rhsvda67";
	d := Dosdir.arr2Dd(arr);
	buf := sprint("\"%.8s.%.3s\" ", d.name, d.ext);
	p_i:=7;

	for(i := 16r80; i != 0; i >>= 1) {
		if((d.attr & byte i) ==  byte i)
			ch := attrchar[p_i];
		else 
			ch = '-'; 
		buf += sprint("%c", ch);
		p_i--;
	}

	i = bytes2short(d.time);
	buf += sprint(" %2.2d:%2.2d:%2.2d", i>>11, (i>>5)&63, (i&31)<<1);
	i = bytes2short(d.date);
	buf += sprint(" %2.2d.%2.2d.%2.2d", 80+(i>>9), (i>>5)&15, i&31);
	buf += sprint(" %d %d", bytes2short(d.start), bytes2short(d.length));
	buf += sprint(" %d %d\n",addr,offset);

	if(debug)
		chat(buf);

	return buf;
}

putnamesect(longname: string, curslot: int, first: int, sum: int, a: array of byte)
{
	for(i := 0; i < DOSDIRSIZE; i++)
		a[i] = byte 16rFF;
	if(first)
		a[0] = byte (16r40 | curslot);
	else 
		a[0] = byte curslot;
	a[11] = byte DLONG;
	a[12] = byte 0;
	a[13] = byte sum;
	a[26] = byte 0;
	a[27] = byte 0;
	# a[1:1+10] = characters 1 to 5
	n := len longname;
	j := (curslot-1)*DOSRUNES;
	for(i = 1; i < 1+10; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c >> 8);
		if(c == 0)
			return;
	}
	# a[14:14+12] = characters 6 to 11
	for(i = 14; i < 14+12; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c >> 8);
		if(c == 0)
			return;
	}
	# a[28:28+4] characters 12 to 13
	for(i = 28; i < 28+4; i += 2){
		c := 0;
		if(j < n)
			c = longname[j++];
		a[i] = byte c;
		a[i+1] = byte (c>>8);
		if(c == 0)
			return;
	}
}

putlongname(xf: ref Xfs, ndp: ref Dosptr, name: string, sname: string): int
{
	bp := xf.ptr;
	first := 1;
	sum := aliassum(sname);
	for(nds := (len name+DOSRUNES-1)/DOSRUNES; nds > 0; nds--) {
		putnamesect(name, nds, first, sum, ndp.p.iobuf[ndp.offset:]);
		first = 0;
		ndp.offset += DOSDIRSIZE;
		if(ndp.offset == bp.sectsize) {
			if(debug)
				chat(sys->sprint("long name %s entry %d/%d crossing sector, addr=%d, naddr=%d", name, nds, (len name+DOSRUNES-1)/DOSRUNES, ndp.addr, ndp.naddr));
			ndp.p.flags |= IoTrack->BMOD;
			iotrack->putsect(ndp.p);
			ndp.p = nil;
			ndp.d = nil;

			# switch to the next cluster for the next long entry or the subsequent normal dir. entry
			# naddr must be set up correctly by searchdir because we'll need one or the other

			ndp.prevaddr = ndp.addr;
			ndp.addr = ndp.naddr;
			ndp.naddr = -1;
			if(ndp.addr < 0)
				return -1;
			ndp.p = iotrack->getsect(xf, ndp.addr);
			if(ndp.p == nil)
				return -1;
			ndp.offset = 0;
		}
	}
	return 0;
}

bytes2int(a: array of byte): int 
{
	return (((((int a[3] << 8) | int a[2]) << 8) | int a[1]) << 8) | int a[0];
}

bytes2short(a: array of byte): int 
{
	return (int a[1] << 8) | int a[0];
}

chat(s: string)
{
	if(g.chatty & VERBOSE)
		sys->fprint(fd, "%s", s);
}

panic(s: string)
{
	sys->fprint(fd, "dosfs: panic: %s\n", s);
	<-chan of int;	# hang here
#	exit;
}

Dosboot.arr2Db(arr: array of byte): ref Dosboot
{
	db := ref Dosboot;
	db.magic = arr[0:3];
	db.version = arr[3:11];
	db.sectsize = arr[11:13];
	db.clustsize = arr[13];
	db.nresrv = arr[14:16];
	db.nfats = arr[16];
	db.rootsize = arr[17:19];
	db.volsize = arr[19:21];
	db.mediadesc = arr[21];
	db.fatsize = arr[22:24];
	db.trksize = arr[24:26];
	db.nheads = arr[26:28];
	db.nhidden = arr[28:32];
	db.bigvolsize = arr[32:36];
	db.driveno = arr[36];
	db.bootsig = arr[38];
	db.volid = arr[39:43];
	db.label = arr[43:54];
	return db;
}

Dosdir.arr2Dd(arr : array of byte) : ref Dosdir
{
	dir := ref Dosdir;
	for(i := 0; i < 8; i++)
		dir.name[len dir.name] = int arr[i];
	for(; i < 11; i++)
		dir.ext[len dir.ext] = int arr[i];
	dir.attr = arr[11];
	dir.reserved = arr[12:22];
	dir.time = arr[22:24];
	dir.date = arr[24:26];
	dir.start = arr[26:28];
	dir.length = arr[28:32];
	return dir;
}

Dosdir.Dd2arr(d : ref Dosdir) : array of byte
{
	a := array[32] of byte;
	i:=0;
	for(j := 0; j < len d.name; j++)
		a[i++] = byte d.name[j];
	for(; j<8; j++)
		a[i++]= byte 0;
	for(j=0; j<len d.ext; j++)
		a[i++] = byte d.ext[j];
	for(; j<3; j++)
		a[i++]= byte 0;
	a[i++] = d.attr;
	for(j=0; j<10; j++)
		a[i++] = d.reserved[j];
	for(j=0; j<2; j++)
		a[i++] = d.time[j];
	for(j=0; j<2; j++)
		a[i++] = d.date[j];
	for(j=0; j<2; j++)
		a[i++] = d.start[j];
	for(j=0; j<4; j++)
		a[i++] = d.length[j];
	return a;
}

#
# checksum of short name for use in long name directory entries
# assumes sname is already padded correctly to 8+3
#
aliassum(sname: string): int
{
	i := 0;
	for(sum:=0; i<11; i++)
		sum = (((sum&1)<<7)|((sum&16rfe)>>1))+sname[i];
	return sum;
}
