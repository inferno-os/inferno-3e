.de EX
.nr x \\$1v
\\!h0c n \\nx 0
..
.de FG		\" start figure caption: .FG filename.ps verticalsize
.KF
.BP \\$1 \\$2
.sp .5v
.EX \\$2v
.ps -1
.vs -1
..
.de fg		\" end figure caption (yes, it is clumsy)
.ps
.vs
.br
\l'1i'
.KE
..
\" step numbers
.nr ,s 0 1
.af ,s a
.am NH
.nr ,s 0 1
..
.de Sn		\" .Sn "step"
\(sq Step \\n(H1\\n+(,s: \\$1
..
.TL
Installation of the Inferno Software
.SP 4
.PP
Inferno can run as either a native operating system or as a
.I hosted
virtual operating system.
This paper explains how to install Inferno from the distribution media
to a hosted environment and how to configure the system for
basic networking.
.LP
Third edition Inferno can run as a hosted virtual operating system on top of
Plan 9, Unix or Windows.
In this paper, the term
.I Unix
is used to cover all supported variants, currently FreeBSD, Linux, HP/UX, Irix and Solaris,
and the term
.I Windows
covers Microsoft Windows 95, Windows 98, Windows Nt and Windows 2000.
.NH
Preparation
.PP
You should ensure that there are at least 150 Mbytes of free space on the filesystem.
The installation program will copy files from the distribution CD to a
directory on the filesystem called the
.I inferno_root
directory.
You can choose the location of this directory.
If you are installing to a multiuser filesystem a subdirectory of your home
directory might be a sensible choice of location. If you plan to share the Inferno
system with other users then common choices for
.I inferno_root
are
.CW /usr/inferno
on Unix and Plan 9 systems, and
.CW c:\eusers\einferno
on Windows systems.
Where these appear in examples in this paper you should substitute
your own
.I inferno_root
directory.
.P1
.B
.Sn "Choose the \fIinferno_root\fB directory."
.P2
Ensure that the user who will run the installation program has
appropriate filesystem permissions to create the
.I inferno_root
directory and
files and subdirectories beneath it.
.NH
Copying Files
.PP
On all platforms except Windows 95 and Windows 98, the files copied
will be owned by the user who runs the installation. 
On Unix, Windows Nt and Windows 2000, if the installation is run by user
.CW root
and a user
.CW inferno
exists the installed files will be owned by user
.CW inferno .
.P1
.B
.Sn "Insert the distribution CD into the CD drive."
.P2
On Unix and Plan 9,
mount the CD to a suitable location on the filesystem, call this location
.I cd_path .
On Windows, note the drive letter of the CD, call this drive letter
.I cd_drive .
The files will be copied by an Inferno hosted installation program which runs
directly from the CD.
The directory
.CW /install
on the CD contains an installation program for each supported platform \- a shell
script for Unix and Plan 9 and an executable for Windows.
The Plan 9 install script is called
.CW Plan9.rc
and determines the CPU type from the environment variable
.CW cputype .
The Unix install scripts all have names of the form
.CW \fIhost-os\f(CW-\fIhost_arch\f(CW.sh
where
.I host-os
will be one of:
.CW FreeBSD ,
.CW Linux ,
or
.CW Solaris
and
.I host_arch
will be one of:
.CW 386 ,
.CW mips ,
.CW power
or
.CW sparc .
Not all combinations are available.
The Windows installation program is called
.CW Nt-386.exe
and can be used on
Windows Nt, Windows 95, Windows 98 and Windows 2000 - it
is only available in combination with the
.CW 386
CPU architecture option.
The next step describes how to begin the installation by running the program
that corresponds to your host system.
.P1
.B
.Sn "Run the installation script."
.P2
The installation program will copy files from the CD to the filesystem.
The Windows installation program will also create registry entries and add
an Inferno item to the Windows
.I start
menu.
On Plan 9, run
.P1
rc \fIcd_path\f(CW/install/Plan9.rc \fIinferno_root\f(CW
.P2
Where
.I inferno_root
is the path to the chosen Inferno root directory. The CPU architecture
will be inferred from the environment variable
.CW cputype .
On Unix, run
.P1
sh \fIcd_path\f(CW/install/\fIhost-os\f(CW-\fIhost_arch\f(CW.sh  \fIinferno_root\f(CW
.P2
Where
.I host_os
is the Unix variant name
.CW FreeBSD , (
.CW Linux
or
.CW Solaris ).
.I host_arch
is the CPU type (most likely
.CW 386 ), 
and
.I inferno_root
is the path to the chosen Inferno directory.
On Windows, run
.P1
\fIcd_drive\f(CW:\einstall\esetup.exe
.P2
The Windows installation program will ask you to choose the location of the installation
directory on the hard disk.
.LP
Files will then be copied from the CD to the
.I inferno_root
subtree on the filesystem. Inferno is now installed, but some configuration
is required.
.NH
Running Inferno
.PP
Inferno host executables are all kept in a single directory corresponding
to the combination of host operating system and CPU architecture - the Inferno
.CW bin
directory.
.P1
\fIinferno_root\f(CW/\fIhost_os\f(CW/\fIhost_arch\f(CW/bin
.P2
Plan 9 users should add a line to their
.CW lib/profile
file that binds this directory after their
.CW /bin
directory.
.P1
bind -a /usr/inferno/Plan9/$cputype/bin /bin
.P2
The bind is done after the existing
.I bin
directory to avoid hiding your existing Plan 9 compilers.
If, at a later stage, you build either the hosted or native Inferno kernels
you should ensure that the Inferno compilers are used rather than
the Plan 9 compilers. The differences between the two compiler suites
are likely to be reduced in future releases.
On Windows systems the
.I host_os
is always
.CW Nt
and
.I host_arch
is always
.CW 386
and the installation program will create an entry on the
.I "start menu"
to invoke Inferno.
For Unix systems or Windows systems in which Inferno will be started
from a command shell, the environment variable
.CW PATH
should be set to include the Inferno
.CW bin
directory.
For Windows 95 and Windows 98 this should be done in the
.CW \eautoexec.bat
file by adding a line like
.P1
PATH="c:\eusers\einferno\eNt\e386\ebin";%PATH%
.P2
You will need to reboot Windows to have the system re-read the
.CW \eautoexec.bat
file.
For Windows NT and Windows 2000 modify the
.CW Path
environment variable through
.I "Control Panel -> System -> Environment" .
For Unix this should be done in your
.CW .profile
file by adding a line like
.P1
PATH="/usr/inferno/Linux/386/bin:$PATH"
.P2
Don't forget to ensure that
.CW PATH
is exported.
You may need to log out and back in again for these changes to take effect.
.KS
.P1
.B
.Sn "Start Inferno."
.P2
Hosted inferno is run by invoking an executable called
.I emu .
.KE
On Windows, select the Inferno option from the
.I "start menu" .
This will invoke
.I emu
with appropriate arguments to find its files in
.I inferno_root .
If you need to change any of the options passed to
.I emu
when invoked from the
.I "start menu"
you need to do this by clicking the right mouse button
on the Windows task bar and choosing
.I "Properties -> Start Menu Programs -> Advanced"
to modify the shortcut used for Inferno.
For Unix and Plan 9, you will need to tell
.I emu
where to find the Inferno file tree by passing it the
.CW -r\fIrootpath\f(CW
command line option. For example
.P1
emu -r/usr/john/inferno
.P2
Without the
.CW -r
option it will look for the file tree in
.CW /usr/inferno
on Plan 9 and Unix and
.CW \eusers\einferno
on the current drive for Windows.
By default, when using graphics
.I emu
will use a window with a resolution of 640 x 480 pixels. To use a larger resolution
you will need to pass
.I emu
the
.CW -g\fIXsize\f(CWx\fIYsize\f(CW
command line option. So, for example, to invoke
.I emu
as above but with a resolution of 1024 x 768 pixels the full command line
would be
.P1
emu -r/usr/john/inferno -g1024x768
.P2
When invoked in this way
.I emu
displays a command window running the Inferno shell
.CW /dis/sh.dis .
To avoid typing the command line options each time you invoke
.I emu
you can store them in the environment variable
.CW EMU
which is interrogated when
.I emu
is started and might as well be set along side the
.CW PATH
environment variable if the same configuration options are to be used on
each invocation.
.P1
set EMU="-rd:\eusers\ejohn\einferno -g1024x768"
.P2
for Windows.
.P1
EMU=(-r/usr/john/inferno -g1024x768)
.P2
for Plan 9, and
.P1
EMU="-r/usr/john/inferno -g1024x768"
.P2
for Unix.
An alternative to using the
.CW EMU
environment variable is to place the correct invocation in a
script file (or batch file, for Windows) and invoke that instead
of running
.I emu
directly.
It is important to note that for Windows the
.CW -r
option also serves to indicate both the drive and directory on to which the software
has been installed. Without a drive letter the system will assume the
current drive and will fail if the user changes to an alternative drive.
Once the environment variables or scripts are set up, as described above, invoking
.P1
emu
.P2
or the appropriate script file,
should result in output which look something like this
.P1
Inferno Third Edition (18 Jun 2001) main (pid=689) interp
Initialize Dis: /dis/emuinit.dis
; 
.P2
You are now running third edition Inferno, built on 18th June 2001; the word
.CW interp
means that the Inferno Dis virtual machine is interpreting Dis instructions.
You can add a further option
.CW -c1
(see the
.I emu (1)
manual page) to cause
.I emu
to start up in
.I compile
mode in which the JIT compiler is automatically invoked to compile all
Dis operations to native machine instructions on demand. In
.I compile
mode most programs will run significantly faster.
Whether in compiled or interpreted mode you should now have a functional
hosted Inferno system.
When Inferno starts the initial
.CW /dis/sh.dis
it reads commands from the file
.CW /lib/sh/profile
before becoming interactive. See the manual pages for the shell
.I sh (1)
to learn more about tailoring the initial environment.
The semi-colon is the default shell prompt. From this command window
you should be able to see the installed Inferno files and directories
.P1
lc /
.P2
The command
.I lc
presents the contents of its directory argument in columnar fashion to standard
output in the command window.
.P1
; lc /
Inferno/     emu/         lib/         mkfile       services/
Linux/       fonts/       lib9/        mkfiles/     tk/
Nt/          icons/       libbio/      module/      tmp/
appl/        image/       libregexp/   n/           tools/
asm/         include/     limbo/       net/         usr/
chan/        interp/      math/        nvfs/        utils/
crypt/       kern/        memimage/    os/          
dev/         keyring/     memlayer/    prefab/
dis/         kfs/         mkconfig     prog/
;
.P2
Only the files and directories in and below the
.I inferno_root
directory on the host filesystem are immediately visible to an Inferno process;
these files are made visible in the root of the Inferno file namespace.
If you wish to import or export files
from and to the host filesystem you will need to use tools on your
host to move them in or out of the Inferno visible portion of your host
filesystem (see the manual pages
.I os (1)
and
.I cmd (3)
for an interface to host commands).
From this point onwards in this paper all file paths not qualified with
.I inferno_root
are assumed to be in the Inferno namespace.
Files created in the host filesystem will be created with the user id of
the user that started
.I emu
and on Unix systems with that user's group id.
.NH
Setting the site's time zone
.PP
Time zone settings are defined by
files in the directory
.CW /locale/timezone .
For instance, the file
.CW /locale/GMT
defines Greenwich Mean Time,
.CW /locale/GB-Eire
defines time zones for Great Britain and the Irish Republic
(GMT and British Summer Time), and
.CW /locale/US_Eastern
defines United States
Eastern Standard Time and Eastern Daylight Time.
The time zone settings used by applications are read
(by
.I daytime (2))
from the file
.CW /locale/timezone ,
which is initially a copy of
.CW /locale/GB-Eire .
To set a different time zone for the whole site,
copy the appropriate time zone file into
.CW /locale/timezone :
.P1
cp /locale/US_Eastern /locale/timezone
.P2
To set a different time zone for a user or window,
.I bind (1)
the file containing the time zone setting over
.CW /locale/timezone ,
either in the user's profile or in a name space description file:
.P1
bind /locale/US_Eastern /locale/timezone
.P2
.NH
Running the
.I wm
Window Manager
.PP
Many Inferno programs run under the
.I wm
window manager.
Inferno has a simple editor,
.I wm/edit ,
that can be used to edit the inferno configuration files.
.P1
.B
.Sn "Start the window manager."
.P2
Invoke
.I wm
by typing
.P1
wm/wm
.P2
You should see a new window open with a blue background and a small
.I "Vita Nuova"
logo in the bottom left hand corner. Click on the logo with mouse button 1
to reveal a small menu.
Selecting the 
.I Edit
entry will start
.I wm/edit .
In common with most
.I wm
programs the editor has three small buttons in a line at its top right hand corner.
Clicking on the X button, the right most button,
will close the program down. The left most of the three buttons will allow the window
to be resized - after clicking it drag the window from a point near to either one of its
edges or one of its corners. The middle button will minimise the window, creating
an entry for it in the application bar along the bottom of the main
.I wm
window. You can restore a minimised window by clicking on its entry in the application bar.
The initial
.I wm
configuration is determined by the contents of the shell
script
.CW /lib/wmsetup
(see
.I sh (1)).
.P1
.B
.Sn "Open a shell window."
.P2
Choose the
.I shell
option from the menu to open up a shell window. The configuration of Inferno
will be done from this shell window.
.NH
Manual Pages
.PP
Manual pages for all of the system commands are available from a shell
window. Use the
.I man
or
.I wm/man
commands. For example,
.P1
man wm
.P2
will give information about
.I wm .
And
.P1
man man
.P2
will give information about using
.I man .
.I Wm/man
makes use of the Tk text widget to produce slightly more
attractive output than
.I man .
Here, and in other Inferno documentation you will see references to manual page
entries of the form \fIcommand\f(CW(\fIsection\f(CW)\fR.
You can display the manual page for the command by running
.P1
man \fIcommand\f(CW
.P2
or
.P1
man \fIsection\f(CW \fIcommand\f(CW
.P2
if the manual page appears in more than one section.
.NH
Initial Namespace
.PP
The initial Inferno namespace is built
by placing the root device '#/' (see
.I root (3))
at the root of the namespace and binding
.nr ,i 0 1
.af ,i i
.IP  \n+(,i)
the host filesystem device '#U' (see
.I fs (3))
containing the
.I inferno_root
subtree of the host filesystem at the root of the Inferno filesystem,
.IP  \n+(,i)
the console device '#c' (see
.I cons (3))
in
.CW /dev ,
.IP  \n+(,i)
the prog device '#p' (see
.I prog (3))
onto
.CW /prog ,
.IP  \n+(,i)
the IP device '#I' (see
.I ip (3))
in
.CW /net ,
and
.IP  \n+(,i)
the environment device '#e' (see
.I env (3))
at
.CW /dev/env .
.rr ,i
.LP
You can see the sequence of commands required to construct the current namespace
by running
.P1
ns
.P2
To use IP networking, the IP device
.I ip (3)) (
must have been bound into
.CW /net .
Typing
.P1
ls -l /net
.P2
(see
.I ls (1))
should result in something like
.P1
dr-xr-xr-x I   0 bootes bootes 0 Feb 02 14:48 /net/tcp
dr-xr-xr-x I   1 bootes bootes 0 Feb 02 14:48 /net/udp
.P2
We can now configure Inferno to allow secure connections to other
Inferno systems. First we will start a signer process which will generate
certificates for both the system making a connection and the system
receiving the connection. If there is only one machine in your Inferno
network then the same machine will be user as client, server and
certificate signer.
.NH
Connection Server
.PP
The connection server (see
.I cs (8)
and
.I db (6))
translates symbolic network names and services into instructions
for connecting to a given service.
The file
.CW /services/cs/db
defines a mapping from machine names of the form
.CW $\fIservice\f(CW
to either a network address or a numeric address.
The connection server will convert such a machine name using this file
into either a numeric address or a machine name.
A typical
.CW /services/cs/db
file will look something like this
.P1
$SIGNER		doppio
$FILESERVER	rotta
$MAILSERVER	doppio
$PROXY		pox
.P2
Network and service names are passed through to the host for conversion to numeric
addresses and port numbers. If the host is unable to convert a service name
the connection server will attempt to convert the name using mappings
of service and protocol names to Internet port numbers
in the file
.CW /services/cs/services
which should contain at least the following entries
.P1
styx        6666/tcp          # Main file service
mpeg        6667/tcp          # Mpeg stream
rstyx       6668/tcp          # Remote invocation
infdb       6669/tcp          # Database connection
infweb      6670/tcp          # inferno web server
infsigner   6671/tcp          # inferno signing services
infcsigner  6672/tcp          # inferno signing services
inflogin    6673/tcp          # inferno login service
virgil      2202/udp virgild  # inferno info
.P2
For the moment, leave this file as it is.
You will need to modify this file, at some point in the future,
if you add new services to Inferno
and want to refer to them by name.
.P1
.B
.Sn "Start the connection server."
.P2
To run the connection server, type
.P1
lib/cs
.P2
You should now see a new file in the
.CW /net
directory called
.CW cs .
Run the command
.P1
ls /net
.P2
You should see the following output
.P1
/net/cs
/net/tcp
/net/udp
.P2
Before an Inferno machine can establish a connection to an Inferno
service on another machine, each needs to obtain a certificate from a common signer.
To bootstrap this process we will configure this machine as a signer.
.NH
Network Services
.PP
The command
.I srv
is used to start listeners for local network servers (see
.I srv (8)).
.I Srv
starts a listener for each service configured in
.CW /services/server/config .
.P1
S infsigner   tcp /dis/lib/signer.dis 
S infcsigner  tcp /dis/lib/countersigner.dis
S inflogin    tcp /dis/lib/logind.dis         
S styx        tcp /dis/lib/styxd.dis nossl clear sha md5 rc4 sha/rc4
S rstyx       tcp /dis/lib/rstyxd.dis nossl clear sha md5 rc4 sha/rc4
S infdb       tcp /dis/lib/dbsrv.dis  nossl clear sha md5 rc4 sha/rc4
S virgil      udp /dis/lib/virgild.dis
M 67          udp /dis/lib/bootp.dis
M 69          udp /dis/lib/tftpd.dis
.P2
Documentation for these servers can be found in section 8 of the
Programmers Manual (Volume 1).
Start the listeners on this machine by running
.I srv .
.KS
.P1
.B
.Sn "Start the network listener services."
.P2
Type
.P1
lib/srv
.P2
Your servers will now be running. To confirm this type
.P1
netstat
.P2
.KE
.I Netstat
prints information about network connections. You should see
several lines of output, each one describing an announced TCP or UDP service.
Depending upon the contents of your
.CW /services/server/config
file you should see something which looks like this
.P1
tcp/0    inferno    200.1.1.89!6669      0.0.0.0!0      Announced
tcp/1    inferno    200.1.1.89!6668      0.0.0.0!0      Announced
tcp/2    inferno    200.1.1.89!6666      0.0.0.0!0      Announced
tcp/3    inferno    200.1.1.89!6673      0.0.0.0!0      Announced
tcp/4    inferno    200.1.1.89!6672      0.0.0.0!0      Announced
tcp/5    inferno    200.1.1.89!6671      0.0.0.0!0      Announced
udp/0    inferno    200.1.1.89!2202      0.0.0.0!0      Announced
.P2
Each line corresponds to a network connection:
the connection name, the name of the user running the server,
the address of the local end of the connection,
the address of the remote end of the connection,
and the connection status.
The connection name is actually the protocol and conversation directory
in
.CW /net .
The connection addresses are all of the form \fIhost\f(CW!\fIport\fR
for these IP based services, and the remote addresses are not filled in
because they all represent listening services that are in the
.CW Announced
state.
In this example the fourth line shows a TCP service listening on port 6673.
Examining
.CW /services/cs/services
with
.CW grep
(see
.I grep (1))
shows that the listener on port 6673 is the Inferno login service.
.P1
grep 6673 /services/cs/services
.P2
gives
.P1
inflogin    6673/tcp          # inferno login service
.P2
Before the signing service can be used to generate certificates
some configuration is required.
The signer needs a public and private key-pair and a database of
user names and passwords.
.NH
Configuring a Signer
.PP
To use authenticated connections we need to set up a signer to generate
certificates for users (see
.I createsignerkey (8)
and
.I signer (8)).
For two machines to communicate securely they must both have obtained
a certificate from the same signer.
Choose an Inferno machine to become the signer.
If this is the first or only
Inferno machine on your network then make this machine the signer.
.P1
.B
.Sn "Generate a signer key."
.P2
On the signer machine run
.P1
lib/createsignerkey \fIname\f(CW
.P2
In place of
.I name
enter the network name of the signer. This value will appear as the signer name in each
certificate generated by the signer.
.I Createsignerkey
creates public and private keys that are used by the signer when generating
certificates.
.P1
.B
.Sn "Enter user names and secrets."
.P2
For each user to be authenticated by the signer run
.P1
changelogin \fIusername\f(CW
.P2
You will be prompted to supply a secret (i.e. password) and expiration date.
The expiration date will be used
as the expiration date of certificates generated for that user.
.I Changelogin
(see
.I changelogin (8))
will create and update entries in the file
.CW /keydb/password .
For the signer to generate a certificate there must be at least one entry in the
password file.
If you are not sure at this stage of the names of the users that you want to
authenticate then create an entry for the user
.CW inferno .
.NH
Establishing a Secure Connection
.PP
To establish a secure connection between two machines, each needs to have
a certificate signed by a common signer (which need not be a third machine).
If you have only one Inferno machine you can experiment with secure connections
by making the same machine signer, server and client.
.PP
.P1
.B
.Sn "Generate a server certificate."
.P2
On the server machine,
ensure that
.CW lib/cs
is running.
You will need it if you refer
to your signer by hostname instead of IP address.
If in doubt, or if it is not running, type
.P1
lib/cs
.P2
On the server machine, use
.I getauthinfo (8)
to obtain a certificate and save it in a file named
.CW default
by running
.P1
getauthinfo default
.P2
.I Getauthinfo
will prompt for the address of your signer and for a remote username and password
combination.
.I Getauthinfo
will connect to the
.I inflogin
service on the signer and authenticate you against its user and password database,
.CW /keydb/password ,
using the username and password that you entered.
Answer
.CW Yes
to the question that asks if you want to save the certificate in a file.
.I Getauthinfo
will save a certificate in the file
.CW /usr/\fIuser\f(CW/keyring/default
where
.I user
is the name in
.CW /dev/user .
.P1
.B
.Sn "Generate a client certificate."
.P2
Obtain a certificate for the client in the same way.
Type
.P1
getauthinfo default
.P2
If you wish you can obtain a certificate for use with a specific server
by storing
it in a file whose name exactly matches the network address of the server
.P1
getauthinfo tcp!\fIhostname\f(CW
.P2
.I Getauthinfo
stores the certificate in the file
.CW /usr/\fIuser\f(CW/keyring/\fIkeyname\f(CW
where
.I user
is the name in
.CW /dev/user
and
.I keyname
is the argument given to
.I getauthinfo .
Again, 
answer
.CW Yes
to the question that asks if you want to save the certificate in a file.
Now that both client and server have a certificate obtained from the same signer
it is possible to establish a secure connection between them.
If you have only one Inferno system you can still test the configuration by using
the same machine as both client and server. Alternatively, start a second copy of
.I emu
on the same machine and treat one as the server and one as the client.
.P1
.B
.Sn "Make an authenticated connection."
.P2
On the server, make sure that
.I srv
is running, type
.P1
netstat
.P2
you should see a line for the TCP service listening on port 6666.
.P1
tcp/2    inferno    200.1.1.89!6666      0.0.0.0!0      Announced
.P2
If you do not see any output, start
.I srv
by running
.P1
lib/srv
.P2
The listener on port 6666 is expecting to serve the Inferno file
protocol
.I Styx
to export a namespace.
.P1
grep 6666 /services/cs/services
.P2
Gives
.P1
styx        6666/tcp          # Main file service
.P2
The line for the
.I styx
service in the file
.CW /services/server/config
shows that the server
.CW /dis/lib/styxd.dis
is listening on port 6666.
The namespace that
.I styxd
serves is the one that it inherited when it was started with
.I srv .
On the client, make sure that
.I Cs
is running by typing
.P1
lib/cs
.P2
Now that
.CW lib/cs
is running on the client and
.CW lib/srv
is running on the server
you can test the service.
On the client, confirm that
.CW /n/remote
is an empty directory with
.P1
lc /n/remote
.P2
On the client, you can now mount the namespace that
.I styxd
is serving on the server onto the client directory
.CW /n/remote
by typing
.P1
mount  tcp!\fIserveraddr\f(CW /n/remote
.P2
Where
.I serveraddr
is the IP address of the server or a name which the host can resolve to the
IP address of the server.
Now
.P1
lc /n/remote
.P2
should reveal the files and directories in the namespace being served by
.I styxd .
Those files are now also visible in the namespace of your shell.
You will notice that these changes only affect the shell in which you ran the
.I mount
command - other processes are unaffected.
You can create, remove or modify files and directories in and under
.CW /n/remote
much as you can any other file or directory in your namespace.
In fact, in general, a process does not need to know whether a file
actually resides locally or remotely.
You can unmount the mounted directory with
.I unmount .
Type
.P1
unmount /n/remote
.P2
You can confirm that it has gone by running
.P1
ls /n/remote
.P2
All connections made by Inferno are authenticated. The default connection
made by
.I mount
is authenticated but does not use SSL.
The arguments passed to
.I styxd
in its entry in
.CW /services/server/config
.P1
S rstyx       tcp /dis/lib/rstyxd.dis nossl clear sha md5 rc4 sha/rc4
.P2
define the different combinations of security algorithms that
.I styxd
is prepared to accept.
You can pass an argument to
.I mount
to specify
a more secure connection.
The
.CW -C
option to
.I mount
can be used to specify a hashing and an encryption algorithm to be applied to
the connection.
.P1
.B
.Sn "Make a secure authenticated connection."
.P2
For example,
.P1
mount  -C sha/rc4 tcp!\fIserveraddr\f(CW /n/remote
.P2
will make an authenticated connection to the machine given by
.I serveraddr
using SHA hashing for message digesting and RC4 for encryption
and mount the namespace served by the server's
.I styx
service on the client directory
.CW /n/remote .
.NH
Adding new users
.PP
Every inferno process has an associated
.I "user name" .
At boot time the user name is set equal to your login name on the host
operating system. You can change the user name by writing the new user name to
the file
.CW /dev/user .
This is a one time operation; once the user name has been changed from the original
it cannot be changed again in that process.
The user name is used to select the directory in which programs like
.I mount
search for certificates. When you attach to a server on another
system the user name is passed across to the remote system as part of the
attach procedure allowing the remote system
to assign the correct ownership to files created on the remote server.
The
.I wm
window manager program
.I wm/logon
allows a user to login to the local Inferno system before running the
main window manager program
.I wm/wm .
.P1
.B
.Sn "Re-start Inferno."
.P2
You should now close down any instances of
.I emu
that you are currently running.
The quickest way to do this is to
type
.I control-c
in the emu window in which you ran
.I wm/wm .
Start a new
.I emu ,
as before, by either running
.P1
emu
.P2
or by choosing the appropriate entry from your start menu on
Windows machines. This time, run
.P1
wm/logon
.P2
and log in as user
.I inferno .
When you log in
.I wm/logon
will change directory to
.CW /usr/inferno
and then write the name
.CW inferno
to
.CW /dev/user .
If this is the first time that you have logged on as user
.I inferno
to this machine it will display a licence.
If the file
.CW /usr/inferno/namespace
exists it will be used to construct a new namespace for the user
based on the commands that it contains (see
.I newns (2)).
.I Logon
will then start
.I wm/wm .
.NH
What next
.PP
You should now have a fully functional Inferno system.
You will need to have a three button mouse to use
.I acme ,
.I wm ,
or
.I plumbing .
.PP
To learn more you could start with the manual pages for:
.I intro (1),
.I emu (1),
.I wm (1),
.I wm-misc (1),
.I sh (1),
.I acme (1),
and
.I limbo (1)
and also the papers in sections 1, 2 and 3
of volume two of the Inferno Programmer's Manual.
