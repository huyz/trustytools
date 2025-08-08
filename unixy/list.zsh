#!/bin/sh
# $RCSfile: list,v $ $Revision: 1.62 $ $Date: 2011/05/20 04:15:50 $
# Depending on the extension of the arguments, runs them through the
# approriate filters and then through less.
# Has minimal support for less flags.
# ALERT! we don't have a cleanup trap.
# TODO: this should be rewritten to handle a .mailcap file

[ "x$ZSH_VERSION" = "x" ] && exec zsh -f "$0" "$@"

local DEBUG=

local _LESS _lessargs filename command i

### For security, all temp files will be unreadable

# NOTE: this will affect the permissions of files created from within
# the pager (less)
umask 077

### Modify LESS args

# We want to remove the e option, because we don't want to exit until 'q'
# is hit.
_LESS="`echo \"$LESS\" | sed 's/e//'`"

# -r option is to display raw characters, e.g. bold in man pages.
# ALERT! screen display might be messed up (like man page says),
# e.g. long lines might be split in the wrong place
_LESS="${_LESS}r"

### Wrapper for commands that don't take standard input

_wrap_stdin()
{
  # NOTE: We need a suffix for the 'co' command; specifically, we need .html
  # as the suffix for 'links'
  # NOTE: mktemp is more portable (OSX) than tempfile
  #local tmpfile=`tempfile -d ${TMPDIR:-/tmp} -p .lis. -s .html`
  local tmpfile=`mktemp -t .list.XXXXXX`
  echo -n "cat > $tmpfile; ln -s $tmpfile $tmpfile.html; ( "

  local i
  for i in "$@"; do
    echo -n "$i $tmpfile; "
  done

  echo -n "rm -f $tmpfile $tmpfile.html) "
}

# XXX Doesn't work (certainly gzip/co don't like it.  Haven't tried it with
# others).  Need to fix the "rm"
_fifo_stdin()
{
  # NOTE: We need a suffix for the 'co' command; specifically, we need .html
  # as the suffix for 'links'
  local tmpfile="${TMP-/tmp}/.list.$$.html"
  echo -n "cat | ( mkfifo $tmpfile; cat > $tmpfile & ); ( "

  local i
  for i in "$@"; do
    echo -n "$i $tmpfile; "
  done

  echo -n "rm -f $tmpfile ) "
}

### Run commands based on output of "file"

_process_by_content()
{
  case "`file -Lb \"$1\" 2>&1`" in
    *executable*)
      file -Lb "$1"
      echo ""
      nm -s -l "$1"
      ;;
    *)
      cat "$1"
      ;;
  esac
}

### Process

if [[ $# -eq 0 ]]; then
  echo "Usage: ${0##*/} file..."
  return 1
fi

for i in "$@"; do
  # Args to pass to less
  if [[ "$i" = -* ]]; then
    _lessargs="$_lessargs $i"

  # Filename
  else
    command=
    filename="$i"

    # Shortcuts (for commands that perform faster if not through standard input)
    case "$filename" in
      *.zip) command='unzip -l "$filename" |' ;;
    esac

    if [[ -n "$command" ]]; then
      [[ -n $DEBUG ]] && echo "Command=LESS=\"$_LESS\" $command less $_lessargs"
      eval "LESS=\"$_LESS\" $command less $_lessargs"
      continue
    fi

    command="<'$i' "

    # Go through all the filename extensions
    while true; do
      case "$filename" in
        # Source control
        *,v) command="$command `_wrap_stdin 'co -x.html -p'` |" ;;

        # Encryption
        *.3des|*.gpg)
          command="$command gpg -d |"
          # Workaround coz we can't see the prompt
          echo "Enter GPG passphrase: "
          ;;

        # Compression and archival
        *.pgp) command="$command pgp -f |" ;;
        *.tgz) command="$command gunzip -c | tar -tvf - |"; break ;;
        *.tbz|*.tbz2) command="$command bunzip2 -c | tar -tvf - |"; break ;;
        *.tx) command="$command unxz -c | tar -tvf - |"; break ;;
        *.gz|*.z|*.Z) command="$command gunzip -c |" ;;
        *.bz2) command="$command bunzip2 -c |" ;;
        *.xz) command="$command unxz -c |" ;;
        # Ignore zeros so we can list concatenated tar files
        *.tar) command="$command tar -tvf - --ignore-zeros |"; break ;;
        *.jar|*.war|*.ear)
          command="$command `_wrap_stdin 'jar -tvf'` |"
          break
          ;;
        *.zip) command="$command `_wrap_stdin 'unzip -l'` |"; break ;;
        *.rar) command="$command `_wrap_stdin 'unrar l'` |"; break ;;

        # Text files
        *.rtx) command="$command richtext |" ;;
        *.htm|*.html|*.shtml)
          command="$command showhtml"
          [[ -n $DEBUG ]] && echo "Command=$command"
          eval $command
          continue 2
          ;;

        # Proprietary documents
        *.doc)
          command="$command showword"
          [[ -n $DEBUG ]] && echo "Command=$command"
          eval $command
          continue 2
          ;;
        *.xls)
          command="$command showexcel"
          [[ -n $DEBUG ]] && echo "Command=$command"
          eval $command
          continue 2
          ;;
        *.ppt)
          command="$command showppt"
          [[ -n $DEBUG ]] && echo "Command=$command"
          eval $command
          continue 2
          ;;
        *.pdf)
          command="$command `_wrap_stdin 'showpdf'` |"
          break
          ;;
        *.ps)
          command="$command `_wrap_stdin 'showps'` |"
          break
          ;;

        # Man pages -- NOTE: can't have *.o cuz that's ambiguous
        *.[0-9lnp]|*.man)
          # Filename has to be something like *.1 or *.1.gz or *.1.Z
          # except when the filename contains ".man"
          if [[ "$filename" = *.man ||
                "$i" = "$filename" || "$i" = $filename.(gz|Z) ]]; then
            # Other suggested methods
            #SGI: neqn | tbl | nroff -man | less
            #zsh: nroff -man -Tman | less -s
            command="$command tbl -TX | nroff -man | col |"
          else
            break
          fi
          ;;
        *.(pm|pod)) command="$command `_wrap_stdin perldoc` |" ;;

        # Object files
        *.a|*.o) command="$command `_wrap_stdin 'nm -s -l'` |" ;;

        # Other
        *)
          command="$command `_wrap_stdin _process_by_content` |"
          break
          ;;
      esac
      filename="${${filename%.*}%,v}"
    done

    [[ -n $DEBUG ]] && echo "Command=LESS=\"$_LESS\" $command less $_lessargs"
    eval "LESS=\"$_LESS\" $command less $_lessargs"
  fi
done

unfunction _wrap_stdin
