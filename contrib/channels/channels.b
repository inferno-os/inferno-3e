implement Channels;

# Use a channel to pass an adt reference
# Adds up all the numbers from 1 to 100

include "sys.m";
include "draw.m";

Channels: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Datastruct: adt {
	val: int;
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	# set up the pipeline
	a := chan of ref Datastruct;
	b := chan of ref Datastruct;
	first := a;
	for (i := 0; i < 100; i++) {
		spawn proc(i, a, b);
		(a, b) = (b, chan of ref Datastruct);
	}
	last := a;
	# push data structure in at the start
	first <-= ref Datastruct(0);
	# remove it from the end
	result := <-last;
	sys->print("%d\n", result.val);
}
proc(i: int, a, b: chan of ref Datastruct)
{
	d := <-a;
	# compute; leave result in data structure.
	d.val += i;
	b <-= d;
}

