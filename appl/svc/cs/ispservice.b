implement CSplugin;

#
#	Module:		ispservice
#	Purpose:	Connection Server Plugin For Simple PPP Dial-on-Demand
#	Author:		Eric Van Hensbergen (ericvh@lucent.com)
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
include "lock.m";
	lock: Lock;
	Semaphore: import lock;

include "cfgfile.m";
	cfg:	CfgFile;
	ConfigFile: import cfg;

include "../ppp/modem.m";
include "../ppp/script.m";
include "../ppp/pppclient.m";
	ppp: PPPClient;
include "../ppp/pppgui.m";

include "cs.m";

#
# Globals
# 

	context:		ref Draw->Context;
	modeminfo:		ref Modem->ModemInfo;
	pppinfo:		ref PPPClient->PPPInfo;
	scriptinfo:		ref Script->ScriptInfo;
	isp_number:		string;						# should be part of pppinfo
	# isp_lock:		ref Lock->Semaphore;
	lastCdir:		ref Sys->Dir;	# state of file when last read

#
# Constants (for now)
#

DEFAULT_ISP_DB_PATH:	con "/services/ppp/isp.cfg";	# contains pppinfo & scriptinfo
DEFAULT_MODEM_DB_PATH:	con	"/services/ppp/modem.cfg";			# contains modeminfo
MODEM_DB_PATH:	con	"/usr/inferno/config/modem.cfg";			# contains modeminfo
ISP_DB_PATH:	con "/usr/inferno/config/isp.cfg";		# contains pppinfo & scriptinfo
ISP_RETRIES:	con 5;

getcfgstring(c: ref ConfigFile, key: string) :string
{
	ret : string;

	retlist := c.getcfg(key);
	if (retlist == nil)
		return nil;

	for (; retlist != nil; retlist = tl retlist)
		ret+= (hd retlist) + " ";
	
	return ret[:(len ret-1)];		# trim the trailing space
}

configinit()
{
	mi:	Modem->ModemInfo;
	pppi: PPPClient->PPPInfo;
	info: list of string;

	cfg = load CfgFile CfgFile->PATH;
	if (cfg == nil) {
		raise("fail: load CfgFile");
		return;
	}

	# Modem Configuration
	
	cfg->verify(DEFAULT_MODEM_DB_PATH, MODEM_DB_PATH);
	modemcfg := cfg->init(MODEM_DB_PATH);
	if (modemcfg == nil) {
		raise("fail: read: "+MODEM_DB_PATH);
		return;
	}
	modeminfo = ref mi;

	modeminfo.path = getcfgstring(modemcfg, "PATH");
	modeminfo.init = getcfgstring(modemcfg, "INIT");
	modeminfo.country = getcfgstring(modemcfg, "COUNTRY");
	modeminfo.other = getcfgstring(modemcfg, "OTHER");
	modeminfo.errorcorrection = getcfgstring(modemcfg,"CORRECT");
	modeminfo.compression = getcfgstring(modemcfg,"COMPRESS");
	modeminfo.flowctl = getcfgstring(modemcfg,"FLOWCTL");
	modeminfo.rateadjust = getcfgstring(modemcfg,"RATEADJ");
	modeminfo.mnponly = getcfgstring(modemcfg,"MNPONLY");
	modeminfo.dialtype = getcfgstring(modemcfg,"DIALING");
	if(modeminfo.dialtype!="ATDP")
	    modeminfo.dialtype="ATDT";

	cfg->verify(DEFAULT_ISP_DB_PATH, ISP_DB_PATH);
	(ok, stat) := sys->stat(ISP_DB_PATH);
	if(ok >= 0)
		lastCdir = ref stat;
	sys->print("cfg->init(%s)\n", ISP_DB_PATH);

	# ISP Configuration
	pppcfg := cfg->init(ISP_DB_PATH);
	if (pppcfg == nil) {
		raise("fail: Couldn't load ISP configuration file: "+ISP_DB_PATH);
		return;
	}
	pppinfo = ref pppi;
	isp_number = getcfgstring(pppcfg, "NUMBER");
	pppinfo.ipaddr = getcfgstring(pppcfg,"IPADDR");
	pppinfo.ipmask = getcfgstring(pppcfg,"IPMASK");
	pppinfo.peeraddr = getcfgstring(pppcfg,"PEERADDR");
	pppinfo.maxmtu = getcfgstring(pppcfg,"MAXMTU");
	pppinfo.username = getcfgstring(pppcfg,"USERNAME");
	pppinfo.password = getcfgstring(pppcfg,"PASSWORD");

	info = pppcfg.getcfg("SCRIPT");
	if (info != nil) {
		scriptinfo = ref Script->ScriptInfo;
		scriptinfo.path = hd info;
		scriptinfo.username = pppinfo.username;
		scriptinfo.password = pppinfo.password;
	} else
		scriptinfo = nil;

	info = pppcfg.getcfg("TIMEOUT");
	if (info != nil)
		scriptinfo.timeout = int (hd info);

	cfg = nil;	# might as well unload it
}

