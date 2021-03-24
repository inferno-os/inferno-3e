Iobuf: module
{
	PATH: con "/dis/svc/cdfs/iobuf.dis";

	Device: adt {
		inuse:	int;	# attach count
		name:	string;	# of underlying file
		fd:	ref Sys->FD;
		sectorsize:	int;
		qid:	Sys->Qid;	# (qid,dtype,dev) identify uniquely
		dtype:	int;
		dev:	int;

		detach:	fn(nil: self ref Device);
	};

	Block: adt {
		dev:	ref Device;
		addr:	int;
		data:	array of byte;

		# internal
		next:	cyclic ref Block;
		prev:	cyclic ref Block;
		busy:	int;

		get:	fn(nil: ref Device, addr: int): ref Block;
		put:	fn(nil: self ref Block);
	};

	init:	fn(maxbsize: int);
	attach:	fn(name: string, mode: int, sectorsize: int): (ref Device, string);
};
