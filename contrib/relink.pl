#!/usr/bin/perl
# 2011-06-03
# Source: http://cpan.perl.org/scripts/file-handling/relink

'di';
'ig00';
#
# $Header: relink,v 1.2 90/08/12 00:21:14 lwall Locked $
#
# $Log:	relink,v $
# Revision 1.2  90/08/12  00:21:14  lwall
# Manual standardization.
# 

($op = shift) || die "Usage: relink perlexpr [filenames]\n";
if (!@ARGV) {
    @ARGV = <STDIN>;
    chop(@ARGV);
}
for (@ARGV) {
    next unless -l;		# symbolic link?
    $name = $_;
    $_ = readlink($_);
    $was = $_;
    eval $op;
    die $@ if $@;
    if ($was ne $_) {
	unlink($name);
	symlink($_, $name);
    }
}
##############################################################################

	# These next few lines are legal in both Perl and nroff.

.00;			# finish .ig
 
'di			\" finish diversion--previous line must be blank
.nr nl 0-1		\" fake up transition to first page again
.nr % 0			\" start at page 1
'; __END__ ############# From here on it's a standard manual page ############
.TH RELINK 1 "July 30, 1990"
.AT 3
.SH LINK
relink \- relinks multiple symbolic links
.SH SYNOPSIS
.B relink perlexpr [symlinknames]
.SH DESCRIPTION
.I Relink
relinks the symbolic links given according to the rule specified as the
first argument.
The argument is a Perl expression which is expected to modify the $_
string in Perl for at least some of the names specified.
For each symbolic link named on the command line, the Perl expression
will be executed on the contents of the symbolic link with that name.
If a given symbolic link's contents is not modified by the expression,
it will not be changed.
If a name given on the command line is not a symbolic link, it will be ignored.
If no names are given on the command line, names will be read
via standard input.
.PP
For example, to relink all symbolic links in the current directory
pointing to somewhere in X11R3 so that they point to X11R4, you might say
.nf

	relink 's/X11R3/X11R4/' *

.fi
To change all occurences of links in the system from /usr/spool to /var/spool,
you'd say
.nf

	find / -type l -print | relink 's#/usr/spool#/var/spool#'

.fi
.SH ENVIRONMENT
No environment variables are used.
.SH FILES
None.
.SH AUTHOR
Larry Wall
.SH "SEE ALSO"
ln(1)
.br
perl(1)
.SH DIAGNOSTICS
If you give an invalid Perl expression you'll get a syntax error.
.SH BUGS
.ex