#
# Parts of the following two functions could be generalized
#

isipaddr(a: string): int
{
	i, c, ac, np : int = 0;
 
	for(i = 0; i < len a; i++) {
		c = a[i];
		if(c >= '0' && c <= '9') {
			np = 10*np + c - '0';
			continue;
		}
		if (c == '.' && np) {
			ac++;
	 		if (np > 255)
				return 0;
			np = 0;
			continue;
		}
		return 0;
	}
	return np && np < 256 && ac == 3;
}

# check if there is an existing PPP connection
connected(): int
{
	ifd := sys->open("/net/ipifc", Sys->OREAD);
	if(ifd == nil) {
		raise("fail: can't open /net/ipifc");
		return 0;
	}

	d := array[10] of Sys->Dir;
	buf := array[1024] of byte;

	for (;;) {
		n := sys->dirread(ifd, d);
		if (n <= 0)
			return 0;
		for(i := 0; i < n; i++)
			if(d[i].name[0] <= '9') {
				sfd := sys->open("/net/ipifc/"+d[i].name+"/status", Sys->OREAD);
				if (sfd == nil)
					continue;
				ns := sys->read(sfd, buf, len buf);
				if (ns <= 0)
					continue;
				(nflds, flds) := sys->tokenize(string buf[0:ns], " \t\r\n");
				if(nflds < 4)
					continue;
				if (isipaddr(hd tl tl flds))
					return 1;
			}
	}
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	sys->print("Initializing ISP Dial-On-Demand service module\n");

	ppp = load PPPClient PPPClient->PATH;
	if (ppp == nil) {
		raise("fail: Couldn't load ppp module");
		return;
	}

	lock = load Lock Lock->PATH;
	if (lock == nil) {
		raise("fail: Couldn't load lock module");
		return;
	}
	lock->init();

	# Contruct Config Tables During Init - may want to change later
	#	for multiple configs (Software Download Server versus ISP)
	configinit();	
	context = ctxt;

	# set us up a lock
	# isp_lock = Semaphore.new();
}
 
dialup_cancelled: int;      
connecting : int;
xlate(data: string):(list of string)
{
	e := ref Sys->Exception;
	if (sys->rescue("*",e) == Sys->EXCEPTION) {
		sys->print("ispservice: caught exception: %s\n", e.name);
		sys->rescued(Sys->ONCE, nil);
		# isp_lock.release();
		raise(e.name);
	}
	dialup_cancelled = 0;
	# cannot use a lock because this process may be killed with the result that the lock
	# is never released and later requests block permanently
	# isp_lock.obtain();
	(ok, stat) := sys->stat(ISP_DB_PATH);
	if (ok < 0 || lastCdir == nil || !samefile(*lastCdir, stat))
		configinit();
	errc := chan of string;
	for (;;) {
		if (!connected()) {
			if (!connecting) {
				connecting = 1;
				sync := chan of int;
				spawn pppconnect(errc, sync);
				<- sync;
				err := <- errc;
				if (err == nil)
					return data :: nil;
				else
					raise(err);
			}
			else {
				sys->sleep(2500);
				if (dialup_cancelled)
					raise("fail: dialup cancelled");	
			}
		}
		else {
			# isp_lock.release();
			return data :: nil;
		}
	}	
}

pppconnect(errc : chan of string, sync : chan of int)
{
	connecting = 1;
	sys->pctl(Sys->NEWPGRP, nil);
	sync <-= 0;
	resp_chan : chan of int;
	logger := chan of int;
	pppgui := load PPPGUI PPPGUI->PATH;
	for (count :=0; count < ISP_RETRIES; count++) {
		resp_chan = pppgui->init(context, logger, ppp, nil);
		spawn ppp->connect(modeminfo, isp_number, scriptinfo, pppinfo, logger);
		x := <-resp_chan;
		if (x > 0) {
			if (x == 1) {
				# isp_lock.release();
				# alt needed in case calling process has been killed
				alt {
					errc <-= nil => ;
					* => ;
				}
			} else	{		# user canceled dial-in
				dialup_cancelled = 1;
				alt {
					errc <-= "fail: dialup cancelled" => ;
					* => ;
				}
			}
			connecting = 0;
			return;
		}
		# else connect failed, go around loop to try again
	}
	alt {
		errc <-= "fail: dialup failed" => ;
		* => ;
	}
	connecting = 0;
}

samefile(d1, d2: Sys->Dir): int
{
	return d1.dev==d2.dev && d1.dtype==d2.dtype &&
			d1.qid.path==d2.qid.path && d1.qid.vers==d2.qid.vers &&
			d1.mtime==d2.mtime;
}

raise(s : string)
{
#	sys->print("CSplugin : raise %s\n", s);
	sys->raise(s);
}
