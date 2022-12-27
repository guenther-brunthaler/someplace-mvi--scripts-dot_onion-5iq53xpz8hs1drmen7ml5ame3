#! /bin/sh
# v2022.101

set -e
cleanup() {
	rc=$?
	test "$TD" && rm -r -- "$TD"
	test $rc = 0 || echo "\"$0\" failed!" >& 2
}
trap cleanup 0
TD=
trap 'exit $?' HUP TERM INT QUIT

verbose=false
force=false
while getopts vf opt
do
	case $opt in
		f) force=true;;
		v) verbose=true;;
		*) false || exit
	esac
done
shift `expr $OPTIND - 1 || :`

TD=`mktemp -d "${TMPDIR:-/tmp}/${0##*/}".XXXXXXXXXX`

case $# in
	2) ;;
	*)
		echo "Two arguments are required (in arbitrary order):"
		echo "* Path to a directory which is part of a git checkout."
		echo "* Path to unlocked encrypted directory where"
		echo "  associated '\$unixtime-\$commit'-files are stored."
		false || exit
esac >& 2

# Strip trailing slashes from directory arguments and verify their existence.
i=$#
while :
do
	t=$1; shift
	while :
	do
		t2=${t%/}
		test "$t" = "$t2" && break
		t=$t2
	done
	test -d "$t"
	set -- "$@" "$t"
	i=`expr $i - 1` || break
done

# Identify argument order.
if (cd -- "$1" && git status > /dev/null 2>& 1)
then
		repo=$1 bndl=$2
else
		repo=$2 bndl=$1
fi

# Verify the bundle directory is indeed not (directly) a git repository.
if (cd -- "$bndl" && git status > /dev/null 2>& 1)
then
	false || exit
else
	:
fi

# Verify the git repository does not have any uncommitted changes.
test `
	cd -- "$repo" && git status -s > "$TD"/log && wc -l < "$TD"/log
` = 0 || {
	cat < "$TD"/log >& 2
	$force || {
		echo "Please commit uncommited changes in '$repo' first!" >& 2
		false || exit
	}
}

lc=`cd -- "$repo" && git log -n 1 --oneline | cut -d ' ' -f 1 | cut -c -7`
lb=`
	{ cd -- "$repo" && git cat-file -p HEAD; } \
	| awk '$1 == "committer" {print $(NF - 1); exit}'
`-$lc
case $bndl in
	/*) ;;
	*) bndl=$PWD/$bndl
esac

pull_bundles() {
	note=true
	while read b
	do
		if $note
		then
			echo "Pulling new commits from" \
				"encrypted repository..." >& 2
			note=false
		fi
		echo $b
		(cd -- "$repo" && git pull "$bndl/$b")
	done
	if $note
	then
		echo "Both sides are up to date - nothing to be done." >& 2
	fi
}

push_all_bundles() {
	cd -- "$rpo"
	echo "Pushing initial bundle '$lb'" \
		"to encrypted repository." >& 2
	git bundle create "$bndl/$lb" HEAD
}

ls -1 -- "$bndl" | sort -t - -n > "$TD"/blist
if test ! -s "$TD"/blist
then
	push_all_bundles
	exit
fi

while read b
do
	case $b in
		"$lb") pull_bundles; exit
	esac
done < "$TD"/blist

lc=`tail -n 1 < "$TD"/blist`
lc=${lc#*-}
if (cd -- "$repo" && git log -n 1 --oneline "$lc") > /dev/null 2>& 1
then
	cd -- "$repo"
	echo "Pushing new bundle '$lb'" \
		"to encrypted repository." >& 2
	git bundle create "$bndl/$lb" $lc..
else
	push_all_bundles
fi
