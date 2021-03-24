Viewman : module {
	# metrics
	textwidth : fn (text : Parseman->Text) : int;
};

Parseman : module {
	PATH : con "/dis/lib/parseman.dis";

	Metrics : adt {
		pagew : int;
		dpi : int;
		em : int;	# size in dots
		en : int;	# size in dots
		V : int;	# font height in dots
		indent : int;
		ssindent : int;
	};

	Text : adt {
		font : int;
		attr : int;
		text : string;
		heading : int;	# heading level
		link : string;
	};

	# Text fonts and attributes
	FONT_ROMAN,
	FONT_ITALIC,
	FONT_BOLD : con iota;
	ATTR_SMALL, ATTR_LAST : con 1 << iota;

	init : fn () : string;
	parseman : fn (fd : ref Sys->FD, metrics : Metrics, ql : int, viewer : Viewman, setline : chan of list of (int, Text));
};
