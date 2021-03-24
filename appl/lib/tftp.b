implement Tftp;

include "sys.m";
	sys: Sys;

include "tftp.m";

debug: int;
progress: int;

nboputs(buf: array of byte, val: int)
{
	buf[0] = byte (val >> 8);
	buf[1] = byte val;
}

nbogets(buf: array of byte): int
{
	return (int buf[0] << 8) | int buf[1];
}

kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd == nil)
		return;

	msg := array of byte "kill";
        sys->write(fd, msg, len msg);
}

timeoutproc(pid: chan of int, howlong: int, c: chan of string)
{
	pid <-= sys->pctl(0, nil);

	sys->sleep(howlong);

	# send timeout
	c <-= "timed out";
}

tpid := -1;
tc: chan of string;

timeoutcancel()
{
	if (tpid >= 0) {
		kill(tpid);
		tpid = -1;
	}
}

timeoutstart(howlong: int): (chan of string)
{
	timeoutcancel();
	pidc := chan of int;
	tc = chan of string;
	spawn timeoutproc(pidc, howlong, tc);
	tpid = <- pidc;
	return tc;
}

init(p: int, dbg: int)
{
	sys = load Sys Sys->PATH;
	progress = p;
	debug = dbg;
}

listen(pidc: chan of int, fd: ref Sys->FD, bc: chan of array of byte)
{
	pid := sys->pctl(0, nil);
	pidc <-= pid;
	buf := array [512 + 4] of byte;
	while (1) {
		n := sys->read(fd, buf, len buf);
		bc <-= buf[0 : n];
	}
}

receive(host: string, filename: string, fd: ref Sys->FD): (int, string)
{
	rbuf: array of byte;
	
	(ok, conn) := sys->dial("udp!" + host + "!69", nil);
	if (!ok) 
		return (0, sys->sprint("dial: %r"));
	buf := array [512 + 4] of byte;
	i := 0;
	nboputs(buf[i : i + 2], 1);		# rrq
	i += 2;
	flen := len array of byte filename;
	buf[i :] = array of byte filename;
	i += flen;
	buf[i++] = byte 0;
	mode := "binary";
	mlen := len array of byte mode;
	buf[i:] = array of byte mode;
	i += mlen;
	buf[i++] = byte 0;
	pidc := chan of int;
	bc := chan of array of byte;
	spawn listen(pidc, conn.dfd, bc);
	tftppid := <- pidc;
	lastblock := 0;
	for (;;) {
		done := 0;
		for (count := 0; !done && count < 5; count++) {
			# send packet
	
			if (sys->write(conn.dfd, buf, i) < 0) {
				kill(tftppid);
				return (0, sys->sprint( "%s/data: %r", conn.dir));
			}
	
			# wait for next block
	
			mtc := timeoutstart(3000);
			timedout := 0;
			do {
				alt {
				<- mtc =>
					if (progress)
						sys->print("T");
					timedout = 1;
				rbuf = <- bc =>
					op := nbogets(rbuf[0 : 2]);
					case op {
					3 =>
						block := nbogets(rbuf[2 : 4]);
						if (block == lastblock + 1) {
							timeoutcancel();
							done = 1;
						}
						else if (progress)
							sys->print("S");
					5 =>
						timeoutcancel();
						
						kill(tftppid);
						return (0, sys->sprint("server error %d: %s", nbogets(rbuf[2 : 4]), string rbuf[4 :]));
					* =>
						timeoutcancel();
						
						kill(tftppid);
						return (0, sys->sprint("phase error %d", op));
					}
				}
			} while (!done && !timedout);
		}
		if (!done) {
			kill(tftppid);
			return (0, sys->sprint("tftp timeout"));
;
		}
		n := len rbuf;
	# copy the data somewhere
		if (sys->write(fd, rbuf[4 :], n - 4) < 0) {
			kill(tftppid);
			return (0, sys->sprint("writing destination: %r"));
		}
		lastblock++;
		if (progress && lastblock % 25 == 0)
			sys->print(".");
		if (n < 512 + 4) {
			if (progress)
				sys->print("\n");
			break;
		}
	# send an ack
		nboputs(buf[0 : 2], 4);		# ack
		nboputs(buf[2 : 4], lastblock);
	}
	kill(tftppid);
	return (1, nil);
}


