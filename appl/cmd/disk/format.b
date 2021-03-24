implement Format;

include "sys.m";
include "draw.m";
include "daytime.m";

sys : Sys;
daytime : Daytime;

Format : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

#
#  floppy types (all MFM encoding)
#
Type : adt {
	name : string;
	bytes : int;		# bytes/sector
	sectors : int;	# sectors/track
	heads : int;	# number of heads
	tracks : int;	# tracks/disk
	media : int;	# media descriptor byte
	cluster : int;	# default cluster size
};

NTYPES : con 5;

floppytype := array[NTYPES] of  {
	Type ( "3½HD",	512, 18,	2,	80,	16rf0,	1 ),
	Type ( "3½DD",	512,	  9,	2,	80,	16rf9,	2 ),
	Type ( "5¼HD",	512,	15,	2,	80,	16rf9,	1 ),
	Type ( "5¼DD",	512,	  9,	2,	40,	16rfd,	2 ),
	Type	( "hard",	512,	  0,	0,	  0,	16rf8,	4 ),
};

Geom : adt {
	h: int;	# number of heads
	s: int;	# sectors/track
};

guess := array[] of {
	Geom ( 9, 2 ),		# daft one to cover very small partitions
	Geom ( 64, 32 ),
	Geom ( 64, 63 ),
	Geom ( 128, 63 ),
	Geom ( 255, 63 ),
	Geom ( 0, 0 ),
};

# offsets in DOS boot area
DB_MAGIC 	: con 0;
DB_VERSION	: con 3;
DB_SECTSIZE	: con 11;
DB_CLUSTSIZE	: con 13;
DB_NRESRV	: con 14;
DB_NFATS	: con 16;
DB_ROOTSIZE	: con	17;
DB_VOLSIZE	: con	19;
DB_MEDIADESC : con 21;
DB_FATSIZE	: con 22;
DB_TRKSIZE	: con 24;
DB_NHEADS	: con 26;
DB_NHIDDEN	: con 28;
DB_BIGVOLSIZE : con 32;
DB_DRIVENO 	: con 36;
DB_RESERVED0 : con 37;
DB_BOOTSIG	: con 38;
DB_VOLID	: con 39;
DB_LABEL	: con 43;
DB_TYPE		: con 54;

DB_VERSIONSIZE : con 8;
DB_LABELSIZE	: con 11;
DB_TYPESIZE	: con 8;
DB_SIZE		: con 62;

# offsets in DOS directory
DD_NAME	: con 0;
DD_EXT		: con 8;
DD_ATTR		: con 11;
DD_RESERVED 	: con 12;
DD_TIME		: con 22;
DD_DATE		: con 24;
DD_START	: con 26;
DD_LENGTH	: con 28;

DD_NAMESIZE	: con 8;
DD_EXTSIZE	: con 3;
DD_SIZE		: con 32;

DRONLY	: con 16r01;
DHIDDEN	: con 16r02;
DSYSTEM	: con byte 16r04;
DVLABEL	: con byte 16r08;
DDIR	: con byte 16r10;
DARCH	: con byte 16r20;

BP_SIZE	: con 512;

