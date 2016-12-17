# Test framework from Git with modifications.
#
# Modifications Copyright (C) 2016 Kyle J. McKay
# Modifications made:
#
#  * Many "GIT_..." variables removed -- some were kept as TESTLIB_..." instead
#    (Except "GIT_PATH" is new and is the full path to a "git" executable)
#
#  * IMPORTANT: test-lib-main.sh SHOULD NOT EXECUTE ANY CODE!  A new
#    function "test_lib_main_init" has been added that will be called
#    and MUST contain any lines of code to be executed.  This will ALWAYS
#    be the LAST function defined in this file for easy locatability.
#
#  * Added cmd_path, fatal, whats_my_dir, vcmp, test_possibly_broken_ok_ and
#    test_possibly_broken_failure_ functions
#
#  * Anything related to valgrind or perf has been stripped out
#
#  * Many other minor changes
#
# Copyright (C) 2005 Junio C Hamano
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/ .

#
## IMPORTANT:  THIS FILE MUST NOT CONTAIN ANYTHING OTHER THAN FUNCTION
##             DEFINITION!!!  INITIALIZATION GOES IN THE LAST FUNCTION
##             DEFINED IN THIS FILE "test_lib_main_init" AS REQUIRED!
#

cmd_path() (
	{ "unset" -f command unset unalias "$1"; } >/dev/null 2>&1 || :
	{ "unalias" -a; } >/dev/null 2>&1 || :
	command -v "$1"
)

fatal() {
	printf '%s\n' "$*" >&2
	TESTLIB_EXIT_OK=1
	exit 1
}

