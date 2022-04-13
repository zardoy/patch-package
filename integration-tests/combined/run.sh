#! /usr/bin/env bash

set -e

#enable_debug=true; set -x
enable_debug=false; set +x

#test_script="$1"
test_script_list="$@"
# test/patch-parse-failure.sh

# FIXME test/shrinkwrap.sh
#    Patch file: patches/left-pad+1.1.3.patch
#    Patch was made for version: 1.1.3
#    Installed version: 1.1.1


# FIXME
cat >/dev/null <<EOF
EOF

# test
test_script_list=$(cat <<'EOF'
test/ignore-whitespace.sh.FIXME
test/shrinkwrap.sh.FIXME
test/dev-only-patches.sh.FIXME
test/patch-parse-failure.sh
test/broken-patch-file.sh
test/fails-when-no-package.sh
test/custom-resolutions.sh
test/collate-errors.sh
test/no-symbolic-links.sh
test/error-on-fail.sh
test/custom-patch-dir.sh
test/delete-scripts.sh
test/ignores-scripts-when-making-patch.sh
test/adding-and-deleting-files.sh
test/create-issue.sh
test/scoped-package.sh
test/package-gets-updated.sh
test/happy-path-npm.sh
test/happy-path-yarn.sh
test/unexpected-patch-creation-failure.sh
test/delete-old-patch-files.sh
test/lerna-canary.sh
test/nested-packages.sh
test/file-mode-changes.sh
test/nested-scoped-packages.sh
test/include-exclude-regex-relativity.sh
test/yarn-workspaces.sh
test/reverse-option.sh
test/include-exclude-paths.sh
EOF
)

function pkg_jq() {
  # yes i know sponge. this is portable
  cat package.json | jq "$@" >package.json.1
  mv package.json.1 package.json
}

if $enable_debug; then
function debug() {
  echo "  $(tput setaf 8)$@$(tput sgr0)"
}
else
function debug(){ :; }
fi

if $enable_debug; then
function echo_on(){ :; }
function echo_off(){ :; }
else
# https://stackoverflow.com/questions/17840322/how-to-undo-exec-dev-null-in-bash
function echo_on() {
  exec 1>&5
  exec 1>&6
}

function echo_off() {
  # TODO write to logfile instead of /dev/null -> help to debug
  exec 5>&1 1>/dev/null
  exec 6>&2 2>/dev/null
}
fi
# color demo:
# for n in $(seq 0 16); do printf "$(tput setaf $n)$n$(tput sgr0) "; done; echo
# 7 = light gray
# 8 = dark gray



for test_script in $test_script_list
do

#echo "$(tput setaf 6)TEST$(tput sgr0) $test_script" # cyan
echo "$(tput setaf 11)TEST$(tput sgr0) $test_script" # yellow

if (echo "$test_script" | grep -q '\.FIXME$')
then
  echo "  skip"
  echo
  continue
fi

work_dir=work

[ -e "$test_script" ] || {
  echo "no such file: $test_script" >&2
  exit 1
}

test_name="$(basename "$test_script" .sh)"

test_script="$(readlink -f "$test_script")" # absolute path
test_script_base="${test_script%.*}"

patches_src="$(readlink -f "../$test_name/patches")"

test_src="$(readlink -f "../$test_name")"

[ -d snapshot ] || mkdir snapshot
snapshot_dir="$(readlink -f snapshot)"

snapshot_index=-1

function expect_error() {
  echo_on
  expect_return "!=0" "$@"
  echo_off
}

function expect_ok() {
  echo_on
  expect_return "==0" "$@"
  echo_off
}

