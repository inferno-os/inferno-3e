SimpleFS: module {
	Qidpath: type Styxservers->Qidpath;
	PATH: con "/dis/lib/simplefs.dis";
	Fs: adt {
		c:		chan of ref Fsop;
		reply:	chan of string;

		quit:		fn(t: self ref Fs);
		create:	fn(t: self ref Fs, parentq: Qidpath, d: Sys->Dir): string;
		remove:	fn(t: self ref Fs, q: Qidpath): string;
	};
	Fsop: adt {
		reply: chan of string;
		q: Qidpath;
		pick {
		Create or
		Wstat =>
			d: Sys->Dir;
		Remove =>
		}
	};
	init:		fn();
	start:		fn(): (ref Fs, chan of ref Styxservers->Treeop);
};
