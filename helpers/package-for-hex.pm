#! /bin/bash

show_usage() {
    cat <<EOF
`basename "$0"` -- package gpb for hex.pm and upload it
Usage: `basename "$0"` [options]
Options:
    -h    Show this help
    -n    Dry-run: upload nothing: answer 'no' to the question
          on whether or not to proceed. hex.publish will show you
          the files it is about to upload.
          This will also disable the check for whether the
          version is not on n.m or n.m.x format, ie if we are
          on a non-tagged git commit.
EOF
}

dry_run=false
while getopts "hn" opt
do
    case "$opt" in
	h) show_usage; exit 0;;
	n) dry_run=true;;
    esac
done
shift $OPTIND

# we must execute from inside the gpb repo, or else the
# version retrieval will fail.
#

script_dir="$(dirname "$0")"
script_path="$(cd "$script_dir"; pwd)"
cd "$script_dir"
repo_top=$(git rev-parse --show-toplevel)
cd "$repo_top"
repo_path="$(pwd)"

d="$(mktemp -d "tmp-pkg-for-hex-XXXXXXX")"
cleanup () { /bin/rm -rf "$repo_path/$d"; }
trap 'xc=$?; cleanup; exit $xc' EXIT INT QUIT TERM

vsn="$(git describe --always --tags --match '[0-9]*.[0-9]*')"
if [ $dry_run = false ]
then
    if ! (echo "$vsn" | egrep '^[0-9]+(\.[0-9]+)*$' >/dev/null)
    then
	echo "ERROR: bad version \"$vsn\", will only publish versions" >&2
	echo "that are dotted numbers only." >&2
	echo "Aborting." >&2
	cleanup
	exit 1
    fi
fi

# Contributors are those who in one way or another
# are mentioned in the ChangeLog fiel
# (run a  too??)
contributors="$(("$script_path"/extract-contributors "$repo_top"/ChangeLog; \
                 git log --format=%an ) | \
                sort -u | \
                "$script_path"/lines-to-strlist --indent-but-first-to=19
                )"

git archive --format=tar --prefix="$d"/ HEAD | tar xf -

set -e
cd "$d"

## First some version fixup stuff.
## gpb fetches the version from the git tag.
## Include that version in the package, verbatim

## Fixup the vsn tag in the src/gpb.app.src
"$script_path"/xsillyed src/gpb.app.src key:vsn change-to:' {vsn,"'"$vsn"'"}'
## Fixup vsn substitution in include/gpb_version.hrl
"$script_path"/xsillyed rebar.config key:pre_hooks delete-paragraph
build/mk_version_hrl < include/gpb_version.hrl.in > include/gpb_version.hrl
/bin/rm include/gpb_version.hrl.in

cat >package.exs <<EOF
# -*- coding: utf-8 -*-
defmodule Gpb.Mixfile do
  use Mix.Project

  def project do
    [app: :gpb,
     version: "$vsn",
     description: description,
     package: package,
     deps: deps]
  end

  defp deps do
    []
  end

  defp description do
    "A compiler for Google protocol buffer definitions files for Erlang."
  end

  defp package do
    [files: ~w(src include descr_src COPYING.LIB README.* rebar.config ChangeLog Makefile),
     contributors: $contributors,
     licenses: ["LGPL 2.1"],
     links: %{"GitHub" => "https://github.com/tomas-abrahamsson/gpb"}]
   end
end

EOF

if [ $dry_run = true ]
then
    cat -n package.exs
    echo
fi
if [ $dry_run = true ]
then
    echo no | (LC_ALL=en_US.utf-8 MIX_EXS=package.exs mix hex.publish)
    echo "(answered no)"
else
    (LC_ALL=en_US.utf-8 MIX_EXS=package.exs mix hex.publish)
fi

/bin/rm -rf 