whats_my_dir() (
	# determine script's location and name
	myname="$0"
	while [ -L "$myname" ]; do
		oldname="$myname"
		myname="$(readlink "$myname")"
		case "$myname" in /*) :;; *)
			myname="$(dirname "$oldname")/$myname"
		esac
	done
	mydir="$(cd "$(dirname "$myname")" && pwd -P)"
	printf '%s\n' "$mydir"
)

vcmp() (
	# Compare $1 to $2 each of which must match \d+(\.\d+)*
	# An empty string ('') for $1 or $2 is treated like 0
	# Outputs:
	#  -1 if $1 < $2
	#   0 if $1 = $2
	#   1 if $1 > $2
	# Note that $(vcmp 1.8 1.8.0.0.0.0) correctly outputs 0.
	while
		_a="${1%%.*}"
		_b="${2%%.*}"
		[ -n "$_a" -o -n "$_b" ]
	do
		if [ "${_a:-0}" -lt "${_b:-0}" ]; then
			echo -1
			return
		elif [ "${_a:-0}" -gt "${_b:-0}" ]; then
			echo 1
			return
		fi
		_a2="${1#$_a}"
		_b2="${2#$_b}"
		set -- "${_a2#.}" "${_b2#.}"
	done
	echo 0
)

error() {
	say_color error "error: $*"
	TESTLIB_EXIT_OK=t
	exit 1
}

say() {
	say_color info "$*"
}

die() {
	code=$?
	if test -n "$TESTLIB_EXIT_OK"
	then
		exit $code
	else
		echo >&5 "FATAL: Unexpected exit with code $code"
		exit 1
	fi
}

# You are not expected to call test_ok_ and test_failure_ directly, use
# the test_expect_* functions instead.

test_ok_() {
	test_success=$(($test_success + 1))
	say_color "" "ok $test_count - $@"
}

test_failure_() {
	test_failure=$(($test_failure + 1))
	say_color error "not ok $test_count - $1"
	shift
	printf '%s\n' "$*" | sed -e 's/^/#	/'
	test "$immediate" = "" || { TESTLIB_EXIT_OK=t; exit 1; }
}

test_known_broken_ok_() {
	test_fixed=$(($test_fixed + 1))
	say_color error "ok $test_count - $@ # TODO known breakage vanished"
}

test_known_broken_failure_() {
	test_broken=$(($test_broken + 1))
	say_color warn "not ok $test_count - $@ # TODO known breakage"
}

test_possibly_broken_ok_() {
	test_success=$(($test_success + 1))
	say_color "" "ok $test_count - $@"
}

test_possibly_broken_failure_() {
	test_broken=$(($test_broken + 1))
	say_color warn "not ok $test_count - $@ # TODO tolerated breakage"
}

test_debug() {
	test "$debug" = "" || test $# -eq 0 || test -z "$*" || "$@"
}

match_pattern_list() {
	arg="$1"
	shift
	test -z "$*" && return 1
	for pattern_
	do
		case "$arg" in
		$pattern_)
			return 0
		esac
	done
	return 1
}

match_test_selector_list() {
	title="$1"
	shift
	arg="$1"
	shift
	test -z "$1" && return 0

	# Both commas and whitespace are accepted as separators.
	OLDIFS=$IFS
	IFS=' 	,'
	set -- $1
	IFS=$OLDIFS

	# If the first selector is negative we include by default.
	include=
	case "$1" in
		!*) include=t ;;
	esac

	for selector
	do
		orig_selector=$selector

		positive=t
		case "$selector" in
			!*)
				positive=
				selector=${selector##?}
				;;
		esac

		test -z "$selector" && continue

		case "$selector" in
			*-*)
				if x_="${selector%%-*}" && test "z$x_" != "z${x_#*[!0-9]}"
				then
					echo "error: $title: invalid non-numeric in range" \
						"start: '$orig_selector'" >&2
					exit 1
				fi
				if x_="${selector#*-}" && test "z$x_" != "z${x_#*[!0-9]}"
				then
					echo "error: $title: invalid non-numeric in range" \
						"end: '$orig_selector'" >&2
					exit 1
				fi
				unset x_
				;;
			*)
				if test "z$selector" != "z${selector#*[!0-9]}"
				then
					echo "error: $title: invalid non-numeric in test" \
						"selector: '$orig_selector'" >&2
					exit 1
				fi
		esac

		# Short cut for "obvious" cases
		test -z "$include" && test -z "$positive" && continue
		test -n "$include" && test -n "$positive" && continue

		case "$selector" in
			-*)
				if test $arg -le ${selector#-}
				then
					include=$positive
				fi
				;;
			*-)
				if test $arg -ge ${selector%-}
				then
					include=$positive
				fi
				;;
			*-*)
				if test ${selector%%-*} -le $arg \
					&& test $arg -le ${selector#*-}
				then
					include=$positive
				fi
				;;
			*)
				if test $arg -eq $selector
				then
					include=$positive
				fi
				;;
		esac
	done

	test -n "$include"
}

maybe_teardown_verbose() {
	test -z "$verbose_only" && return
	exec 4>/dev/null 3>/dev/null
	verbose=
}

maybe_setup_verbose() {
	test -z "$verbose_only" && return
	if match_pattern_list $test_count $verbose_only
	then
		exec 4>&2 3>&1
		# Emit a delimiting blank line when going from
		# non-verbose to verbose.  Within verbose mode the
		# delimiter is printed by test_expect_*.  The choice
		# of the initial $last_verbose is such that before
		# test 1, we do not print it.
		test -z "$last_verbose" && echo >&3 ""
		verbose=t
	else
		exec 4>/dev/null 3>/dev/null
		verbose=
	fi
	last_verbose=$verbose
}

want_trace() {
	test "$trace" = t && test "$verbose" = t
}

# This is a separate function because some tests use
# "return" to end a test_expect_success block early
# (and we want to make sure we run any cleanup like
# "set +x").
test_eval_inner_() {
	# Do not add anything extra (including LF) after '$*'
	eval "
		want_trace && set -x
		$*"
}

test_eval_() {
	# We run this block with stderr redirected to avoid extra cruft
	# during a "-x" trace. Once in "set -x" mode, we cannot prevent
	# the shell from printing the "set +x" to turn it off (nor the saving
	# of $? before that). But we can make sure that the output goes to
	# /dev/null.
	#
	# The test itself is run with stderr put back to &4 (so either to
	# /dev/null, or to the original stderr if --verbose was used).
	{
		test_eval_inner_ "$@" </dev/null >&3 2>&4
		test_eval_ret_=$?
		if want_trace
		then
			set +x
			if test "$test_eval_ret_" != 0
			then
				say_color error >&4 "error: last command exited with \$?=$test_eval_ret_"
			fi
		fi
	} 2>/dev/null
	return $test_eval_ret_
}

test_run_() {
	test_cleanup=:
	expecting_failure=$2

	if test "${TESTLIB_TEST_CHAIN_LINT:-1}" != 0; then
		# turn off tracing for this test-eval, as it simply creates
		# confusing noise in the "-x" output
		trace_tmp=$trace
		trace=
		# 117 is magic because it is unlikely to match the exit
		# code of other programs
		test_eval_ "(exit 117) && $1"
		if test "$?" != 117; then
			error "bug in the test script: broken &&-chain: $1"
		fi
		trace=$trace_tmp
	fi

	test_eval_ "$1"
	eval_ret=$?

	if test -z "$immediate" || test $eval_ret = 0 ||
	   test -n "$expecting_failure" && test "${test_cleanup:-:}" != ":"
	then
		test_eval_ "$test_cleanup"
	fi
	if test "$verbose" = "t" && test -n "$HARNESS_ACTIVE"
	then
		echo ""
	fi
	return "$eval_ret"
}

test_start_() {
	test_count=$(($test_count+1))
	maybe_setup_verbose
}

test_finish_() {
	echo >&3 ""
	maybe_teardown_verbose
}

test_skip() {
	to_skip=
	skipped_reason=
	if match_pattern_list $this_test.$test_count $TESTLIB_SKIP_TESTS
	then
		to_skip=t
		skipped_reason="TESTLIB_SKIP_TESTS"
	fi
	if test -z "$to_skip" && test -n "$test_prereq" &&
	   ! test_have_prereq "$test_prereq"
	then
		to_skip=t

		of_prereq=
		if test "$missing_prereq" != "$test_prereq"
		then
			of_prereq=" of $test_prereq"
		fi
		skipped_reason="missing $missing_prereq${of_prereq}"
	fi
	if test -z "$to_skip" && test -n "$run_list" &&
		! match_test_selector_list '--run' $test_count "$run_list"
	then
		to_skip=t
		skipped_reason="--run"
	fi

	case "$to_skip" in
	t)
		say_color skip >&3 "skipping test: $@"
		say_color skip "ok $test_count # skip $1 ($skipped_reason)"
		: true
		;;
	*)
		false
		;;
	esac
}

# stub; runs at end of each successful test
test_at_end_hook_() {
	:
}

test_done() {
	TESTLIB_EXIT_OK=t

	if test -z "$HARNESS_ACTIVE"
	then
		test_results_dir="$TEST_OUTPUT_DIRECTORY/test-results"
		mkdir -p "$test_results_dir"
		base=${0##*/}
		test_results_path="$test_results_dir/${base%.sh}.counts"

		cat >"$test_results_path" <<-EOF
		total $test_count
		success $test_success
		fixed $test_fixed
		broken $test_broken
		failed $test_failure

		EOF
	fi

	if test "$test_fixed" != 0
	then
		say_color error "# $test_fixed known breakage(s) vanished; please update test(s)"
	fi
	if test "$test_broken" != 0
	then
		say_color warn "# still have $test_broken known breakage(s)"
	fi
	if test "$test_broken" != 0 || test "$test_fixed" != 0
	then
		test_remaining=$(( $test_count - $test_broken - $test_fixed ))
		msg="remaining $test_remaining test(s)"
	else
		test_remaining=$test_count
		msg="$test_count test(s)"
	fi
	case "$test_failure" in
	0)
		# Maybe print SKIP message
		if test -n "$skip_all" && test $test_count -gt 0
		then
			error "Can't use skip_all after running some tests"
		fi
		test -z "$skip_all" || skip_all=" # SKIP $skip_all"

		if test $test_external_has_tap -eq 0
		then
			if test $test_remaining -gt 0
			then
				say_color pass "# passed all $msg"
			fi
			say "1..$test_count$skip_all"
		fi

		test -d "$remove_trash" &&
		cd "$(dirname "$remove_trash")" &&
		rm -rf "$(basename "$remove_trash")"

		test_at_end_hook_

		exit 0 ;;

	*)
		if test $test_external_has_tap -eq 0
		then
			say_color error "# failed $test_failure among $msg"
			say "1..$test_count"
		fi

		exit 1 ;;

	esac
}

