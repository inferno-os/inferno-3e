Man : module {
	PATH : con "/dis/man.dis";

	init : fn (ctxt : ref Draw->Context, argv : list of string);

	# Man module declarations
	#
	loadsections : fn (sections : list of string) : string;
	getfiles : fn (sections : list of string , keys : list of string) : list of (int, string, string);
};
