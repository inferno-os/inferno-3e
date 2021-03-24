implement Converter;

# A Fahrenheit/Centigrade temperature converter
# Accepts strings of the form nC (or n C) and nF (or n F)
# where n is a number of degrees C or degrees F
# Returns a string indicating the conversion


include "string.m";
	str: String;
include "sys.m";
	sys: Sys;

include "converter_tmpl.m";


# Initialise module

init()
{
	sys = load Sys Sys->PATH;
	str = load String String->PATH;
}



# Convert a string

convert(request: string): string
{
	deg := real request;
	(trimmed, nil) := str->splitr(str->toupper(request), "^ \t\n");
	if (trimmed[len trimmed-1] == 'C')
		return sys->sprint("%.2f deg C = %.2f deg F\n", deg, 32.0 + deg * 9.0 / 5.0);
	if (trimmed[len trimmed-1] == 'F')
		return sys->sprint("%.2f deg F = %.2f deg C\n", deg, (deg-32.0) * 5.0 / 9.0);
	return "? Please specify degrees and scale, eg 100 C\n";
}
