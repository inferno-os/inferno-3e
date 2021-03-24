implement Server;
include "sys.m";
include "draw.m";

# a very simple demo file server.
# it serves a single append-only file, storing the contents
# of the file in a string.

Server: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys := load Sys Sys->PATH;

	# make sure that the file2chan device (#s)
	# is in place.
	sys->bind("#s", "/chan", Sys->MBEFORE);

	# create the file to serve, named "/chan/srvfile"
	fio := sys->file2chan("/chan", "srvfile");

	contents := "";

	# infinite loop, serving the file.
	for (;;) alt {
	(offset, data, fid, wc) := <-fio.write =>
		# got a write request. ignore EOF (wc == nil)
		# append data written to contents.
		if (wc != nil) {
			contents += string data;

			# reply to the write request
			wc <-= (len data, nil);
		}
	(offset, count, fid, rc) := <-fio.read =>
		# got a read request. ignore EOF (rc == nil).
		# return appropriate section of contents.
		if (rc != nil) {
			d := array of byte contents;
			if (offset > len d)
				offset = len d;
			if (offset + count > len d)
				count = len d - offset;

			# reply to the read request with requested data.
			rc <-= (d[offset:offset + count], nil);
		}
	}
}
