#! /bin/sh
# v2022.30.1

enc_pfx=onion
enc_sfx=.encfs
cfg_pfx=$enc_pfx
cfg_sfx=-encfs6.xml
mnt_pfx=$enc_pfx
mnt_sfx=.mnt
pwf_pfx=$enc_pfx
pwf_sfx=.psw
pwf_tgz_gbo=passwords.tgz.gbo
gbo=gbosslcrypt

set -e
cleanup() {
	rc=$?
	test "$TD" && rm -r -- "$TD"
	test $rc = 0 || echo "\"$0\" failed!" >& 2
}
trap cleanup 0
TD=
trap 'exit $?' HUP TERM INT QUIT

unmount=false
verbose=false
while getopts uv opt
do
	case $opt in
		u) unmount=true;;
		v) verbose=true;;
		*) false || exit
	esac
done
shift `expr $OPTIND - 1 || :`

canon() {
	readlink -f -- "$1"
}

get_device() {
	stat -c '%d' "$1"
}

is_mounted() {
	test "`get_device "$1"`" != "`get_device "$1/.."`"
}

me=$0
if test ! -e "$me"
then
	me=`command -v -- "$me"`
	test -e "$me"
fi
cd -- "`dirname -- "$me"`"
test -e "`basename -- "$me"`"

L= n=1
while test -e "$cfg_pfx$n$cfg_sfx"
do
	L=$n
	n=`expr $n + 1`
done
n=$L
test "$n"

TD=`mktemp -d "${TMPDIR:-/tmp}/${0##*/}".XXXXXXXXXX`
if $unmount
then
	i=1
	while test $i -le $n
	do
		m=$mnt_pfx$i$mnt_sfx
		is_mounted "$m" || {
			echo "'$m' has not been mounted yet!" >& 2
			false || exit
		}
		encfs -u "$PWD/$m" > "$TD"/log || {
			cat < "$TD"/log >& 2
			false || exit
		}
		i=`expr $i + 1`
	done
	$verbose && echo "$n volumes have been unmounted." >& 2 || :
else

	test "$psw" || {
		echo "Export path to the password file as \$psw first!" >& 2
		false || exit
	}
	test -f "$psw"
	test -f "$pwf_tgz_gbo"
	"$gbo" -d "$psw" < "$pwf_tgz_gbo" | tar -C "$TD" -xz
	L= i=$n
	while :
	do
		m=$mnt_pfx$i$mnt_sfx
		if test ! -e "$m"
		then
			echo "Creating '$m'..." >& 2
			mkdir -m700 -- "$m"
		elif is_mounted "$m"
		then
			echo "'$m' is already mounted!" >& 2
			false || exit
		fi
		case $L in
			"") src=$enc_pfx$i$enc_sfx;;
			*) src=$mnt_pfx$L$mnt_sfx
		esac
		pwf=$TD/$pwf_pfx$i$pwf_sfx encfs \
			--extpass='tr -d "\\n" < "$pwf"' \
			-c "$cfg_pfx$i$cfg_sfx" \
			"$PWD/$src" "$PWD/$m"
		L=$i
		i=`expr $i - 1` || break
	done
	$verbose && echo "Successfully mounted $n nested volumes." >& 2 || :
fi
