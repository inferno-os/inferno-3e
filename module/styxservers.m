Styxservers: module
{
	PATH: con "/dis/lib/styxservers.dis";
	Qidpath: type int;
	Chan: adt {
		fid: int;
		qid: Qidpath;
		open: int;
		mode: int;
		uname: string;
		param: string;
		data: array of byte;

		isdir: fn(c: self ref Chan): int;
	};


	Filetree: adt {
		c:		chan of ref Treeop;
		reply:	chan of (ref Sys->Dir, string);

		new:		fn(c: chan of ref Treeop): ref Filetree;
		find:		fn(t: self ref Filetree, q: Qidpath): (ref Sys->Dir, string);
		walk:	fn(t: self ref Filetree, parentq: Qidpath, name: string): (ref Sys->Dir, string);
		readdir:	fn(t: self ref Filetree, q: Qidpath, offset, count: int): array of byte;
	};

	Treeop: adt {
		reply:	chan of (ref Sys->Dir, string);
		q:		Qidpath;
		pick {
		Find =>
		Walk =>
			name: string;
		Readdir =>
			offset:	int;
			count: 	int;
		}
	};

	Styxserver: adt {
		fd:		ref Sys->FD;
		chans:	array of list of ref Chan;
		t:		ref Filetree;
		rootqid:	Qidpath;

		new:			fn(fd: ref Sys->FD, t: ref Filetree, rootqid:	Qidpath): (chan of ref Styx->Tmsg, ref Styxserver);
		reply:		fn(srv: self ref Styxserver, m: ref Styx->Rmsg): int;

		fidtochan:		fn(srv: self ref Styxserver, fid: int): ref Chan;
		newchan:		fn(srv: self ref Styxserver, fid: int): ref Chan;
		chanfree:		fn(srv: self ref Styxserver, c: ref Chan);
		chanlist:		fn(srv: self ref Styxserver): list of ref Chan;

		attach:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Attach): ref Chan;
		clone:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Clone): ref Chan;
		clunk:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Clunk): ref Chan;

		walk:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Walk): ref Chan;
		open:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Open): ref Chan;
		read:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Read): ref Chan;
		remove:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Remove): ref Chan;
		stat:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Stat);

		default:	fn(srv: self ref Styxserver, gm: ref Styx->Tmsg);

		# check permissions but don't reply.
		# XXX better names desired!
#		canopen:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Open): (ref Chan, string);
#		canremove:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Remove): (ref Chan, Qidpath, string);
		cancreate:	fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Create): (ref Chan, int, string);
		canwrite:		fn(srv: self ref Styxserver, m: ref Styx->Tmsg.Write): (ref Chan, string);
	};

	readbytes: fn(m: ref Styx->Tmsg.Read, d: array of byte): ref Styx->Rmsg.Read;

	openok: fn(uname: string, omode, perm: int, funame, fgname: string): int;
	openmode: fn(o: int): int;
	init: fn();
	
	Einuse		: con "fid already in use";
	Ebadfid		: con "bad fid";
	Eopen		: con "fid already opened";
	Enotfound	: con "file does not exist";
	Enotdir		: con "not a directory";
	Eperm		: con "permission denied";
	Ebadarg		: con "bad argument";
	Eexists		: con "file already exists";
};
