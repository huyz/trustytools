#!/usr/bin/env perl
# Filename:         untar.pl
# Version:          0.1
# Description:
#   Extracts all or specific files from within a tar archive that's possibly
#   compressed and/or encrypted.  Files can be filtered at the command-line
#   and/or interactively.
#   Supports compress, gzip, bzip2, xz, gpg, pgp
#
# Source:           https://github.com/huyz/trustytools
# Author:           Huy Z, http://huyz.us/
# Updated on:       2011-06-03
# Created on:       1995-08-10
#
#
# Usage:
#    untar [options] archive [pattern...]
#
#  Options:
#    -i : filter interactively
#    -s : use substring pattern (instead of perl5 regular expression)
#    -q : run in quiet mode
#
#  Depending on extensions in filenames, different utilities will be invoked:
#    *.(tgz|gz|z|Z): decompress using gzip
#    *.(tbz|bz2|tbz|bz): decompress using bzip2
#    *.(tx|xz): decompress using unxz
#    *.gpg: decrypt using gpg
#    *.pgp: decrypt using pgp

# Copyright (C) 2011 Huy Z
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use v5.6.0;

### Modules & pragmas

our $DEBUG;

use warnings;
use strict;

use Getopt::Long 2.19;
use vars qw( $opt_interactive $opt_substring $opt_quiet );

#############################################################################
##### Configuration

# NOTE: see under "Build command" section for all program paths.

my $TAR = "tar";
my $STD_TARFLAGS = "p";

##### End of Configuration
#############################################################################

### Init

$| = 1;
umask 000;
my $argv0 = ( split( '/', $0 ) )[-1];

### Usage

sub usage
{
  print STDERR "Usage: $argv0 [options] archive [pattern...]

  Options:
    -i : filter interactively
    -s : use substring pattern (instead of perl5 regular expression)
    -q : run in quiet mode

  Depending on extensions in filenames, different utilities will be invoked:
    *.(tgz|gz|z|Z): decompress using gzip
    *.(tbz|bz2|tbz|bz): decompress using bzip2
    *.(tx|xz): decompress using unxz
    *.gpg: decrypt using gpg
    *.pgp: decrypt using pgp
";
  exit 1;
}

### Get options and arguments

GetOptions(
  "i" => \$opt_interactive,
  "s" => \$opt_substring,
  "q" => \$opt_quiet ) or usage();

usage() unless @ARGV >= 1;

my $archive = shift @ARGV;

# Substring search
@ARGV = map { quotemeta $_ } @ARGV if $opt_substring;

# When interactive, default regular expression is "match anything"
# so that user is prompted for every single filename
if ( $opt_interactive && ! @ARGV )
{
  @ARGV = ( '.' );
}

### Build command

my $arcname = $archive;
my $command = "<$archive ";

while ( 1 )
{
  # NOTE: 3des is my own non-standard extension
  if ( $arcname =~ /\.(gpg|3des)$/ )
  {
    $command .= "gpg -d | ";
  }
  elsif ( $arcname =~ /\.pgp$/ )
  {
    $command .= "pgp -f | ";
  }
  elsif ( $arcname =~ /\.(gz|z|Z)$/ )
  {
    $command .= "gunzip -c | ";
  }
  elsif ( $arcname =~ /\.tgz$/ )
  {
    $command .= "gunzip -c | ";
    last;
  }
  elsif ( $arcname =~ /\.bz2?$/ )
  {
    $command .= "bunzip2 -c | ";
  }
  elsif ( $arcname =~ /\.tbz2?$/ )
  {
    $command .= "bunzip2 -c | ";
  }
  elsif ( $arcname =~ /\.xz$/ )
  {
    $command .= "unxz -c | ";
  }
  elsif ( $arcname =~ /\.tx$/ )
  {
    $command .= "unxz -c | ";
  }
  else
  {
    last;
  }

  # Remove extension
  $arcname =~ s/\.[^\.]+$//;
}

#############################################################################