#  the boot program for the boot sector.
bootprog := array[BP_SIZE] of {
16r000 =>
	byte 16rEB, byte 16r3C, byte 16r90, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00,
	byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00,
16r03E =>
	byte 16rFA, byte 16rFC, byte 16r8C, byte 16rC8, byte 16r8E, byte 16rD8, byte 16r8E, byte 16rD0,
	byte 16rBC, byte 16r00, byte 16r7C, byte 16rBE, byte 16r77, byte 16r7C, byte 16rE8, byte 16r19,
	byte 16r00, byte 16r33, byte 16rC0, byte 16rCD, byte 16r16, byte 16rBB, byte 16r40, byte 16r00,
	byte 16r8E, byte 16rC3, byte 16rBB, byte 16r72, byte 16r00, byte 16rB8, byte 16r34, byte 16r12,
	byte 16r26, byte 16r89, byte 16r07, byte 16rEA, byte 16r00, byte 16r00, byte 16rFF, byte 16rFF,
	byte 16rEB, byte 16rD6, byte 16rAC, byte 16r0A, byte 16rC0, byte 16r74, byte 16r09, byte 16rB4,
	byte 16r0E, byte 16rBB, byte 16r07, byte 16r00, byte 16rCD, byte 16r10, byte 16rEB, byte 16rF2,
	byte 16rC3,  byte 'N',  byte 'o',  byte 't',  byte ' ',  byte 'a',  byte ' ',  byte 'b',
	byte 'o',  byte 'o',  byte 't',  byte 'a',  byte 'b',  byte 'l',  byte 'e',  byte ' ',
	byte 'd',  byte 'i',  byte 's',  byte 'c',  byte ' ',  byte 'o',  byte 'r',  byte ' ',
	byte 'd',  byte 'i',  byte 's',  byte 'c',  byte ' ',  byte 'e',  byte 'r',  byte 'r',
	byte 'o',  byte 'r', byte '\r', byte '\n',  byte 'P',  byte 'r',  byte 'e',  byte 's',
	byte 's',  byte ' ',  byte 'a',  byte 'l',  byte 'm',  byte 'o',  byte 's',  byte 't',
	byte ' ',  byte 'a',  byte 'n',  byte 'y',  byte ' ',  byte 'k',  byte 'e',  byte 'y',
	byte ' ',  byte 't',  byte 'o',  byte ' ',  byte 'r',  byte 'e',  byte 'b',  byte 'o',
	byte 'o',  byte 't',  byte '.',  byte '.',  byte '.', byte 16r00, byte 16r00, byte 16r00,
16r1F0 =>
	byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00,
	byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r00, byte 16r55, byte 16rAA,
* =>
	byte 16r00,
};

dev : string;
clustersize : int;
fat: array of byte;	# the fat
fatbits : int;
fatsecs : int;
fatlast : int;	# last cluster allocated
clusters : int;
volsecs : int;
root : array of byte;	# first block of root
rootsecs : int;
rootfiles : int;
rootnext : int;
t : Type;
fflag : int;
file : string = nil;	# output file name
bootfile : string = nil;
typ : string = nil;

Sof : con 1;	# start of file
Eof : con 2;	# end of file

stdin, stdout, stderr : ref Sys->FD;

usage()
{
	sys->fprint(stderr, "usage: format [-b bfile] [-c csize] [-df] [-l label] [-t type] file [args ...]\n");
	exit;
}

fatal(str : string)
{
	sys->fprint(stderr, "format : ");
	sys->fprint(stderr, "%s\n", str);
	if(fflag && file != nil)
		sys->remove(file);
	exit;
}

init(nil : ref Draw->Context, argv : list of string)
{
	i, n, dos : int;
	buf, label, a, s : string;
	arg : list of string;
	cfd : ref Sys->FD;

	sys = load Sys Sys->PATH;
	daytime = load Daytime Daytime->PATH;
	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	fflag = 0;
	dos = 0;
	typ = nil;
	clustersize = 0;
	label = "CYLINDRICAL";
	for (arg = tl argv; arg != nil; arg = tl arg) {
		s = hd arg;
		if (s[0] == '-') {
			for (i = 1; i < len s; i++) {
				case s[i] {
					'b' =>
						arg = tl arg;
						if (arg == nil)
							usage();
						bootfile = hd arg;
					'd' =>
						dos = 1;
					'c' =>
						arg = tl arg;
						if (arg == nil)
							usage();
						clustersize = int hd arg;
					'f' =>
						fflag = 1;
					'l' =>
						arg = tl arg;
						if (arg == nil)
							usage();
						label = hd arg;
						if (len label > DB_LABELSIZE)
							label = a[0 : DB_LABELSIZE];
						while (len label < DB_LABELSIZE)
							label = label + " ";
					't' =>
						arg = tl arg;
						if (arg == nil)
							usage();
						typ = hd arg;
					* =>
						usage();
				}
			}
		}
		else
			break;
	}

	if(arg == nil)
		usage();

	dev = hd arg;
	cfd = nil;
	if(fflag == 0){
		n = len dev;
		if(n > 4 && dev[n-4 : ] == "disk")
			dev = dev[0 : n-4];
		else if(n > 3 && dev[n-3 : ] == "ctl")
			dev = dev[0 : n-3];

		buf = dev + "ctl";
		cfd = sys->open(buf, Sys->ORDWR);
		if(cfd == nil)
			fatal(sys->sprint("opening %s: %r", buf));
		sys->print("Formatting floppy %s\n", dev);
		buf = "format";
		if(typ != nil)
			buf = buf + " " + typ;
		if(sys->write(cfd, array of byte buf, len buf) < 0)
			fatal(sys->sprint("formatting tracks: %r"));
	}

	if(dos)
		dosfs(cfd, label, tl arg);
	exit;
}

