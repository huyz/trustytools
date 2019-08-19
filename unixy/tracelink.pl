#!/usr/bin/perl -w
# $RCSfile: sl,v $ $Revision: 1.27 $ $Date: 2003/11/20 12:01:29 $

=head1 NAME

tracelink - expand symbolic link

=head1 SYNOPSIS

    tracelink [-p] paths...

=head1 DESCRIPTION

B<sl> expands the symbolic links along the specified paths in
a visually helpful way.
For example,

sl /ug/drop
 1: /UG/drop
 2: B</net/envy/root/mnt/scsi_3/mis/ug>/DROP
 3: B</UG/mnt/scsi_3/mis/drop>
 4: B</net/envy/root/mnt/scsi_3/mis/ug>/mnt/SCSI_3/mis/drop
 -> B</net/envy/root/mnt/scsi_3>/mis/drop

What is shown in uppercase in the above example would be displayed
in reverse mode on your terminal given the proper capabilities.
These parts indicate the symbolic links that are expanded into
the emboldened path of the following line.

The symbolic link expansions are numbered to help in not exceeding
your system limit on the number of symbolic links.

The B<-p> option will display the permissions and ownerships of each
part of each path.

=head1 BUGS

Tell me about 'em.

=head1 AUTHOR

Juice Teen

=cut

$lastindent = "";

# Usage
if (!@ARGV || @ARGV == 1 && $ARGV[0] =~ /^-[hp]$/) {
  print STDERR "Usage: " . (split('/', $0))[-1] . " [-p] [filenames ...]\n" .
               "       -p will display the permissions along the expansion\n";
  exit 1;
}
($perm, $lastindent) = (shift, "    ") if $ARGV[0] eq "-p";

# Get escape sequences for this terminal
$tput = -x "/usr/bin/tput" ? "/usr/bin/tput" : "/usr/5bin/tput";
$BOLD       = `$tput bold`;
$STANDOUT   = `$tput smso`;
$PLAIN      = `$tput sgr0`;
@ESCSEQ = ($BOLD, $STANDOUT, $PLAIN);
$ESCSEQ  = "(?:" . join ('|', map { $_ = "\Q$_\E" } grep($_, @ESCSEQ)) . ")";

# Get rid of "." and ".." in a row when appropriate and reprint the path.
# Eliminates duplicate '/'s in a row.
# Also, prints out the permissions
sub simplify_and_perms($$)
{
  my $simplified;
  # Eliminate duplicate '/'s in a row
  $simplified = 1 if $_[0] =~ s,//+,/,g;
  # Eliminate "." when appropriate.
  while ($_[0] =~ s@(/|^)($ESCSEQ*)\.($ESCSEQ*)(/|$)
                   @ # don't want to erase both '/'
                     ($1 && $4 ? '/' : '') . "$2$3"
                   @ex) {
    $simplified = 1;
  }
  # Eliminate ".." when appropriate.
  # My most complicated regular expression yet!
  while ($_[0] =~ s@(^|/)($ESCSEQ*)         # can be preceded by esc-seq
                    (?!$ESCSEQ)             # cannot be escape sequence
                    (?:[^/]                 # can be a single char
                      |(?!\.\.)[^/]{2}      # cannot be ..
                      |[^/]{3,}             # can be 3 or more chars
                    )($ESCSEQ*)             # can be followed by esc-seq
                    /($ESCSEQ*)\.\.($ESCSEQ*)(/|$)
                   @ ($1 && $6 ? '/' : '') . "$2$3$4$5"
                   @ex) {
    $simplified = 1;
  }
  # Don't know if this is necessary, but it might be
  $_[0] = "/" unless $_[0];

  print "$lastindent$_[0]\n" if $simplified;

  # print out permissions
  if ($permout) {
    print $permout;
    $permout = "";
  }
}

# Print out the symlink with the counter
sub printout($)
{
  printf "%2d: $_[0]\n", ++$num;
  $lastindent = "    ";
  simplify_and_perms $_[0], 1;
}