# Provide an implementation of the 'yes' utility
yes() {
	if test $# = 0
	then
		y=y
	else
		y="$*"
	fi

	i=0
	while test $i -lt 99
	do
		echo "$y"
		i=$(($i+1))
	done
}

run_with_limited_cmdline() {
	(ulimit -s 128 && "$@")
}


#
## Note that the following functions have bodies that are NOT indented
## to assist with readability
#


# This function is called with all the test args and must perform all
# initialization that involves variables and is not specific to "$0"
# or "$test_description" in any way.  This function may only be called
# once per run of the entire test suite.
test_lib_main_init_generic() {
# Begin test_lib_main_init_generic


! [ -f ../TG-BUILD-SETTINGS ] || . ../TG-BUILD-SETTINGS
! [ -f TG-TEST-SETTINGS ] || . ./TG-TEST-SETTINGS

: "${SHELL_PATH:=/bin/sh}"
: "${DIFF:=diff}"
: "${GIT_PATH:=$(cmd_path git)}"
: "${PERL_PATH:=$(cmd_path perl || :)}"
TESTLIB_DIRECTORY="$(whats_my_dir)"

# Test the binaries we have just built.  The tests are kept in
# t/ subdirectory and are run in 'trash directory' subdirectory.
if test -z "$TEST_DIRECTORY"
then
	# We allow tests to override this, in case they want to run tests
	# outside of t/, e.g. for running tests on the test library
	# itself.
	TEST_DIRECTORY="$TESTLIB_DIRECTORY"
else
	# ensure that TEST_DIRECTORY is an absolute path so that it
	# is valid even if the current working directory is changed
	TEST_DIRECTORY="$(cd "$TEST_DIRECTORY" && pwd)" || exit 1
fi
if test -z "$TEST_OUTPUT_DIRECTORY"
then
	# Similarly, override this to store the test-results subdir
	# elsewhere
	TEST_OUTPUT_DIRECTORY="$TEST_DIRECTORY"
fi
[ -d "$TESTLIB_DIRECTORY"/empty ] || {
	mkdir "$TESTLIB_DIRECTORY/empty"
	chmod a-w "$TESTLIB_DIRECTORY/empty"
}
EMPTY_DIRECTORY="$TESTLIB_DIRECTORY/empty"

################################################################
# It appears that people try to run tests with missing perl or git...
git_version="$("$GIT_PATH" --version 2>&1)" ||
	fatal 'error: you do not seem to have git available?'
case "$git_version" in [Gg][Ii][Tt]\ [Vv][Ee][Rr][Ss][Ii][Oo][Nn]\ [0-9]*) :;; *)
	fatal "error: git --version returned bogus value: $git_version"
