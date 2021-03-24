# fit a polynomial to a set of points
#	fit -n [-v]
#		where n is the degree of the polynomial

implement Fit;

include "sys.m";
include "draw.m";
include "math.m";
include "bufio.m";

sys : Sys;
bufio : Bufio;
maths : Math;

Fit : module
{
	init : fn(nil : ref Draw->Context, argv : list of string);
};

MAXPTS	: con 512;
MAXPOW	: con 16;
EPS : con 0.0000005;

stderr : ref Sys->FD;

init(nil : ref Draw->Context, argv : list of string)
{
    sys = load Sys Sys->PATH;
    maths = load Math Math->PATH;
    if (maths == nil) {
	sys->fprint(stderr, "cannot load maths library\n");
	exit;
    }
    bufio = load Bufio Bufio->PATH;
    if (bufio == nil) {
	sys->fprint(stderr, "cannot load bufio\n");
	exit;
    }
    stderr = sys->fildes(2);
    main(argv);
}

isn(r : real, n : int) : int
{
    s : real = r - real n;

    if (s < 0.0)
	s = -s;
    return s < EPS;
}

fact(n : int) : real
{
    i : int;
    f : real = 1.0;

    for (i = 1; i <= n; i++)
	f *= real i;
    return f;
}

comb(n : int, r : int) : real
{
    i : int;
    f : real = 1.0;

    for (i = 0; i < r; i++)
	f *= real (n-i);
    return f/fact(r);
}

power(x : real, n : int) : real
{
    i : int;
    y : real = 1.0;

    for (i = 0; i < n; i++)
	y *= x;
    return y;
}

matalloc(n : int) : array of array of real
{
    i : int;
    mat : array of array of real;

    mat = array[n] of array of real;
    for (i = 0; i < n; i++)
	mat[i] = array[n] of real;
    return mat;
}

matsalloc(n : int) : array of array of array of real
{
    i : int;
    mats : array of array of array of real;

    mats = array[n+1] of array of array of real;
    for (i = 0; i <= n; i++)
	mats[i] = matalloc(i);
    return mats;
}

det(mat : array of array of real, n : int, mats : array of array of array of real) : real
{
    i, j, k, s : int;
    d : real;
    m : array of array of real;

    # easy cases first
    if (n == 0)
	return 1.0;
    if (n == 1)
	return mat[0][0];
    if (n == 2)
	return mat[0][0]*mat[1][1]-mat[0][1]*mat[1][0];
    d = 0.0;
    s = 1;
    m = mats[n-1];
    for (k = 0; k < n; k++) {
	for (i = 0; i < n-1; i++) {
	    for (j = 0; j < n-1; j++) {
		if (j < k)
		    m[i][j] = mat[i+1][j];
		else
		    m[i][j] = mat[i+1][j+1];
	    }
	}
	d += (real s)*mat[0][k]*det(m, n-1, mats);
	s = -s;
    }
    return d;
}

