Styx: module
{
	PATH:	con "/dis/lib/styx.dis";

	MAXFDATA: con 8192;
	MAXMSG:	con 128;	# max header sans data
	MAXRPC:	con MAXMSG+MAXFDATA;

	DIRLEN:	con 116;

	NOTAG:	con 16rFFFF;
	NOFID:	con 16rFFFF;	# 16 bits in this version of Styx

	STATFIXLEN:	con 116;	# amount of fixed length data in a stat buffer
	IOHDRSZ:	con MAXMSG;	# 9P2000 name

	Tnop,		#  0
	Rnop,		#  1
	Terror,		#  2, illegal
	Rerror,		#  3
	Tflush,		#  4
	Rflush,		#  5
	Tclone,		#  6
	Rclone,		#  7
	Twalk,		#  8
	Rwalk,		#  9
	Topen,		# 10
	Ropen,		# 11
	Tcreate,		# 12
	Rcreate,		# 13
	Tread,		# 14
	Rread,		# 15
	Twrite,		# 16
	Rwrite,		# 17
	Tclunk,		# 18
	Rclunk,		# 19
	Tremove,		# 20
	Rremove,		# 21
	Tstat,		# 22
	Rstat,		# 23
	Twstat,		# 24
	Rwstat,		# 25
	Tsession,		# 26		# unimplemented
	Rsession,		# 27		# unimplemented
	Tattach,		# 28
	Rattach,		# 29
	Tmax		: con iota;
	
	NAMELEN:	con 28;
	ERRLEN:	con 64;
	
	OREAD:	con 0; 		# open for read
	OWRITE:	con 1; 		# write
	ORDWR:	con 2; 		# read and write
	OEXEC:	con 3; 		# execute, == read but check execute permission
	OTRUNC:	con 16; 		# or'ed in (except for exec), truncate file first
	ORCLOSE: con 64; 		# or'ed in, remove on close

	# older names for mode bits, used by original version of Styx
	CHDIR:	con int 16r80000000;	# mode bit for directory
	CHAPPEND:	con 16r40000000;	# mode bit for append-only files
	CHEXCL:	con 16r20000000;	# mode bit for exclusive use files 	

	# mode bits in Dir.mode used by the protocol
	DMDIR:		con int 1<<31;		# mode bit for directory
	DMAPPEND:	con int 1<<30;		# mode bit for append-only files
	DMEXCL:		con int 1<<29;		# mode bit for exclusive use files
	DMAUTH:		con int 1<<27;		# mode bit for authentication files

	Tmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Nop =>
		Flush =>
			oldtag: int;
		Clone =>
			fid, newfid: int;
		Walk =>
			fid: int;
			name: string;
		Open =>
			fid, mode: int;
		Create =>
			fid, perm, mode: int;
			name: string;
		Read =>
			fid, count: int;
			offset: big;
		Write =>
			fid: int;
			offset: big;
			data: array of byte;
		Clunk or
		Stat or
		Remove => 
			fid: int;
		Wstat =>
			fid: int;
			stat: Sys->Dir;
		Attach =>
			fid: int;
			uname, aname: string;
		}

		read:	fn(fd: ref Sys->FD, msglim: int): ref Tmsg;
		unpack:	fn(a: array of byte): (int, ref Tmsg);
		pack:	fn(nil: self ref Tmsg): array of byte;
		packedsize:	fn(nil: self ref Tmsg): int;
		text:	fn(nil: self ref Tmsg): string;
	};

	Rmsg: adt {
		tag: int;
		pick {
		Readerror =>
			error: string;		# tag is unused in this case
		Nop or
		Flush =>
		Error =>
			ename: string;
		Clunk or
		Remove or
		Clone or
		Wstat =>
			fid: int;
		Walk or
		Create or
		Open or
		Attach =>
			fid: int;
			qid: Sys->Qid;
		Read =>
			fid: int;
			data: array of byte;
		Write =>
			fid, count: int;
		Stat =>
			fid: int;
			stat: Sys->Dir;
		}

		read:	fn(fd: ref Sys->FD, msglim: int): ref Rmsg;
		unpack:	fn(a: array of byte): (int, ref Rmsg);
		pack:	fn(nil: self ref Rmsg): array of byte;
		packedsize:	fn(nil: self ref Rmsg): int;
		text:	fn(nil: self ref Rmsg): string;
	};

	init:	fn();

	readmsg:	fn(fd: ref Sys->FD, msglim: int): (array of byte, string);
	istmsg:	fn(f: array of byte): int;

	packdirsize:	fn(d: Sys->Dir): int;
	packdir:	fn(d: Sys->Dir): array of byte;
	unpackdir: fn(f: array of byte): (int, Sys->Dir);
	dir2text:	fn(d: Sys->Dir): string;
	qid2text:	fn(q: Sys->Qid): string;

	# temporary undocumented function for old/new Styx compatibility
	write:	fn(fd: ref Sys->FD, b: array of byte, n: int): int;
};
