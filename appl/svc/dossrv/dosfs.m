Dosfs : module {

	PATH : con "/dis/svc/dossrv/dosfs.dis";

	init : fn(s : string, l: string,i : int, trksize: int): string;
	setup : fn();	
	dossrv : fn(fd :ref Sys->FD);
	rnop : fn(nil: ref Styx->Tmsg.Nop): ref Styx->Rmsg;
	rflush : fn(nil: ref Styx->Tmsg.Flush): ref Styx->Rmsg;
	rattach : fn(nil: ref Styx->Tmsg.Attach): ref Styx->Rmsg;
	rclone : fn(nil: ref Styx->Tmsg.Clone): ref Styx->Rmsg;
	rwalk : fn(nil: ref Styx->Tmsg.Walk): ref Styx->Rmsg;
	ropen : fn(nil: ref Styx->Tmsg.Open): ref Styx->Rmsg;
	rcreate : fn(nil: ref Styx->Tmsg.Create): ref Styx->Rmsg;
	rread : fn(nil: ref Styx->Tmsg.Read): ref Styx->Rmsg;
	rwrite : fn(nil: ref Styx->Tmsg.Write): ref Styx->Rmsg;
	rclunk : fn(nil: ref Styx->Tmsg.Clunk): ref Styx->Rmsg;
	rremove : fn(nil: ref Styx->Tmsg.Remove): ref Styx->Rmsg;
	rstat : fn(nil: ref Styx->Tmsg.Stat): ref Styx->Rmsg;
	rwstat : fn(nil: ref Styx->Tmsg.Wstat): ref Styx->Rmsg;
};
