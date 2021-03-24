implement CSplugin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "cs.m";
include "cfgfile.m";
include "srv.m";
	srv: Srv;

include "ipsrv.m";
	is: Ipsrv;

#
#	Module:		ipservice
#	Purpose:	Connection Server Plugin For IP (DNS Name & Service Name Resolution)
#	Author:		Inferno Business Unit Members
#

#
# Front-End For CSplug-in
#

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	srv = load Srv Srv->PATH;

	sys->print("Initializing IP service module\n");

	cfg := load CfgFile CfgFile->PATH;
	if (cfg == nil) {
		sys->raise("fail:load CfgFile");
		return;
	}
	if (cfg->verify(defaultdnsfile, dnsfile) == nil && srv == nil)
		sys->raise(Econfig);
	  
	is = load Ipsrv Ipsrv->PATH;
	if(is != nil){
		is->init(Ipsrv->PATH :: "-d" :: dnsfile :: nil);
	}else if(srv == nil)
		sys->raise("fail: load "+Ipsrv->PATH);
}

#
# IP Service->Port Mapping
#
defaultdnsfile: con "/services/dns/db";
dnsfile: con "/usr/inferno/config/dns.cfg";

isipaddr(a: string): int	# wrong for ipv6
{
	i, c: int;

	if(a == nil)
		return 0;
	for(i = 0; i < len a; i++) {
		c = a[i];
		if((c < '0' || c > '9') && c != '.')
			return 0;
	}
	return 1;
}

isnumeric(a: string): int
{
	i, c: int;

	for(i = 0; i < len a; i++) {
		c = a[i];
		if(c < '0' || c > '9')
			return 0;
	}
	return 1;
}

xlate(data: string):(list of string)
{
	n: int;
	l, rl : list of string;
	netw, mach, service: string;

	(n, l) = sys->tokenize(string data, "!\n");
	if(n != 3) {
		sys->raise("fail: "+Ebadargs);
		return nil;
	}

	netw = hd l;
	mach = hd tl l;
	service = hd tl tl l;

	if(netw == "net")
		netw = "tcp";

	if(isnumeric(service) == 0) {
		r: string;
		if(is != nil)
			r = is->ipn2p(netw, service);
		else if(srv != nil)
			r = srv->ipn2p(netw, service);
		if(r == nil) {
			sys->raise("fail: "+Eservice);
			return nil;
		}
		service = r;
	}	

	if(mach == "*")
		l = "" :: nil;
	else
		if(isipaddr(mach) == 0) {
			r: list of string;
			if(is != nil)
				r = is->iph2a(mach);
			else if(srv != nil)
				r = srv->iph2a(mach);
			if(r == nil) {
				sys->raise("fail: "+Eunknown);
				return nil;
			}
			l = r;
		}
		else
			l = mach :: nil;		

	# Construct a return list based on translated values
 	for(; l != nil; l = tl l)
		rl = netw+"!"+(hd l)+"!"+service::rl;
    	
	# Reverse the list
	for(; rl != nil; rl = tl rl) 
		l = (hd rl)::l;	

  	return l;	
}