function expect_return() {
  snapshot_index=$((snapshot_index + 1))
  local rc_condition="$1"
  shift
  local name="$1"
  shift
  git add . >/dev/null
  git commit -m 'before expect_error' >/dev/null || true
  local rc=0
  debug "exec: $*"
  out=$("$@" 2>&1) || rc=$? # https://stackoverflow.com/questions/18621990
  debug "rc = $rc"
  if (( "$rc" $rc_condition ))
  then
    # passed the rc check
    echo "  $(tput setaf 2)PASS$(tput sgr0) $name ($rc $rc_condition)"
    git add . >/dev/null
    git commit -m 'after expect_error' >/dev/null || true
    #shot="$snapshot_dir/$test_name/$snapshot_index.txt"
    #shot="$test_script_base.out-$snapshot_index.txt"

    # cleanup snapshot
    # # generated by patch-package 0.0.0 on 2022-04-13 20:43:55
    # FIXME: patch-package should have a "timeless" option (both CLI and env) -> all times are unix zero = 1970-01-01 00:00:00
    out="$(echo "$out" | sed -E 's/^# generated by patch-package 0.0.0 on [0-9 :-]+$/# generated by patch-package 0.0.0 on 1970-01-01 00:00:00/')"
    shot="$test_script.$snapshot_index.txt"
    debug "using snapshot file: $shot"
    # to update a snapshot, delete the old snapshot file
    if [ -e "$shot" ]; then
      debug comparing snapshot
      if diff -u --color "$shot" <(echo "$out") # returns 0 if equal, print diff if not equal
      then
        echo "  $(tput setaf 2)PASS$(tput sgr0) $name (snapshot)"
      else
        echo "  $(tput setaf 1)FAIL$(tput sgr0) $name (snapshot)"
        return 1
      fi
    else
      debug writing snapshot
      [ -d "$snapshot_dir/$test_name" ] || mkdir -v -p "$snapshot_dir/$test_name"
      echo "    writing snapshot $(basename "$shot")"
      echo "$out" >"$shot"
    fi
    return 0
  else
    # fail
    git add . >/dev/null
    git commit -m 'after expect_error' >/dev/null || true
    echo "  $(tput setaf 1)FAIL$(tput sgr0) $name. actual $rc vs expected $rc_condition"
    if [ "$rc" = 127 ]; then
      echo  "internal error? rc=$rc can mean: command not found. maybe you forgot 'npx' before the command? command was: $*"
    fi
    echo "out: $out"
    # TODO expected $out
    return 1
  fi
}

git_main_branch=main

(
cd "$work_dir"
git checkout --force $git_main_branch >/dev/null 2>&1 || true
git reset --hard >/dev/null
git clean --force -d # remove empty untraced directories https://stackoverflow.com/questions/28565473/git-clean-removes-empty-directories

# FIXME in rare cases, this fails to delete the branch
#git branch -D $test_name >/dev/null 2>&1 || true
debug "delete branch, try 1"
git branch -D $test_name >/dev/null 2>&1 || true # debug
debug "delete branch, try 2"
git branch -D $test_name >/dev/null 2>&1 || true # debug

# FIXME this fails in rare cases. bug in git?
debug "create branch"
git branch $test_name >/dev/null
debug "switch branch"
git switch $test_name >/dev/null 2>&1

if [ -d "$patches_src" ]; then
  debug "copying patches for this test:"
  (
    # debug
    cd "$test_src"
    find patches/ -type f | while read f; do debug "  $f"; done
  )
  cp -r "$patches_src" .
fi

git add . >/dev/null
git commit -m before >/dev/null || true



# prepare

export CI=true # needed so patch-package returns 1 on error
# see shouldExitWithError in applyPatches.ts
# see run-tests.sh
# FIXME? patch-package should always return 1 on error
# tests:
# test/fails-when-no-package.sh
# test/broken-patch-file.sh
# ...

export NODE_ENV="" # test/error-on-fail.sh sets NODE_ENV="development"



# run

# set argv. $1 == $test_src
set -- "$test_src"

debug "writing logfile $test_script.log"
debug "sourcing $test_script ..."
echo_off
source "$test_script"
echo_on
debug "sourcing $test_script done"

git add . >/dev/null
git commit -m after >/dev/null || true

# TODO
)

echo # empty line after each test

done

echo "$(tput setaf 2)PASS ALL$(tput sgr0)"

