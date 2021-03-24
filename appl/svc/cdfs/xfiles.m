Xfiles: module
{
	ISOPATH:	con "/dis/svc/cdfs/iso9660.dis";	# 9660

	Xfs: adt {
		d:	ref Iobuf->Device;
		inuse:	int;
		issusp:	int;	# system use sharing protocol in use?
		suspoff:	int;	# LEN_SKP, if so
		isplan9:	int;	# has Plan 9-specific directory info
		isrock:	int;	# is rock ridge
		rootqid:	Sys->Qid;
		ptr:	int;	# tag for private data

		new:	fn(nil: ref Iobuf->Device): ref Xfs;
		incref:	fn(nil: self ref Xfs);
		decref:	fn(nil: self ref Xfs);
	};

	Xfile:	adt {
		xf:	ref Xfs;
		flags:	int;
		qid:	Sys->Qid;
		ptr:	int;	# tag for private data

		new:		fn(): ref Xfile;
		clean:	fn(nil: self ref Xfile): ref Xfile;

		attach:	fn(nil: self ref Xfile): string;
		clone:	fn(nil: self ref Xfile, nil: ref Xfile);
		walkup:	fn(nil: self ref Xfile): string;
		walk:	fn(nil: self ref Xfile, nil: string): string;
		open:	fn(nil: self ref Xfile, nil: int): string;
		create:	fn(nil: self ref Xfile, nil: string, nil: int, nil: int): string;
		readdir:	fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
		read:		fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
		write:	fn(nil: self ref Xfile, nil: array of byte, nil: int, nil: int): (int, string);
		clunk:	fn(nil: self ref Xfile);
		remove:	fn(nil: self ref Xfile): string;
		stat:		fn(nil: self ref Xfile): (ref Sys->Dir, string);
		wstat:	fn(nil: self ref Xfile, nil: ref Sys->Dir): string;
	};

	Oread, Owrite, Orclose: con 1<<iota;
	Omodes: con 3;	# mask

	init:	fn(nil: Iobuf, nil: Styx);
};
