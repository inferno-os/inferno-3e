implement Man2txt;

include "draw.m";
include "sys.m";
include "bufio.m";
include "parseman.m";

Man2txt : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);

	# Viewman signature...
	textwidth : fn (text : Parseman->Text) : int;

};

sys : Sys;
bufio : Bufio;
Iobuf : import bufio;
output : ref Iobuf;

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->print("cannot load Bufio module: %r\n");
		sys->raise("fail:init");
	}

	stdout := sys->fildes(1);
	output = bufio->fopen(stdout, Sys->OWRITE);

	parser := load Parseman Parseman->PATH;
	parser->init();

	argv = tl argv;
	for (; argv != nil ; argv = tl argv) {
		fname := hd argv;
		fd := sys->open(fname, Sys->OREAD);
		if (fd == nil) {
			sys->print("cannot open %s: %r\n", fname);
			continue;
		}
		vm := load Viewman SELF;
		m := Parseman->Metrics(65, 1, 1, 1, 1, 5, 2);
		
		datachan := chan of list of (int, Parseman->Text);
		spawn parser->parseman(fd, m, 1, vm, datachan);
		for (;;) {
			line := <- datachan;
			if (line == nil)
				break;
			setline(line);
		}
		output.flush();
	}
	output.close();
}

textwidth(text : Parseman->Text) : int
{
	return len text.text;
}


setline(line : list of (int, Parseman->Text))
{
#return;
	offset := 0;
	for (; line != nil; line = tl line) {
		(indent, txt) := hd line;
		while (offset < indent) {
			output.putc(' ');
			offset++;
		}
		output.puts(txt.text);
		offset += len txt.text;
	}
	output.putc('\n');
}