# List of filenames to put on the command line.
my @files;
my @dirs;
my $count = 0;

### Function to add to file list

# Adds files only if their parent directory hasn't been selected.
# Keeps track of directories.
sub add
{
  my $file = $_[0];

  # Add the given file to the file list, unless the user
  # has already asked to extract an ancestor directory already
  # (otherwise that would be redundant)
  push( @files, $file ) unless grep( $file =~ /^$_/, @dirs );

  # If the filename ends in '/', then let's remember it 
  if( $file =~ m,/$, )
  {
    push( @dirs, $file )
  }
  # If this is not a directory, add to the count
  else
  {
    $count++;
  }
}

### Build file list

# List the archive and prompt the user, if applicable
if ( $opt_interactive || @ARGV )
{
  my $resp = "";
  my $def_resp = "n";
  my $search;

  # NOTE: the parentheses are used to hide the '<' from perl
  # so that it only sees the '|'
  my $cmd = "($command $TAR -tf -)";
  open( LIST, "$cmd |" ) or die "ERROR: $argv0: can't run command '$cmd'\n$!\n";

  while ( <LIST> )
  {
    my $file = $_;
    chomp( $file );

    s/\s+symbolic link.*$//; # Remove some tars' crap

    # Filter out filenames via the specified patterns, if applicable
    for my $expr ( @ARGV )
    {
      if ( /$expr/ )
      {
        # If not interactive, add the file
        if ( ! $opt_interactive )
        {
          add( $file );
        }
        # Interactive
        else
        {
          RESPONSE:
          {
            print "$file? ";

            # Ancestor directory already selected
            if ( grep( $file =~ /^$_/, @dirs ) )
            {
              print "...already included\n";
            }
            # Previous command was "search":
            # we're in the middle of a search and this file doesn't match.
            elsif ( $resp =~ m,^/, && ! /$search/ )
            {
              print "...skipping\n";
            }
            else
            {
              $search = "";

              # Previous command was a "exclude rest"
              if ( $resp =~ /^N/ )
              {
                print "...no way\n";
              }
              else
              {
                # Previous command was a "include rest"
                if ( $resp =~ /^Y/ )
                {
                  print "...hell yeah\n";
                }
                # Get a new response from user
                else
                {
                  print "yYnN/qh [$def_resp] ";
                  chomp( $resp = <STDIN> );
                  $resp =~ s/\r$//;
                  $resp =~ s/^\s*//;
                  if( $resp )
                  {
                    $def_resp = $resp;
                  }
                  else
                  {
                    $resp = $def_resp;
                  }
                }

                # Quit out
                if ( $resp =~ /^[Qq]/ )
                {
                  exit 0;
                }
                # Include
                elsif ( $resp =~ /^[Yy]/ )
                {
                  add( $file );
                }
                # Prepare for searching
                elsif ( $resp =~ m,^/(.*)$, )
                {
                  $search = $1;
                }
                # Help
                elsif ( $resp !~ /^[Nn]/ )
                {
                  print <<"";
   y        : include
   Y        : include rest
   n        : exclude
   N        : exclude rest
   /pattern : goto next file that matches pattern
   q        : quit
   help     : help

                  redo RESPONSE;
                }
              }
            }
          }
        }
      }
    }
  }

  close LIST;

  print "$count files selected.\n";

  # Format file lists
  if( @files )
  {
    # Quote sh characters, special within double-quotes
    map { s/([\\`"\$])/\\$1/g; $_ = "\"$_\"" } @files;
  }
  # Quit if no files selected
  else
  {
    exit;
  }

  print "\n";
}

### Perform unarchival

if ( ! $opt_interactive || @files )
{
  if( ! $opt_quiet )
  {
    $STD_TARFLAGS .= "v";
  }

  # Run command
  my $cmd = "$command $TAR -x${STD_TARFLAGS}f - " . join( ' ', @files );
  print "$cmd" if $DEBUG;
  exec $cmd or die "error: can't run command '$cmd'\n$!\n";
}
