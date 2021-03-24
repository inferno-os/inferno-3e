# Limbo HTTP Proxy server
# Written by MArc Hufschmitt marcas1@mime.up8.edu
# MIME Departement, Universite Paris 8
# http://www.mime.up8.edu/

implement proxy;

include "draw.m";
draw : Draw;

include "sys.m";
sys : Sys;
debug :=1;
fdlog : ref Sys->FD;
proxyhalted:=0;


proxy : module {
    init : fn (ctxt : ref Draw->Context, argv : list of string);
};


init ( ctxt : ref Draw->Context, argv : list of string)
{
    buf := array[256] of byte;
    
    sys = load Sys Sys->PATH;
    
    draw = load Draw Draw->PATH;


    pid := sys->pctl(0,nil);
    sys->print("Starting Proxy on port 8080\n");


    fdlog=sys->create("proxy.log",sys->OWRITE,8r644);
    if (fdlog == nil) {
	fdlog = sys->fildes(2);
	sys->fprint(fdlog,"Impossible d'ouvrir proxy.log\n");
    }

    sys->fprint(fdlog,"Log file opened\n");
    while (1) {
	c := EcouteTcp(8080);
	fdremote := sys->open(c.dir+"/remote",sys->OREAD);
	n:=sys->read(fdremote,buf, len buf);
	if (debug)
	    LOG(fdlog,pid,sys->sprint("J'ai recu un appel de %s",string buf[0:n]));
	spawn occupetoide(c);
	c = nil;
    }
    
}

occupetoide(c : ref Sys->Connection)
{
    buf := array[70082] of byte;

    pid := sys->pctl(0,nil);
    #pid := 0;
    n : int;
    
	err : int;
	port : int;
	serveur : string;
	methode : string;
	version : string;
	fichier : string;
	
	clientoptions : string;
	s : string;

    endofheader := 0;
    deb := 0;
    cur := 0;

    while (1) {
	n = sys->read(c.dfd,buf, 1);
#	LOG(fdlog,pid,sys->sprint("deb %d cur %d  '%s'",deb,cur,string buf[0:n]));
	s += string buf[0:n];
	if (buf[0] == byte '\r' || buf[0]== byte '\n') {
	    break;
	    
	}
    }
    
    if (debug)
	LOG(fdlog,pid,sys->sprint("Le client envoie %s",s));
	
    (err,methode,serveur,port,fichier,version) = ParseRequest(s);
	
    if (debug)
	LOG(fdlog,pid,sys->sprint("err:%d Je vais traiter method=%s version=%s serveur=%s port=%d fichier=%s options %s",err,methode,version,serveur,port,fichier,clientoptions));	
    
    if (methode=="STOP" && proxyhalted==0) {
	proxyhalted=1;
	sys->print("Stopped\n");
	return;
    }
    if (methode=="START") {
	proxyhalted=0;
	sys->print("Started\n");
	return;
    }

    if (proxyhalted==1)
	return;


    rerequest :=methode+" "+fichier+" "+version;

    (ok,realc) := connecteTCP(serveur,port);
    if (ok>=0) {
	fdremote := sys->open(realc.dir+"/remote",sys->OREAD);
	n:=sys->read(fdremote,buf, len buf);
	sys->print("Je me connecte a %s",string buf[0:n]);

	vrairep := "";


	sys->write(fdlog,array of byte rerequest, len rerequest);

	sys->write(realc.dfd, array of byte rerequest,len rerequest);
	#LOG(fdlog,pid,sys->sprint("j'ai envoye"));
	


	pasfini := 1;
	
	spawn echangelog(c, realc, fdlog,pid);
	spawn echangelog(realc, c, fdlog, pid);

	#sys->write(c.cfd,array of byte "hangup", 6);
	    
	#sys->stream(c.dfd,realc.dfd,200);
	
	#n= sys->read(realc.dfd,buf,len buf);
	#vrairep = string buf[0:n];
	#sys->print("j'ai recu du serveur %d[%s]\n",len vrairep,vrairep);
	
	#n=sys->write(c.dfd,array of byte vrairep, len vrairep);
	#sys->print("j'ai renvoye au client %d\n",len vrairep);
	#sys->stream(realc.dfd,c.dfd,2000);
	#sys->sleep(200);
	
    }
    else {
	    LOG(fdlog,pid,"Connexion impossible sur "+serveur+":" + string port);
	    sys->write(c.dfd, err202:= array of byte ("HTTP/1.0 202 Proxy Erreur\n\n<HTML>ERREUR PROXY 202 SERVEUR "+serveur+" INTROUVABLE<BR></HTML>"), len err202);
	    
	}
    
    realc=nil;
    c = nil;
}

LOG(fdlog : ref Sys->FD, pid : int, err : string) 
{
    sys->fprint(fdlog,"****[%d]**** %s\n",pid,err);
}

EcouteTcp(port : int) : ref sys->Connection
{

	nomcon:="/net/tcp!*!"+string port;
	(err,tcpcon) := sys->announce(nomcon);
	if (err<0) {
     		sys->print("announce avorte : %s\n", nomcon);
		return nil;
	}
	(err,tcpcon)=sys->listen(tcpcon);
	if (err<0) {
	  sys->print("listen avorte : %s\n", nomcon);
	  return nil;
	}

	tcpcon.dfd= sys->open(tcpcon.dir+"/data", sys->ORDWR);
	if (tcpcon.dfd == nil) {
	  sys->print("Ouverture R/W impossible : %s/data",tcpcon.dir);
	  exit;
	}

	return ref tcpcon;
}


connecteTCP(serv : string, port : int) : (int, ref sys->Connection)
{
  dialto:="net!"+serv+"!"+string port;
    (ok,conn):=sys->dial(dialto,nil);
    #if (ok) 
#	conn.dfd = sys->open(conn.dir+"/data",sys->ORDWR);
    
    return (ok,ref conn);
}

ParseRequest( r : string ) : (int,string,string,int,string,string)
{
    port := 80;
    serveur : string;
    methode : string;
    uri : string;
    version : string;
    fichier : string;
    err := 0;
    (n,l) := sys->tokenize(string r," \t");
    case hd l {
	"GET" or "POST" or "HEAD" =>
	methode=hd l;
	l = tl l;
	* =>
	return (-1 , hd l,"",0,"","");
    }
    uri=hd l;
    l = tl l;
    version = hd l;
    if (uri[0:7]=="http://") {
	siteport : string;
	for (i:=7; i< len uri; i++)
	    if (uri[i]=='/') {
		siteport= uri[7:i];
		fichier=uri[i:];
		break;
	    }

	site : list of string;
	if (n>1) {
	    (n,site)=sys->tokenize(siteport,":");
	    
	    serveur = hd site;
	    if (n>1)
		port = int (hd (tl site));
	}
	else {
	    serveur = siteport;
	}
	sys->print("site %s port %d\n",serveur,port);
    }
    else {
	err=-1;
    }
    return(err,methode,serveur,port,fichier,version);
    
}

echangelog ( a, b: ref sys->Connection, fdlog : ref sys->FD, pid : int)
{
    buf := array[10000] of byte;
    while (reads := sys->read(a.dfd,buf,len buf)) {
	
	sys->write(b.dfd,buf,reads);
	LOG(fdlog,pid,sys->sprint("%s -> %s",a.dir, b.dir));
	sys->write(fdlog,buf,reads);
    }
    
}
	    