guessgeometry(sectors: int): (int, int, int)
{
	c := 1024;
	for (i := 0; guess[i].h; i++)
		if (c * guess[i].h * guess[i].s >= sectors)
			return (guess[i].h, guess[i].s, sectors / (guess[i].h * guess[i].s));
	return (255, 63, sectors / (255 * 63));
}

dosfs(cfd : ref Sys->FD, label : string, arg : list of string)
{
	r : string;
	b : array of byte;
	i, n : int;
	length, x, err : int;
	fd, sysfd : ref Sys->FD;
	d : Sys->Dir;

	sys->print("Initialising MS-DOS file system\n");

	if(fflag){
		t = floppytype[0];
		if(typ != nil){
			for (i = 0; i < NTYPES; i++) {
				t = floppytype[i];
				if (t.name == typ)
					break;
			}
			if(i == NTYPES)
				fatal(sys->sprint("unknown disk type %s", typ));
		}
		file = dev;
		if (t.tracks == 0 && t.name == "hard") {
			fd = sys->open(dev, Sys->ORDWR);
			if (fd == nil)
				fatal(sys->sprint("open: %s: %r", file));
			(err, d) = sys->fstat(fd);
			if (err < 0)
				fatal(sys->sprint("fstat: %s: %r", file));
			(t.sectors, t.heads, t.tracks) = guessgeometry(d.length / t.bytes);
		}
		else if ((fd = sys->create(dev, Sys->ORDWR, 8r666)) == nil)
			fatal(sys->sprint("create %s: %r", file));
		length = t.bytes*t.sectors*t.heads*t.tracks;
	}
	else{
		file = dev + "disk";
		fd = sys->open(file, Sys->ORDWR);
		if(fd == nil)
			fatal(sys->sprint("open %s: %r", file));
		(err, d) = sys->fstat(fd);
		if(err < 0)
			fatal(sys->sprint("stat %s: %r", file));
		length = d.length;
	
		t = floppytype[0];
		buf := array[64] of byte;
		sys->seek(cfd, 0, 0);
		n = sys->read(cfd, buf, 64-1);
		if(n < 0)
			fatal("reading floppy type");
		else {
			typ = string buf[0 : n];
			for (i = 0; i < NTYPES; i++) {
				t = floppytype[i];
				if (t.name == typ)
					break;
			}
			if(i == NTYPES)
				fatal(sys->sprint("unknown floppy type %s", typ));
		}
	}
	sys->print("disk type %s, %d tracks, %d heads, %d sectors/track, %d bytes/sec\n",
		t.name, t.tracks, t.heads, t.sectors, t.bytes);

	if(clustersize == 0)
		clustersize = t.cluster;
	clusters = length/(t.bytes*clustersize);
	if(clusters < 4087)
		fatbits = 12;
	else
		fatbits = 16;
	volsecs = length/t.bytes;
	fatsecs = (fatbits*clusters + 8*t.bytes - 1)/(8*t.bytes);
	rootsecs = volsecs/200;
	rootfiles = rootsecs * (t.bytes/DD_SIZE);
	b = array[t.bytes] of byte;
	if(b == nil)
		fatal("out of memory");
	memset(b, 0, t.bytes);

	#
	# write bootstrap & parameter block
	#
	if(bootfile != nil){
		if((sysfd = sys->open(bootfile, Sys->OREAD)) == nil)
			fatal(sys->sprint("open %s: %r", bootfile));
		if(sys->read(sysfd, b, t.bytes) < 0)
			fatal(sys->sprint("read %s: %r", bootfile));
	}
	else
		memmove(b, bootprog, BP_SIZE);
	b[DB_MAGIC+0] = byte 16rEB;
	b[DB_MAGIC+1] = byte 16r3C;
	b[DB_MAGIC+2] = byte 16r90;
	memmove(b[DB_VERSION : ], array of byte "Plan9.00", DB_VERSIONSIZE);
	putshort(b[DB_SECTSIZE : ], t.bytes);
	b[DB_CLUSTSIZE] = byte clustersize;
	putshort(b[DB_NRESRV : ], 1);
	b[DB_NFATS] = byte 2;
	putshort(b[DB_ROOTSIZE : ], rootfiles);
	if(volsecs < (1<<16)){
		putshort(b[DB_VOLSIZE : ], volsecs);
	}
	putlong(b[DB_BIGVOLSIZE : ], volsecs);
	b[DB_MEDIADESC] = byte t.media;
	putshort(b[DB_FATSIZE : ], fatsecs);
	putshort(b[DB_TRKSIZE : ], t.sectors);
	putshort(b[DB_NHEADS : ], t.heads);
	putlong(b[DB_NHIDDEN : ], 0);
	b[DB_DRIVENO] = byte 0;
	b[DB_BOOTSIG] = byte 16r29;
	x = daytime->now();
	putlong(b[DB_VOLID : ], x);
	memmove(b[DB_LABEL : ], array of byte label, DB_LABELSIZE);
	r = sys->sprint("FAT%d    ", fatbits);
	memmove(b[DB_TYPE : ], array of byte r, DB_TYPESIZE);
	b[t.bytes-2] = byte 16r55;
	b[t.bytes-1] = byte 16rAA;
	if(sys->seek(fd, 0, 0) < 0)
		fatal(sys->sprint("seek to boot sector: %r\n"));
	if(sys->write(fd, b, t.bytes) != t.bytes)
		fatal(sys->sprint("writing boot sector: %r"));

	#
	#  allocate an in memory fat
	#
	fat = array[fatsecs*t.bytes] of byte;
	if(fat == nil)
		fatal("out of memory");
	memset(fat, 0, fatsecs*t.bytes);
	fat[0] = byte t.media;
	fat[1] = byte 16rff;
	fat[2] = byte 16rff;
	if(fatbits == 16)
		fat[3] = byte 16rff;
	fatlast = 1;
	if (sys->seek(fd, 2*fatsecs*t.bytes, 1) < 0)
		fatal(sys->sprint("seek to 2 fats: %r"));	# 2 fats

	#
	#  allocate an in memory root
	#
	root = array[rootsecs*t.bytes] of byte;
	if(root == nil)
		fatal("out of memory");
	memset(root, 0, rootsecs*t.bytes);
	if (sys->seek(fd, rootsecs*t.bytes, 1) < 0)
		fatal(sys->sprint("seek to root: %r"));		# rootsecs

	#
	# Now positioned at the Files Area.
	# If we have any arguments, process 
	# them and write out.
	#
	for(i = 0; arg != nil; arg = tl arg){
		if(i >= rootsecs*t.bytes)
			fatal("too many files in root");
		#
		# Open the file and get its length.
		#
		if((sysfd = sys->open(hd arg, Sys->OREAD)) == nil)
			fatal(sys->sprint("open %s: %r", hd arg));
		(err, d) = sys->fstat(sysfd);
		if(err < 0)
			fatal(sys->sprint("stat %s: %r", hd arg));
		sys->print("Adding file %s, length %d\n", hd arg, d.length);

		length = d.length;
		if(length){
			#
			# Allocate a buffer to read the entire file into.
			# This must be rounded up to a cluster boundary.
			#
			# Read the file and write it out to the Files Area.
			#
			length += t.bytes*clustersize - 1;
			length /= t.bytes*clustersize;
			length *= t.bytes*clustersize;
			if((b = array[length] of byte) == nil)
				fatal("out of memory");
	
			if(sys->read(sysfd, b, d.length) < 0)
				fatal(sys->sprint("read %s: %r", hd arg));
			memset(b[d.length : ], 0, length-d.length);
			if (sys->write(fd, b, length) != length)
				fatal(sys->sprint("write %s: %r", hd arg));

			#
			# Allocate the FAT clusters.
			# We're assuming here that where we
			# wrote the file is in sync with
			# the cluster allocation.
			# Save the starting cluster.
			#
			length /= t.bytes*clustersize;
			x = clustalloc(Sof);
			for(n = 0; n < length-1; n++)
				clustalloc(0);
			clustalloc(Eof);
		}
		else
			x = 0;

		#
		# Add the filename to the root.
		#
		addrname(root[i : ], d, x, hd arg);
		i += DD_SIZE;
	}

	#
	#  write the fats and root
	#
	if (sys->seek(fd, t.bytes, 0) < 0)
		fatal(sys->sprint("seek to fat1: %r"));
	if (sys->write(fd, fat, fatsecs*t.bytes) != fatsecs*t.bytes)
		fatal(sys->sprint("writing fat #1: %r"));
	if (sys->write(fd, fat, fatsecs*t.bytes) != fatsecs*t.bytes)
		fatal(sys->sprint("writing fat #2: %r"));
	if (sys->write(fd, root, rootsecs*t.bytes) != rootsecs*t.bytes)
		fatal(sys->sprint("writing root: %r"));

	if(fflag){
		if (sys->seek(fd, t.bytes*t.sectors*t.heads*t.tracks-1, 0) < 0)
			;
		if (sys->write(fd, array of byte "9", 1) != 1)
			;
	}
}

