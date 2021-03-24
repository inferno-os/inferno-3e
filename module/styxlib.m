Styxlib: module
{
	PATH: con "/dis/lib/styxlib.dis";
	Chan: adt {
		fid: int;
		qid: Sys->Qid;
		open: int;
		mode: int;
		uname: string;
		path: string;
		data: array of byte;

		isdir: fn(c: self ref Chan): int;
	};

	Dirtab: adt {
		name: string;
		qid: Sys->Qid;
		length: big;
		perm: int;
	};

	Styxserver: adt {
		fd: ref Sys->FD;
		chans: array of list of ref Chan;
		uname: string;

		new: fn(fd: ref Sys->FD): (chan of ref Tmsg, ref Styxserver);
		reply: fn(srv: self ref Styxserver, m: ref Rmsg): int;

		fidtochan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		newchan: fn(srv: self ref Styxserver, fid: int): ref Chan;
		chanfree: fn(srv: self ref Styxserver, c: ref Chan);
		chanlist: fn(srv: self ref Styxserver): list of ref Chan;

		devattach: fn(srv: self ref Styxserver, m: ref Tmsg.Attach): ref Chan;
		devclone: fn(srv: self ref Styxserver, m: ref Tmsg.Clone): ref Chan;
		devflush: fn(srv: self ref Styxserver, m: ref Tmsg.Flush);
		devwalk: fn(srv: self ref Styxserver, m: ref Tmsg.Walk,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan;
		devclunk: fn(srv: self ref Styxserver, m: ref Tmsg.Clunk): ref Chan;
		devstat: fn(srv: self ref Styxserver, m: ref Tmsg.Stat,
							gen: Dirgenmod, tab: array of Dirtab);
		devdirread: fn(srv: self ref Styxserver, m: ref Tmsg.Read,
							gen: Dirgenmod, tab: array of Dirtab);
		devopen: fn(srv: self ref Styxserver, m: ref Tmsg.Open,
							gen: Dirgenmod, tab: array of Dirtab): ref Chan;
		devremove: fn(srv: self ref Styxserver, m: ref Tmsg.Remove): ref Chan;
	};

	readbytes: fn(m: ref Tmsg.Read, d: array of byte): ref Rmsg.Read;
	readnum: fn(m: ref Tmsg.Read, val, size: int): ref Rmsg.Read;
	readstr: fn(m: ref Tmsg.Read, d: string): ref Rmsg.Read;

	openok: fn(omode, perm: int, uname, funame, fgname: string): int;
	openmode: fn(o: int): int;
	
	devdir: fn(c: ref Chan, qid: Sys->Qid, n: string, length: big,
				user: string, perm: int): Sys->Dir;

	dirgenmodule: fn(): Dirgenmod;
	dirgen: fn(srv: ref Styxserver, c: ref Chan, tab: array of Dirtab, i: int): (int, Sys->Dir);
	d2tmsg: fn(d: array of byte): (int, ref Tmsg);
	d2rmsg: fn(d: array of byte): (int, ref Rmsg);
	rmsg2d: fn(m: ref Rmsg, d: array of byte): int;
	tmsg2s: fn(m: ref Tmsg): string;				# for debugging
	rmsg2s: fn(m: ref Rmsg): string;				# for debugging
	convD2M: fn(d: array of byte, f: Sys->Dir): array of byte;
	convM2D: fn(d: array of byte): (array of byte, Sys->Dir);

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
	};

	Rmsg: adt {
		tag: int;
		pick {
		Nop or
		Flush =>
		Error =>
			err: string;
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
	};
	MAXRPC: con 128 + Sys->ATOMICIO;
	DIRLEN: con 116;
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
	Tsession,		# 26
	Rsession,		# 27
	Tattach,		# 28 
	Rattach,		# 29
	Tmax		: con iota;

	Einuse		: con "fid already in use";
	Ebadfid		: con "bad fid";
	Eopen		: con "fid already opened";
	Enotfound	: con "file does not exist";
	Enotdir		: con "not a directory";
	Eperm		: con "permission denied";
	Ebadarg		: con "bad argument";
	Eexists		: con "file already exists";
};


Dirgenmod: module {
	dirgen: fn(srv: ref Styxlib->Styxserver, c: ref Styxlib->Chan,
			tab: array of Styxlib->Dirtab, i: int): (int, Sys->Dir);
};