esac
#"$PERL_PATH" --version >/dev/null 2>&1 ||
#	fatal 'error: you do not seem to have perl available?'

# if --tee was passed, write the output not only to the terminal, but
# additionally to the file test-results/$BASENAME.out, too.
case "$TESTLIB_TEST_TEE_STARTED, $* " in
done,*)
	# do not redirect again
	;;
*' --tee '*|*' --verbose-log '*)
	mkdir -p "$TEST_OUTPUT_DIRECTORY/test-results"
	BASE="$TEST_OUTPUT_DIRECTORY/test-results/$(basename "$0" .sh)"

	# Make this filename available to the sub-process in case it is using
	# --verbose-log.
	TESTLIB_TEST_TEE_OUTPUT_FILE=$BASE.out
	export TESTLIB_TEST_TEE_OUTPUT_FILE

	# Truncate before calling "tee -a" to get rid of the results
	# from any previous runs.
	>"$TESTLIB_TEST_TEE_OUTPUT_FILE"

	(TESTLIB_TEST_TEE_STARTED=done ${SHELL_PATH} "$0" "$@" 2>&1;
	 echo $? >"$BASE.exit") | tee -a "$TESTLIB_TEST_TEE_OUTPUT_FILE"
	test "$(cat "$BASE.exit")" = 0
	exit
	;;
esac