main(argv : list of string)
{
    i, j, n, p : int;
    x, y, z, xbar, ybar, d, e : real;
    a := array[MAXPOW+1] of real;
    b := array[MAXPOW+1] of real;
    sx := array[2*MAXPOW+1] of real;
    sxy := array[MAXPOW+1] of real;
    xd := array[MAXPTS] of real;
    yd := array[MAXPTS] of real;
    mat : array of array of real;
    mats : array of array of array of real;
    arg : list of string;
    s : string;
    fb : ref Bufio->Iobuf = nil;
    verbose : int = 0;

    n = 0;
    p = 1;
    for (arg = tl argv; arg != nil; arg = tl arg) {
	s = hd arg;
	if (s[0] == '-') {
	    case (s[1]) {
		'd' =>
		    if(len s > 2)
				p = int s[2 : ];
		    else{
				arg = tl arg;
				p = int hd arg;
		    }
		'0' to '9' =>
		    p = int s[1 : ];
		 'v' =>
		    verbose = 1;
		* =>
		    sys->fprint(stderr, "bad option %s\n", s);
		    exit;
	    }
	}
	else {
	    fb = bufio->open(s, bufio->OREAD);
	    if (fb == nil) {
		sys->fprint(stderr, "cannot open %s\n", s);
		exit;
	    }
	}
    }
    if (fb == nil)
	fb = bufio->open("/dev/cons", bufio->OREAD);
    if (fb == nil) {
	sys->fprint(stderr, "missing data file name\n");
	exit;
    }
    while (1) {
	xs := bufio->fb.gett(" \t\r\n");
	if (xs == nil)
	    break;
	ys := bufio->fb.gett(" \t\r\n");
	if (ys == nil) {
		sys->fprint(stderr, "missing value\n");
		exit;
	}
	if (n >= MAXPTS) {
	    sys->fprint(stderr, "too many points\n");
	    exit;
	}
	xd[n] = real xs;
	yd[n] = real ys;
	n++;
    }
    if (p < 0) {
	sys->fprint(stderr, "negative power\n");
	exit;
    }
    if (p > MAXPOW) {
	sys->fprint(stderr, "power too large\n");
	exit;
    }
    if (n < p+1) {
	sys->fprint(stderr, "not enough points\n");
	exit;
    }
    # use x-xbar, y-ybar to avoid overflow
    for (i = 0; i <= p; i++)
	sxy[i] = 0.0;
    for (i = 0; i <= 2*p; i++)
	sx[i] = 0.0;
    xbar = ybar = 0.0;
    for (i = 0; i < n; i++) {
        x = xd[i];
        y = yd[i];
        xbar += x;
        ybar += y;
    }
    xbar = xbar/(real n);
    ybar = ybar/(real n);
    for (i = 0; i < n; i++) {
	x = xd[i]-xbar;
	y = yd[i]-ybar;
	for (j = 0; j <= p; j++)
	    sxy[j] += y*power(x, j);
	for (j = 0; j <= 2*p; j++)
	    sx[j] += power(x, j);
    }
    mats = matsalloc(p+1);
    mat = mats[p+1];
    for (i = 0; i <= p; i++) {
	for (j = 0; j <= p; j++) {
	    mat[i][j] = sx[i+j];
	}
    }
    d = det(mat, p+1, mats);
    if (isn(d, 0)) {
	sys->fprint(stderr, "points not independent\n");
	exit;
    }
    for (j = 0; j <= p; j++) {
	for (i = 0; i <= p; i++)
	    mat[i][j] = sxy[i];
	a[j] = det(mat, p+1, mats)/d;
	for (i = 0; i <= p; i++)
	    mat[i][j] = sx[i+j];
    }
    if (verbose)
        sys->print("\npt	actual x	actual y	predicted y\n");
    e = 0.0;
    for (i = 0; i < n; i++) {
	x = xd[i]-xbar;
	y = yd[i]-ybar;
	z = 0.0;
	for (j = 0; j <= p; j++)
	    z += a[j]*power(x, j);
	z += ybar;
	e += (z-yd[i])*(z-yd[i]);
        	if (verbose)
	    sys->print("%d.	%f	%f	%f\n", i+1, xd[i], yd[i], z);
    }
    if (verbose)
         sys->print("root mean squared error = %f\n", maths->sqrt(e/(real n)));
    for (i = 0; i <= p; i++)
	b[i] = 0.0;
    b[0] += ybar;
    for (i = 0; i <= p; i++)
	for (j = 0; j <= i; j++)
	    b[j] += a[i]*comb(i, j)*power(-xbar, i-j);
    pr := 0;
    sys->print("y = ");
    for (i = p; i >= 0; i--) {
	if (!isn(b[i], 0) || (i == 0 && pr == 0)) {
	    if (b[i] < 0.0) {
		sys->print("-");
		b[i] = -b[i];
	    }
	    else if (pr)
		sys->print("+");
	    pr = 1;
	    if (i == 0)
		sys->print("%f", b[i]);
	    else {
	        if (!isn(b[i], 1))
	             sys->print("%f*", b[i]);
                 sys->print("x");
	        if (i > 1)
		   sys->print("^%d", i);
 	    }
	}
    }
    sys->print("\n");
}
