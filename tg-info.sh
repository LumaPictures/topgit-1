#!/bin/sh
# TopGit - A different patch queue manager
# Copyright (C) Petr Baudis <pasky@suse.cz>  2008
# Copyright (C) Kyle J. McKay <mackyle@gmail.com>  2015, 2016, 2017
# GPLv2

USAGE="Usage: ${tgname:-tg} [...] info [--heads | --leaves] [<name>]"

usage()
{
	if [ "${1:-0}" != 0 ]; then
		printf '%s\n' "$USAGE" >&2
	else
		printf '%s\n' "$USAGE"
	fi
	exit ${1:-0}
}

## Parse options

heads=
leaves=

while [ $# -gt 0 ]; do case "$1" in
	-h|--help)
		usage
		;;
	--heads)
		heads=1
		;;
	--leaves)
		leaves=1
		;;
	-?*)
		echo "Unknown option: $1" >&2
		usage 1
		;;
	*)
		break
		;;
esac; shift; done
[ "$heads$leaves" != "11" ] || die "mutually exclusive options --heads and --leaves"
[ $# -gt 0 ] || set -- HEAD
[ $# -eq 1 ] || die "name already specified ($1)"
name="$1"

# true if $1 is an ancestor of (or the same as) $2 
is_ancestor()
{
	[ "$(git rev-list --count --max-count=1 "$1" --not "$2" --)" = "0" ]
}

if [ -n "$heads" ]; then
	verify="$name"
	! test="$(verify_topgit_branch "${name:-HEAD}" -f)" || verify="refs/heads/$test"
	hash="$(git rev-parse --verify --quiet "$verify" --)" || die "no such ref: $name"
	$tg summary --tgish-only --heads |
	while read -r head; do
		if is_ancestor "$hash" "refs/heads/$head"; then
			printf '%s\n' "$head"
		fi
	done
	exit 0
fi

name="$(verify_topgit_branch "${name:-HEAD}")"
if [ -n "$leaves" ]; then
	find_leaves "$name"
	exit 0
fi
base_rev="$(git rev-parse --short --verify "refs/$topbases/$name" -- 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

measure="$(measure_branch "refs/heads/$name" "$base_rev")"

echo "Topic Branch: $name ($measure)"
if [ "$(git rev-parse --verify --short "refs/heads/$name" --)" = "$base_rev" ]; then
	echo "* No commits."
	exit 0
fi

git cat-file blob "$name:.topmsg" | grep ^Subject: || :

echo "Base: $base_rev"
branch_contains "refs/heads/$name" "refs/$topbases/$name" ||
	echo "* Base is newer than head! Please run \`$tgdisplay update\`."

if has_remote "$name"; then
	echo "Remote Mate: $base_remote/$name"
	branch_contains "refs/$topbases/$name" "refs/remotes/$base_remote/${topbases#heads/}/$name" ||
		echo "* Local base is out of date wrt. the remote base."
	branch_contains "refs/heads/$name" "refs/remotes/$base_remote/$name" ||
		echo "* Local head is out of date wrt. the remote head."
	branch_contains "refs/remotes/$base_remote/$name" "refs/heads/$name" ||
		echo "* Local head is ahead of the remote head."
fi

git cat-file blob "$name:.topdeps" 2>/dev/null |
	sed '1{ s/^/Depends: /; n; }; s/^/         /;'

depcheck="$(get_temp tg-depcheck)"
missing_deps=
needs_update "$name" >"$depcheck" || :
if [ -n "$missing_deps" ]; then
	echo "MISSING: $missing_deps"
fi
depcheck2="$(get_temp tg-depcheck2)"
sed '/^!/d' <"$depcheck" >"$depcheck2"
if [ -s "$depcheck2" ]; then
	echo "Needs update from:"
	# 's/ [^ ]* *$//' -- last is $name
	# 's/^[:] /:/'    -- don't distinguish base updates
	<"$depcheck2" sed -e 's/ [^ ]* *$//' -e 's/^[:] /:/' |
		while read dep chain; do
			case "$dep" in
				:*)
					dep="${dep#:}"
					fulldep="refs/heads/$dep"
					extradep="refs/$topbases/$dep"
					;;
				*)
					extradep=
					case "$dep" in
						refs/*)
							fulldep="$dep";;
						*)
							fulldep="refs/heads/$dep";;
					esac
					;;
			esac
			printf '%s' "$dep "
			[ -n "$chain" ] && printf '%s' "(<= $(echol "$chain" | sed 's/ / <= /')) "
			printf '%s' "($(eval measure_branch '"$fulldep"' '"refs/heads/$name"' ${extradep:+\"\$extradep\"}))"
			echo
		done | sed 's/^/	/'
else
	echo "Up-to-date${missing_deps:+ (except for missing dependencies)}."
fi

# vim:noet