# For repeatability, reset the environment to known value.
# TERM is sanitized below, after saving color control sequences.
LANG=C
LC_ALL=C
PAGER=cat
TZ=UTC
export LANG LC_ALL PAGER TZ
EDITOR=:
# A call to "unset" with no arguments causes at least Solaris 10
# /usr/xpg4/bin/sh and /bin/ksh to bail out.  So keep the unsets
# deriving from the command substitution clustered with the other
# ones.
unset VISUAL EMAIL LANGUAGE COLUMNS $("$PERL_PATH" -e '
	my @env = keys %ENV;
	my $ok = join("|", qw(
		TRACE
		DEBUG
		USE_LOOKUP
		TEST
		.*_TEST
		MINIMUM_VERSION
		PATH
		PROVE
		UNZIP
		PERF_
		CURL_VERBOSE
		TRACE_CURL
	));
	my @vars = grep(/^GIT_/ && !/^GIT_($ok)/o, @env);
	print join("\n", @vars);
')
unset XDG_CONFIG_HOME
unset GITPERLLIB
GIT_AUTHOR_NAME='Te s t'
GIT_AUTHOR_EMAIL=test@example.net
GIT_COMMITTER_NAME='Fra mewor k'
GIT_COMMITTER_EMAIL=framework@example.org
GIT_MERGE_VERBOSITY=5
GIT_MERGE_AUTOEDIT=no
GIT_TEMPLATE_DIR="$EMPTY_DIRECTORY"
GIT_CONFIG_NOSYSTEM=1
GIT_ATTR_NOSYSTEM=1
export PATH GIT_TEMPLATE_DIR GIT_CONFIG_NOSYSTEM GIT_ATTR_NOSYSTEM
export GIT_MERGE_VERBOSITY GIT_MERGE_AUTOEDIT
export GIT_AUTHOR_EMAIL GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL GIT_COMMITTER_NAME
export EDITOR

# Tests using GIT_TRACE typically don't want <timestamp> <file>:<line> output
GIT_TRACE_BARE=1
export GIT_TRACE_BARE

# Protect ourselves from common misconfiguration to export
# CDPATH into the environment
unset CDPATH

unset GREP_OPTIONS
unset UNZIP

case $(echo $GIT_TRACE |tr "[A-Z]" "[a-z]") in
1|2|true)
	GIT_TRACE=4
	;;
esac

# Convenience
#
# A regexp to match 5 and 40 hexdigits
_x05='[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'
_x40="$_x05$_x05$_x05$_x05$_x05$_x05$_x05$_x05"

# Zero SHA-1
_z40=0000000000000000000000000000000000000000

EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
EMPTY_BLOB=e69de29bb2d1d6434b8b29ae775ad8c2e48c5391

# Line feed
LF='
'

# UTF-8 ZERO WIDTH NON-JOINER, which HFS+ ignores
# when case-folding filenames
u200c=$(printf '\342\200\214')

export _x05 _x40 _z40 LF u200c EMPTY_TREE EMPTY_BLOB

while test "$#" -ne 0
do
	case "$1" in
	-d|--d|--de|--deb|--debu|--debug)
		debug=t; shift ;;
	-i|--i|--im|--imm|--imme|--immed|--immedi|--immedia|--immediat|--immediate)
		immediate=t; shift ;;
	-l|--l|--lo|--lon|--long|--long-|--long-t|--long-te|--long-tes|--long-test|--long-tests)
		TESTLIB_TEST_LONG=t; export TESTLIB_TEST_LONG; shift ;;
	-r)
		shift; test "$#" -ne 0 || {
			echo 'error: -r requires an argument' >&2;
			exit 1;
		}
		run_list=$1; shift ;;
	--run=*)
		run_list=${1#--*=}; shift ;;
	-h|--h|--he|--hel|--help)
		help=t; shift ;;
	-v|--v|--ve|--ver|--verb|--verbo|--verbos|--verbose)
		verbose=t; shift ;;
	--verbose-only=*)
		verbose_only=${1#--*=}
		shift ;;
	-q|--q|--qu|--qui|--quie|--quiet)
		# Ignore --quiet under a TAP::Harness. Saying how many tests
		# passed without the ok/not ok details is always an error.
		test -z "$HARNESS_ACTIVE" && quiet=t; shift ;;
	--no-color)
		color=; shift ;;
	--tee)
		shift ;; # was handled already
	--root=*)
		root=${1#--*=}
		shift ;;
	--chain-lint)
		TESTLIB_TEST_CHAIN_LINT=1
		shift ;;
	--no-chain-lint)
		TESTLIB_TEST_CHAIN_LINT=0
		shift ;;
	-x)
		trace=t
		verbose=t
		shift ;;
	--verbose-log)
		verbose_log=t
		shift ;;
	*)
		echo "error: unknown test option '$1'" >&2; exit 1 ;;
	esac