#
#  allocate a cluster
#
clustalloc(flag : int) : int
{
	o, x : int;

	if(flag != Sof){
		if (flag == Eof)
			x =16rffff;
		else
			x = (fatlast+1);
		if(fatbits == 12){
			x &= 16rfff;
			o = (3*fatlast)/2;
			if(fatlast & 1){
				fat[o] = byte (((int fat[o])&16r0f) | (x<<4));
				fat[o+1] = byte (x>>4);
			} else {
				fat[o] = byte x;
				fat[o+1] = byte (((int fat[o+1])&16rf0) | ((x>>8) & 16r0F));
			}
		} else {
			o = 2*fatlast;
			fat[o] = byte x;
			fat[o+1] = byte (x>>8);
		}
	}
		
	if(flag == Eof)
		return 0;
	else
		return ++fatlast;
}

putname(p : string, buf : array of byte)
{
	i, j : int;

	j = -1;
	for (i = 0; i < len p; i++) {
		if (p[i] == '/' || p[i] == '\\')
			j = i;
	}
	p = p[j+1 : ];
	memset(buf[DD_NAME : ], ' ', DD_NAMESIZE+DD_EXTSIZE);
	for(i = 0; i < DD_NAMESIZE && i < len p; i++){
		if(p[i] == '.')
			break;
		if (p[i] >= 'a' && p[i] <= 'z')
			p[i] += 'A'-'a';
		buf[DD_NAME+i] = byte p[i];
	}
	for (i = 0; i < len p; i++) {
		if (p[i] == '.')
			break;
	}
	if(p[i] == '.'){
		p = p[i+1 : ];
		for(i = 0; i < DD_EXTSIZE && i < len p; i++) {
			if (p[i] >= 'a' && p[i] <= 'z')
				p[i] += 'A'-'a';
			buf[DD_EXT+i] = byte p[i];
		}
	}
}

