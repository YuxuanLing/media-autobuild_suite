#!/bin/bash
# shellcheck disable=SC2154,SC2120,SC2119,SC2034,SC1090,SC1117,SC2030,SC2031
#source /local64/etc/profile2.local
source ./media-suite_helper.sh

do_simple_print "Hello world !"
:<<!
do_wget \
            -h ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e \
            "http://10.1.1.43:8001/archive/lame-3.100.tar.gz"
!
			
RUSTUP_HOME="/opt/cargo"	
CARCH=x86_64
## do_rust




# get wget download
do_wget_test() {
    local nocd=false norm=false quiet=false notmodified=false hash
    while true; do
        case $1 in
        -c) nocd=true && shift ;;
        -r) norm=true && shift ;;
        -q) quiet=true && shift ;;
        -h) hash="$2" && shift 2 ;;
        -z) notmodified=true && shift ;;
        --)
            shift
            break
            ;;
        *) break ;;
        esac
    done
    local url="$1" archive="$2" dirName="$3" response_code=000 curlcmds=("${curl_opts[@]}") tries=1 temp_file
    if [[ -z $archive ]]; then
        # remove arguments and filepath
        archive=${url%%\?*}
        archive=${archive##*/}
    fi
    if [[ -f $url ]]; then
	    cp -f "$url" "$PWD"/"$patchName"
        return 1
    fi
    archive=${archive:-"$(/usr/bin/curl -sI "$url" | grep -Eo 'filename=.*$' | sed 's/filename=//')"}
    [[ -z $dirName ]] && dirName=$(guess_dirname "$archive")

    $nocd || cd_safe "$LOCALBUILDDIR"
    $notmodified && [[ -f $archive ]] && curlcmds+=(-z "$archive" -R)
    [[ $hash ]] && tries=3

    if [[ -f $archive ]] && [[ $hash ]] && check_hash "$archive" "$hash"; then
        $quiet || do_print_status prefix "${bold}├${reset} " "${dirName:-$archive}" "$green" "File up-to-date"
        tries=0
    fi

    while [[ $tries -gt 0 ]]; do
        temp_file=$(mktemp)
        response_code=$("${curlcmds[@]}" -w "%{http_code}" -o "$temp_file" "$url")

        if [[ -f $archive ]] && diff -q "$archive" "$temp_file" > /dev/null 2>&1; then
            $quiet || do_print_status prefix "${bold}├${reset} " "${dirName:-$archive}" "$green" "File up-to-date"
            rm -f "$temp_file"
            break
        fi

        ((tries -= 1))

        case $response_code in
        2**)
            $quiet || do_print_status "┌ ${dirName:-$archive}" "$orange" "Downloaded"
            check_hash "$temp_file" "$hash" && cp -f "$temp_file" "$archive"
            rm -f "$temp_file"
            break
            ;;
        304)
            $quiet || do_print_status "┌ ${dirName:-$archive}" "$orange" "File up-to-date"
            rm -f "$temp_file"
            break
            ;;
        esac

        if check_hash "$archive" "$hash"; then
            printf '%b\n' "${orange}${archive}${reset}" \
                '\tFile not found online. Using local copy.'
        else
            do_print_status "└ ${dirName:-$archive}" "$red" "Failed"
            printf '%s\n' "Error $response_code while downloading $url" \
                "<Ctrl+c> to cancel build or <Enter> to continue"
            do_prompt "if you're sure nothing depends on it."
            rm -f "$temp_file"
            return 1
        fi
    done

    $norm || add_to_remove "$(pwd)/$archive"
    do_extract "$archive" "$dirName"
    ! $norm && [[ -n $dirName ]] && ! $nocd && add_to_remove
    [[ -z $response_code || $response_code != "304" ]] && return 0
}




do_patch_test() {
    local binarypatch="--binary"
    case $1 in -p) binarypatch="" && shift ;; esac
    local patch="${1%% *}"     # Location or link to patch.
    local patchName="${1##* }" # Basename of file. (test-diff-files.diff)
    local am=false             # Use git am to apply patch. Use with .patch files
    local strip=${3:-1}        # Leading directories to strip. "patch -p${strip}"
    [[ $patchName == "$patch" ]] && patchName="${patch##*/}"
    [[ $2 == am ]] && am=true

    # hack for URLs without filename
    patchName=${patchName:-"$(/usr/bin/curl -sI "$patch" | grep -Eo 'filename=.*$' | sed 's/filename=//')"}
    [[ -z $patchName ]] &&
        printf '%b\n' "${red}Failed to apply patch '$patch'" \
            "Patch without filename, ignoring. Specify an explicit filename.${reset}" &&
        return 1

    # Just don't. Make a fork or use the suite's directory as the root for
    # your diffs or manually edit the scripts if you are trying to modify
    # the helper and compile scripts. If you really need to, use patch instead.
    # Else create a patch file for the individual folders you want to apply
    # the patch to.
    [[ $PWD == "$LOCALBUILDDIR" ]] &&
        do_exit_prompt "Running patches in the build folder is not supported.
        Please make a patch for individual folders or modify the script directly"

    # Filter out patches that would require curl; else
    # check if the patch is a local patch and copy it to the current dir
	printf "patch and patchName $patch  $patchName \n"
	##ret=$(do_wget_test -c -r -q "$patch" "$patchName")
	##printf "ret = $ret \n"
    if ! do_wget_test -c -r -q "$patch" "$patchName" && [[ -f $patch ]]; then
        patch="$(
            cd_safe "$(dirname "$patch")"
            printf '%s' "$(pwd -P)" '/' "$(basename -- "$patch")"

        )" # Resolve fullpath
		printf "local path $patch  $patchName $PWD \n"
        ##[[ ${patch%/*} != "$PWD" ]] && cp -f "$patch" "$patchName" > /dev/null 2>&1
    fi

    if [[ -f $patchName ]]; then
        if $am; then
            do_simple_print "Success am!" && return 0
        else
            do_simple_print "Success not am!" && return 0
        fi
        printf '%b\n' "${orange}${patchName}${reset}" \
            '\tPatch could not be applied with `'"$($am && echo "git am" || echo "patch")"'`. Continuing without patching.'
    else
        printf '%b\n' "${orange}${patchName}${reset}" \
            '\tPatch not found anywhere. Continuing without patching.'
    fi
    return 1
}


do_patch_test "/d/work/ffmpeg_build_windows/patches/libtiff.git/233.patch" am
pause 'Compile finish, Press [Enter] key to exit...'

:<<!
url="https://github.com/upx/upx/releases/download/v3.96/upx-3.96-win32.zip"
if [[ -f $url ]]; then
   printf "$url file exist \n"
else
   printf "$url file Not exist \n"
fi
!

		