done

test "x${color+set}" != "xset" &&
test "x$TERM" != "xdumb" && (
		{ test -n "$TESTLIB_FORCETTY" || test -t 1; } &&
		tput bold >/dev/null 2>&1 &&
		tput setaf 1 >/dev/null 2>&1 &&
		tput sgr0 >/dev/null 2>&1
	) &&
	color=t
if test -n "$color"
then
	# Save the color control sequences now rather than run tput
	# each time say_color() is called.  This is done for two
	# reasons:
	#   * TERM will be changed to dumb
	#   * HOME will be changed to a temporary directory and tput
	#     might need to read ~/.terminfo from the original HOME
	#     directory to get the control sequences
	# Note:  This approach assumes the control sequences don't end
	# in a newline for any terminal of interest (command
	# substitutions strip trailing newlines).  Given that most
	# (all?) terminals in common use are related to ECMA-48, this
	# shouldn't be a problem.
	say_color_error=$(tput bold; tput setaf 1) # bold red
	say_color_skip=$(tput setaf 4) # blue
	say_color_warn=$(tput setaf 3) # brown/yellow
	say_color_pass=$(tput setaf 2) # green
	say_color_info=$(tput setaf 6) # cyan
	say_color_reset=$(tput sgr0)
	say_color_="" # no formatting for normal text
fi

TERM=dumb
export TERM

# Send any "-x" output directly to stderr to avoid polluting tests
# which capture stderr. We can do this unconditionally since it
# has no effect if tracing isn't turned on.
#
# Note that this sets up the trace fd as soon as we assign the variable, so it
# must come after the creation of descriptor 4 above. Likewise, we must never
# unset this, as it has the side effect of closing descriptor 4, which we
# use to show verbose tests to the user.
#
# Note also that we don't need or want to export it. The tracing is local to
# this shell, and we would not want to influence any shells we exec.
BASH_XTRACEFD=4

test_failure=0
test_count=0
test_fixed=0
test_broken=0
test_success=0

test_external_has_tap=0

# The user-facing functions are loaded from a separate file
. "$TEST_DIRECTORY/test-lib-functions.sh"
test_lib_functions_init

last_verbose=t

if [ -n "$TG_TEST_INSTALLED" ]; then
	[ -n "$(cmd_path tg || :)" ] ||
		fatal 'error: TG_TEST_INSTALLED set but no tg found in $PATH!'
else
	tg_bin_dir="$(cd "$TESTLIB_DIRECTORY/../bin-wrappers" 2>/dev/null && pwd -P || :)"
	[ -x "$tg_bin_dir/tg" ] ||
		fatal 'error: no ../bin-wrappers/tg executable found!'
	PATH="$tg_bin_dir:$PATH"
fi
tg_version="$(tg --version)" ||
	fatal 'error: tg --version failed!'
case "$tg_version" in [Tt][Oo][Pp][Gg][Ii][Tt]\ [Vv][Ee][Rr][Ss][Ii][Oo][Nn]\ [0-9]*) :;; *)
	fatal "error: tg --version returned bogus value: $tg_version"
esac

if [ -n "$GIT_MINIMUM_VERSION" ] && [ -n "$git_version" ]; then
	git_vernum="$(sed -ne '1s/^[^0-9]*\([0-9][0-9]*\(\.[0-9][0-9]*\)*\).*$/\1/p' <<-EOT
		$git_version
		EOT
		)"
	[ "$(vcmp "$git_vernum" $GIT_MINIMUM_VERSION)" -ge 0 ] ||
		fatal "git version >= $GIT_MINIMUM_VERSION required but found git version $git_vernum instead"
fi

