implement Converts;

# Conversion server
# Serves a single file and calls a convertor module
# Uses file2chan and keeps track of FIDs for multiplexed requests

include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;

include "converter_tmpl.m";
	conv: Converter;


Converts: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};


Reply: adt {
	fid: int;
	text: string;
};

replist: list of Reply;


# Save a reply for when user reads the file back

save(fid: int, text: string)
{
	replist = Reply(fid, text) :: replist;

}


# Retrieve a reply for the user and delete the saved entry

retrieve(fid: int) : string
{
	result := "";
	mylist := replist;
	newlist : list of Reply;
	while (mylist != nil) {
		rep := hd mylist;
		if (rep.fid == fid) result = rep.text;
		else newlist = rep :: newlist;
		mylist = tl mylist;
	}
	replist = newlist;
	return result;
}


# Main program

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;

	if (len argv < 3) Usage();
	args := argv;
	args = tl args;
	spath := hd args;
	args = tl args;
	modpath := hd args;
	conv = load Converter modpath;
	if (conv == nil) {
		sys->print("Failed to load converter from %s\n", modpath);
		exit;
	}
	conv->init();

	(sdir, sfile) := str->splitstrr(spath, "/");
	sdir = sdir[:len sdir-1];

	# make sure that the file2chan device (#s)
	# is in place.
	sys->bind("#s", sdir, Sys->MBEFORE);

	fio := sys->file2chan(sdir, sfile);
	if (fio == nil) {
		sys->print("file2chan failed: %r\n");
		exit;
	}

	# Spawn process to serve the file
	spawn serveloop(fio);
}

serveloop(fio: ref Sys->FileIO)
{
	# infinite loop, serving the file.
	for (;;) alt {

	(offset, data, fid, wc) := <-fio.write =>
		# got a write request. Ignore offset.
		# Do conversion and remember reply for when user reads back the file
		if (wc != nil) {
			# Ensure we don't have a reply already saved for this user
			retrieve(fid);
			reply := conv->convert(string data);
			save(fid, reply);
			# reply to the write request
			wc <-= (len data, nil);
		} else {
			# User closed file - delete any stored reply.
			retrieve(fid);
		}

	(offset, count, fid, rc) := <-fio.read =>
		# got a read request. Ignore offset.
		# return reply that we prepared earlier

		if (rc != nil) {
			d := array of byte retrieve(fid);
			# reply to the read request with requested data.
			if (count > len d) count = len d;
			rc <-= (d[:count], nil);
		}
	}
}


# Print usage and exit

Usage()
{
	sys->print("Usage: converts path converter_dis\n");
	exit;
}