# Displays the permission/and ownerships of the given file
sub perm($)
{
  if ($perm) {
    my ($m, $uid, $gid) = (stat $_[0])[2,4,5];
    $permout .= "$lastindent " .
      # first letter
      (-l $_[0] ? 'l' : -d _ ? 'd' : -b _ ? 'b' : -c _ ? 'c' : -p _ ? 'p' :
       -S _ ? 's' : '-') .
      # user
      ($m & 0400 ? 'r' : '-') .
      ($m & 0200 ? 'w' : '-') .
      ($m & 0100 ? ($m & 04000 ? 's' : 'x') :
                   ($m & 04000 ? 'S' : '-')) .
      # group
      ($m & 0040 ? 'r' : '-') .
      ($m & 0020 ? 'w' : '-') .
      ($m & 0010 ? ($m & 02000 ? 's' : 'x') :
                   ($m & 02000 ? 'S' : '-')) .
      # other
      ($m & 0004 ? 'r' : '-') .
      ($m & 0002 ? 'w' : '-') .
      ($m & 0001 ? ($m & 01000 ? 't' : 'x') :
                   ($m & 01000 ? 'T' : '-'));
    $permout .= sprintf(" %-9s%-9s $_[0]" . (-l _ ? " -> " . $link : '') . "\n",
      (($a = (getpwuid($uid))[0]) ? $a : $uid),
      (($b = (getgrgid($gid))[0]) ? $b : $gid));
  }
}

# Change to the specified directory;
# if cannot, print out the path so far.
sub cd($)
{
  perm $_[0];
  if (!chdir $_[0]) {
    printout "$path$pt" .
      ($_[0] eq '/' ? '/' : '') .
      (@path ? '/' . join ('/', @path) : '');
    print "error: can't access directory $_[0]\n$!\n\n";
    next ARG;
  }
}

$lastindent = "    " if @ARGV > 1;

# Record the current path
use Cwd;
$cwd = cwd();

# For each given argument
ARG: while (@ARGV) {
  $path = shift @ARGV;
  next if !$path;
  $num = 0;

  # Until the path hasn't been fully expanded
  LINK: {
    chdir $cwd || die "error: can't access directory $cwd; $!\n" if $cwd;
    @path = split('/', $path);
    $path = "";

    # Absolute directory
    $path[0] =~ s,^($ESCSEQ*)$,/$1,g;

    # For every part of the path
    while (@path) {
      $pt = shift @path;
      # $part will be $pt without escape sequences
      ($part = $pt) =~ s/$ESCSEQ//g;

      # Absolute directory
      if ($part eq "/") {
        $part = "";
        $pt =~ s,/,,;
        cd "/";
      # Current directory
      } elsif ($part eq "." || $part eq "") {
      # Parent directory
      } elsif ($part eq "..") {
        cd $part;
      # Normal directory or symbolic link
      } else {
        # Non-existent whatever
        if (!-e $part && !-l $part) {
          printout "$path$pt" .
            (@path ? '/' . join ('/', @path) : '');
          print STDERR "error: $part does not exist\n\n";
          next ARG;
        }

        # If symbolic link
        if ($link = readlink $part) {
          # Print out the symlink's permissions
          perm $part;

          # Prepare the rest of the path
          $tail = (@path ? '/' . join ('/', @path) : '');

          # Print out line
          $p = "$path$STANDOUT$pt$PLAIN";
          if ("$path$pt" =~ /\Q$BOLD/ && "$path$pt" !~ /\Q$BOLD\E.*\Q$PLAIN/) {
            $p .= $BOLD;
          }
          $p .= $tail;
          printout $p;

          # Update path
          if (substr($link, 0, 1) eq '/') {
            $path = "$BOLD$link$PLAIN";
            $tail = substr($tail, 1) if $link eq '/';
          } else {
            $path =~ s/$ESCSEQ//g;
            $path .= "$BOLD$link$PLAIN";
          }
          $path .= $tail;

          # Jump back for another round of expansion
          redo LINK;

        # If regular directory
        } else {
          cd $part if -d $part && @path;
        }
      }

      # Update the current path expansion so far traversed
      $path .= $pt;
      $path .= '/' if @path;
    }
  }

  # Print the expanded path and its simplifications
  perm "$part";
  print +($num ? " -> " : $lastindent) . "$path\n";
  simplify_and_perms $path, 0;

  # Reset the current working directory
  print "\n" if @ARGV;
}