if test -z "$TESTLIB_TEST_CMP"
then
	if test -n "$TESTLIB_TEST_CMP_USE_COPIED_CONTEXT"
	then
		TESTLIB_TEST_CMP="$DIFF -c"
	else
		TESTLIB_TEST_CMP="$DIFF -u"
	fi
fi

# Fix some commands on Windows
uname_s="$(uname -s)"
case $uname_s in
*MINGW*)
	# no POSIX permissions
	# backslashes in pathspec are converted to '/'
	# exec does not inherit the PID
	test_set_prereq MINGW
	test_set_prereq NATIVE_CRLF
	test_set_prereq SED_STRIPS_CR
	test_set_prereq GREP_STRIPS_CR
	TESTLIB_TEST_CMP=mingw_test_cmp
	;;
*CYGWIN*)
	test_set_prereq POSIXPERM
	test_set_prereq EXECKEEPSPID
	test_set_prereq CYGWIN
	test_set_prereq SED_STRIPS_CR
	test_set_prereq GREP_STRIPS_CR
	;;
*)
	test_set_prereq POSIXPERM
	test_set_prereq BSLASHPSPEC
	test_set_prereq EXECKEEPSPID
	;;
esac

( COLUMNS=1 && test $COLUMNS = 1 ) && test_set_prereq COLUMNS_CAN_BE_1

test_lazy_prereq PIPE '
	# test whether the filesystem supports FIFOs
	case "$uname_s" in
	CYGWIN*|MINGW*)
		false
		;;
	*)
		rm -f testfifo && mkfifo testfifo
		;;
	esac
'

test_lazy_prereq SYMLINKS '
	# test whether the filesystem supports symbolic links
	ln -s x y && test -h y
'

test_lazy_prereq FILEMODE '
	test "$(git config --bool core.filemode)" = true
'

test_lazy_prereq CASE_INSENSITIVE_FS '
	echo good >CamelCase &&
	echo bad >camelcase &&
	test "$(cat CamelCase)" != good
'

test_lazy_prereq UTF8_NFD_TO_NFC '
	# check whether FS converts nfd unicode to nfc
	auml=$(printf "\303\244")
	aumlcdiar=$(printf "\141\314\210")
	>"$auml" &&
	case "$(echo *)" in
	"$aumlcdiar")
		true ;;
	*)
		false ;;
	esac
'

test_lazy_prereq AUTOIDENT '
	sane_unset GIT_AUTHOR_NAME &&
	sane_unset GIT_AUTHOR_EMAIL &&
	git var GIT_AUTHOR_IDENT
'

test_lazy_prereq EXPENSIVE '
	test -n "$TESTLIB_TEST_LONG"
'

test_lazy_prereq USR_BIN_TIME '
	test -x /usr/bin/time
'

test_lazy_prereq NOT_ROOT '
	uid=$(id -u) &&
	test "$uid" != 0
'

# SANITY is about "can you correctly predict what the filesystem would
# do by only looking at the permission bits of the files and
# directories?"  A typical example of !SANITY is running the test
# suite as root, where a test may expect "chmod -r file && cat file"
# to fail because file is supposed to be unreadable after a successful
# chmod.  In an environment (i.e. combination of what filesystem is
# being used and who is running the tests) that lacks SANITY, you may
# be able to delete or create a file when the containing directory
# doesn't have write permissions, or access a file even if the
# containing directory doesn't have read or execute permissions.

test_lazy_prereq SANITY '
	mkdir SANETESTD.1 SANETESTD.2 &&

	chmod +w SANETESTD.1 SANETESTD.2 &&
	>SANETESTD.1/x 2>SANETESTD.2/x &&
	chmod -w SANETESTD.1 &&
	chmod -r SANETESTD.1/x &&
	chmod -rx SANETESTD.2 ||
	error "bug in test sript: cannot prepare SANETESTD"

	! test -r SANETESTD.1/x &&
	! rm SANETESTD.1/x && ! test -f SANETESTD.2/x
	status=$?

	chmod +rwx SANETESTD.1 SANETESTD.2 &&
	rm -rf SANETESTD.1 SANETESTD.2 ||
	error "bug in test sript: cannot clean SANETESTD"
	return $status
'

test_lazy_prereq CMDLINE_LIMIT 'run_with_limited_cmdline true'