puttime(buf : array of byte)
{
	t : ref Daytime->Tm = getlocaltime();
	x : int;

	x = (t.hour<<11) | (t.min<<5) | (t.sec>>1);
	buf[DD_TIME+0] = byte x;
	buf[DD_TIME+1] = byte (x>>8);
	x = ((t.year-80)<<9) | ((t.mon+1)<<5) | t.mday;
	buf[DD_DATE+0] = byte x;
	buf[DD_DATE+1] = byte (x>>8);
}

addrname(buf : array of byte, dir : Sys->Dir, start : int, nm : string)
{
	putname(nm, buf);
	buf[DD_ATTR] = byte DRONLY;
	puttime(buf);
	buf[DD_START+0] = byte start;
	buf[DD_START+1] = byte (start>>8);
	buf[DD_LENGTH+0] = byte dir.length;
	buf[DD_LENGTH+1] = byte (dir.length>>8);
	buf[DD_LENGTH+2] = byte (dir.length>>16);
	buf[DD_LENGTH+3] = byte (dir.length>>24);
}

getlocaltime() : ref Daytime->Tm
{
	return daytime->local(daytime->now());
}

memset(d : array of byte, v : int, n : int)
{
	for (i := 0; i < n; i++)
		d[i] = byte v;
}

memmove(d : array of byte, s : array of byte, n : int)
{
	for (i := 0; i < n; i++) 
		d[i] = s[i];
}

putshort(b : array of byte, v : int)
{
	b[1] = byte (v>>8);
	b[0] = byte v;
}

putlong(b : array of byte, v : int)
{
	putshort(b, v);
	putshort(b[2 : ], v>>16);
}
