#!/usr/bin/env python

# $Id: mailtrim.py,v 1.1 2002/05/31 04:57:44 msoulier Exp $

"""The purpose of this script is to trim a standard Unix mbox file. If the
main function is called, it expects two parameters in argv. The first is the
number of most recent messages to keep. The second is the path to the mbox
file."""

import sys, string, os
from tempfile import mktemp
from shutil import copyfile

error = sys.stderr.write

def count_messages(file):
    """The purpose of this function is to count the messages in the mailbox,
    rewind the mailbox seek pointer, and then return the number of messages in
    the mailbox file."""
    count = 0
    while 1:
        line = file.readline()
        if not line: break
        if line[:5] == "From ":
            count = count + 1
    file.seek(0)
    return count

def trim(file, keep):
    """This purpose of this function is to perform the actual trimming of the
    mailbox file."""
    count = count_messages(file)
    print "\nThere are %d messages in the mailbox file." % count
    if count <= keep:
        print "\nThis file already contains less than the desired number of"
        print "messages. Nothing to do."
        return
    remove = count - keep
    print "\nNeed to remove %d messages..." % remove
    tempfilename = mktemp()
    tempfile = open(tempfilename, "w")
    copying = 0
    while 1:
        line = file.readline()
        if not line: break
        if line[:5] == "From ":
            if remove:
                remove = remove - 1
                continue
            else:
                copying = 1
        if not copying:
            continue
        tempfile.write(line)
    tempfile.close()
    copyfile(tempfilename, file.name)
    os.unlink(tempfilename)

def main():
    """This function expects sys.argv to be set appropriately with the
    required options, mentioned in the module's docstring. It is the entry
    point for the rest of the program."""
    if len(sys.argv) != 3:
        error("Usage: %s <number to keep> <mbox file>\n" % sys.argv[0])
        sys.exit(1)
    keep = string.atoi(sys.argv[1])
    filename = sys.argv[2]
    if not os.path.exists(filename):
        error("ERROR: File %s does not exist\n" % filename)
        sys.exit(1)
    print "Trimming %s to %d messages..." % (filename, keep)
    file = open(filename, "r")
    trim(file, keep)
    file.close()
    print "\nDone trimming %s." % filename

if __name__ == '__main__': main()