# End test_lib_main_init_generic
}


# This function is guaranteed to always be called for every single test.
# Only put things in this function that MUST be done per-test, function
# definitions and sourcing other files generally DO NOT QUALIFY (there can
# be exceptions).
test_lib_main_init_specific() {
# Begin test_lib_main_init_specific


# Ignore --quiet under a TAP::Harness. Saying how many tests
# passed without the ok/not ok details is always an error.
test -n "$HARNESS_ACTIVE" && unset quiet

if test -n "$color"
then
	say_color() {
		test -z "$1" && test -n "$quiet" && return
		eval "say_color_color=\$say_color_$1"
		shift
		printf "%s\\n" "$say_color_color$*$say_color_reset"
	}
else
	say_color() {
		test -z "$1" && test -n "$quiet" && return
		shift
		printf "%s\n" "$*"
	}
fi

if test -n "$HARNESS_ACTIVE"
then
	if test "$verbose" = t || test -n "$verbose_only"
	then
		printf 'Bail out! %s\n' \
		 'verbose mode forbidden under TAP harness; try --verbose-log'
		exit 1
	fi
fi

test "${test_description}" != "" ||
error "Test script did not set test_description."

if test "$help" = "t"
then
	printf '%s\n' "$test_description"
	exit 0
fi

exec 5>&1
exec 6<&0
if test "$verbose_log" = "t"
then
	exec 3>>"$TESTLIB_TEST_TEE_OUTPUT_FILE" 4>&3
elif test "$verbose" = "t"
then
	exec 4>&2 3>&1
else
	exec 4>/dev/null 3>/dev/null
fi

TESTLIB_EXIT_OK=
trap 'die' EXIT
trap 'exit $?' HUP INT QUIT ABRT PIPE TERM

# Test repository
TRASH_DIRECTORY="trash directory.$(basename "$0" .sh)"
test -n "$root" && TRASH_DIRECTORY="$root/$TRASH_DIRECTORY"
case "$TRASH_DIRECTORY" in
/*) ;; # absolute path is good
 *) TRASH_DIRECTORY="$TEST_OUTPUT_DIRECTORY/$TRASH_DIRECTORY" ;;
esac
test ! -z "$debug" || remove_trash=$TRASH_DIRECTORY
! [ -e "$TRASH_DIRECTORY" ] || rm -fr "$TRASH_DIRECTORY" || {
	TESTLIB_EXIT_OK=t
	echo >&5 "FATAL: Cannot prepare test area"
	exit 1
}

HOME="$TRASH_DIRECTORY"
GNUPGHOME="$HOME/gnupg-home-not-used"
export HOME GNUPGHOME

if test -z "$TEST_NO_CREATE_REPO"
then
	test_create_repo "$TRASH_DIRECTORY"
else
	mkdir -p "$TRASH_DIRECTORY"
fi
# Use -P to resolve symlinks in our working directory so that the cwd
# in subprocesses like tg equals our $PWD (for pathname comparisons).
cd -P "$TRASH_DIRECTORY" || exit 1

this_test=${0##*/}
this_test=${this_test%%-*}
if match_pattern_list "$this_test" $TESTLIB_SKIP_TESTS
then
	say_color info >&3 "skipping test $this_test altogether"
	skip_all="skip all tests in $this_test"
	test_done
fi

# Fix some commands on Windows
case "$uname_s" in
*MINGW*)
	# Windows has its own (incompatible) sort and find
	sort() {
		/usr/bin/sort "$@"
	}
	find() {
		/usr/bin/find "$@"
	}
	sum() {
		md5sum "$@"
	}
	# git sees Windows-style pwd
	pwd() {
		builtin pwd -W
	}
	;;
esac


# End test_lib_main_init_specific
}


#
# THIS SHOULD ALWAYS BE THE LAST FUNCTION DEFINED IN THIS FILE
#
# Any client that sources this file should immediately execute this function
# afterwards with the command line arguments
#
# THERE SHOULD NOT BE ANY DIRECTLY EXECUTED LINES OF CODE IN THIS FILE
#
test_lib_main_init() {

	test_lib_main_init_generic "$@"
	test_lib_main_init_specific "$@"

}