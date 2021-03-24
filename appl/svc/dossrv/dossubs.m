DosSubs: module
{
	
	PATH: 	con "/dis/svc/dossrv/dossubs.dis";
	
	Global: adt {
		deffile: string;
		logfile: string;
		chatty: int;
		iotrack: IoTrack;
		dos: DosSubs;
		styx: Styx;
	};

	Dospart: adt {
		active: byte;
		hstart: byte;
		cylstart: array of byte;
		typ: byte;
		hend: byte;
		cylend: array of byte;
		start: array of byte;
		length: array of byte;
	};
	
	Dosboot: adt {
		arr2Db:	fn(arr: array of byte): ref Dosboot;
		magic:	array of byte;
		version:	array of byte;
		sectsize:	array of byte;
		clustsize:	byte;
		nresrv:	array of byte;
		nfats:	byte;
		rootsize:	array of byte;
		volsize:	array of byte;
		mediadesc:	byte;
		fatsize:	array of byte;
		trksize:	array of byte;
		nheads:	array of byte;
		nhidden:	array of byte;
		bigvolsize:	array of byte;
		driveno:	byte;
		bootsig:	byte;
		volid:	array of byte;
		label:	array of byte;
	};
	
	Dosbpb: adt {
		sectsize: int;	# in bytes 
		clustsize: int;	# in sectors 
		nresrv: int;	# sectors 
		nfats: int;	# usually 2 
		rootsize: int;	# number of entries 
		volsize: int;	# in sectors 
		mediadesc: int;
		fatsize: int;	# in sectors 
		fatclusters: int;
		fatbits: int;	# 12 or 16 
		fataddr: int; #big;	# sector number 
		rootaddr: int; #big;
		dataaddr: int; #big;
		freeptr: int; #big;	# next free cluster candidate 
	};
	
	Dosdir: adt {
		Dd2arr:	fn(d: ref Dosdir): array of byte;
		arr2Dd:	fn(arr: array of byte): ref Dosdir;
		name:	string;
		ext:		string;
		attr:		byte;
		reserved:	array of byte;
		time:		array of byte;
		date:		array of byte;
		start:		array of byte;
		length:	array of byte;
	};
	
	Dosptr: adt {
		addr:	int;	# of file's directory entry 
		offset:	int;
		paddr:	int;	# of parent's directory entry 
		poffset:	int;
		iclust:	int;	# ordinal within file 
		clust:	int;
		prevaddr:	int;
		naddr:	int;
		p:	ref IoTrack->Iosect;
		d:	ref Dosdir;
	};
	
	Asis, Clean, Clunk: con iota;
	
	FAT12: con byte 16r01;
	FAT16: con byte 16r04;
	FATHUGE: con byte 16r06;
	DMDDO: con 16r54;
	DRONLY: con 16r01;
	DHIDDEN: con 16r02;
	DSYSTEM: con 16r04;
	DVLABEL: con 16r08;
	DDIR: con 16r10;
	DARCH: con 16r20;
	DLONG: con DRONLY | DHIDDEN | DSYSTEM | DVLABEL;
	DMLONG: con DLONG | DDIR | DARCH;

	DOSDIRSIZE: con 32;
	DOSEMPTY: con 16rE5;
	DOSRUNES: con 13;

	FATRESRV: con 2;

	Oread: con  1;
	Owrite: con  2;
	Orclose: con  4;
	Omodes: con  3;
	
	VERBOSE, STYX_MESS, FAT_INFO, CLUSTER_INFO: con (1 << iota);

	chat: fn(s: string);
	panic: fn(s: string);
	
	dosfs: fn(xf: ref IoTrack->Xfs): int;
	init: fn(g: ref Global);		
	setup: fn();	
	putfile: fn(f: ref IoTrack->Xfile);

	getdir: fn(a: array of byte, addr,offset: int): ref Sys->Dir;
	putdir: fn(d: ref Dosdir, dp: ref Sys->Dir);
	getfile: fn(f: ref IoTrack->Xfile): int;

	truncfile: fn(f: ref IoTrack->Xfile): int;

	readdir: fn(f: ref IoTrack->Xfile, offset, count: int): (int,array of byte);
	readfile: fn(f: ref IoTrack->Xfile, offset,count: int): (int,array of byte);

	searchdir: fn(f: ref IoTrack->Xfile,name:string,cflag: int,lflag: int):  (int,ref Dosptr);
	walkup: fn(f: ref IoTrack->Xfile): (int , ref Dosptr);

	puttime: fn(d: ref Dosdir);
	putname: fn(p: string, d: ref Dosdir);

	falloc: fn(xf: ref IoTrack->Xfs): int;

	writefile: fn(f: ref IoTrack->Xfile, a: array of byte, offset,count: int): int;

	emptydir: fn(f: ref IoTrack->Xfile): int;

	name2de: fn(s: string): int;
	dosname:	fn(s: string): (string, string);
	long2short: fn(s: string,i: int): string;
	putlongname:	fn(xf: ref IoTrack->Xfs, dp: ref Dosptr, name: string, sname: string): int;
	getnamesect: fn(arr: array of byte): string;
	aliassum: fn(s: string): int;
	QIDPATH:	fn(dp: ref Dosptr): int;
};
