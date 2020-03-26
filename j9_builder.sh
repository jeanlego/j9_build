#!/bin/bash

trap ctrl_c INT

ctrl_c() {
        pkill "$0"
}

ARGS_IN=( "$@" )

## Returns errlvl 0 if $1 is a reachable git remote url 
reachable_host() {
        ping -c2 -W2 -q "$1" &> /dev/null
}

# set defaults 
[ "_${ARCH}" != "_" ]           || ARCH="$(uname -m)"
[ "_${VERSION}" != "_" ]        || VERSION="8"
[ "_${BUILD_TYPE}" != "_" ]     || BUILD_TYPE="release"

declare -A OPENJ9
declare -A OMR
declare -A GET_SOURCE
declare -A OUTPUT

declare -A COMMIT
declare -A BRANCH
declare -A REMOTE

declare -A CONFIGURE_ARGS
declare -A BUILD_ARGS
declare -A CLEAN_ARGS

j9_conf=''

source "./build.conf"
if ${J9_BUILD_READY};
then
        echo "sourced build.conf"
else
        echo "failed to source build.conf"
fi

THIS_DIR="${PWD}"
BASE_DIR="${THIS_DIR}"/j9Builds
DOWNLOADS="${BASE_DIR}"/downloads
LOGS="${BASE_DIR}"/logs
UTILS="${BASE_DIR}"/utils
BUILDER="${UTILS}"/builder
SCRIPTS="${UTILS}"/scripts

OUTPUT[get_source]="${BASE_DIR}/jdk${VERSION}"
OUTPUT[openj9]="${BASE_DIR}/openj9"
OUTPUT[omr]="${BASE_DIR}/omr"
OUTPUT[freemarker]="${DOWNLOADS}/freemarker.tgz"
OUTPUT[bootjdk]="${DOWNLOADS}/bootjdk${VERSION}_${ARCH}.tar.gz"
OUTPUT[dockerfile]="${BUILDER}/Dockerfile"
OUTPUT[watchdog]="${UTILS}/casa.watchdog.sh"
OUTPUT[xdocker]="${UTILS}/xdocker.sh"

SOURCE_FLAGS=j9.env

mkdir -p "${BASE_DIR}"
mkdir -p "${DOWNLOADS}"
mkdir -p "${UTILS}"
rm -Rf "${SCRIPTS}" && mkdir -p "${SCRIPTS}"
rm -Rf "${BUILDER}" && mkdir -p "${BUILDER}"     
rm -Rf "${LOGS}" && mkdir -p "${LOGS}"     

mkdir -p "${OUTPUT[get_source]}"
mkdir -p "${OUTPUT[openj9]}"
mkdir -p "${OUTPUT[omr]}"

[ ! -L "${OUTPUT[get_source]}/omr" ] && ln -s -t "${OUTPUT[get_source]}" "${OUTPUT[omr]}"
[ ! -L "${OUTPUT[get_source]}/openj9" ] && ln -s -t "${OUTPUT[get_source]}" "${OUTPUT[openj9]}"



print_script_env() {
        echo  "\
BUILD_TYPE=${BUILD_TYPE}
VERSION=${VERSION}
ARCH=${ARCH}
"
}

#####################
# USAGE PRINTER
usage() {

        echo \
"
$0 
Usage:
    build     [args...]    build using makefile
    configure [args...]    trigger a configure
    clean     [args...]    clean the build
"
exit "$1"
}

die() {
        echo "\
 == ERROR: $2
you called this program with \"${ARGS_IN[*]}\" 
"
print_script_env

        usage "$1"
}

create_sh() {
        name="${LOGS}/${FUNCNAME[1]}"
        script_name="${SCRIPTS}/${FUNCNAME[1]}.sh"
        script_log="${name}.progress"
        script_fail="${name}.failure"
        script_pass="${name}.success"

        echo "Making ${script_name}"
        echo "\
#!/bin/bash
rm -f ${name}* || /bin/true

if
(
        set -xe
        $* 
) > ${script_log} 2>&1
then 
        echo finished ${FUNCNAME[1]}
        mv ${script_log} ${script_pass}
        exit 0
else
        mv ${script_log} ${script_fail}
        echo failed ${FUNCNAME[1]}
        exit 1
fi
" > "${script_name}"
        chmod +x "${script_name}"
}

create_docker_sh() {
        name="${LOGS}/${FUNCNAME[1]}"
        script_name="${OUTPUT[get_source]}/${FUNCNAME[1]}.sh"
        script_log="${name}.progress"
        script_fail="${name}.failure"
        script_pass="${name}.success"

        echo "Making ${script_name}"
        echo "\
#!/bin/bash
rm -f ${name}* || /bin/true

if
(
        set -xe
        $* 
) | tee ${script_log} 2>&1
then 
        echo finished ${FUNCNAME[1]}
        mv ${script_log} ${script_pass}
        exit 0
else
        mv ${script_log} ${script_fail}
        echo failed ${FUNCNAME[1]}
        exit 1
fi
" > "${script_name}"
        chmod +x "${script_name}"
}

generic_git_cmd='
        if [ ! -f "${DIR}/.git" ]; then
                git -C "${DIR}" init
        fi
        
        # clean the remotes
        git -C "${DIR}" remote | xargs -n 1 -I{} git -C "${DIR}" remote remove {}

        # update the remotes
        for ((i=0; i<${#REMOTE_URLS[@]}; i++)); do
                git -C "${DIR}" remote add "${REMOTE_NAMES[$i]}" "${REMOTE_URLS[$i]}"
        done

        git -C "${DIR}" fetch --progress "${REMOTE}" "${BRANCH}"
        if [ "_$(git -C "${DIR}" rev-parse --abbrev-ref HEAD)" != "_${BRANCH}" ]; then
                git -C "${DIR}" checkout --progress -b "${BRANCH}" "${REMOTE}/${BRANCH}"
        fi
        if [[ ! -z "${COMMIT}" ]]; then
                git -C "${DIR}" reset --hard "${COMMIT}"
        fi
'

generic_curl_cmd='
        if [ ! -f "${OUTPUT}" ]; then
                curl -L --output "${OUTPUT}" "${URL}"
        fi
'

get_source_jdk() {
        create_sh "
        REMOTE_NAMES=( ${!GET_SOURCE[@]} )
        REMOTE_URLS=( ${GET_SOURCE[@]} )
        DIR=\"${OUTPUT[get_source]}\"
        COMMIT=\"${COMMIT[get_source]}\"
        BRANCH=\"${BRANCH[get_source]}\"
        REMOTE=\"${REMOTE[get_source]}\"
        ${generic_git_cmd}
        chmod +x ${OUTPUT[get_source]}/configure;
"
}

get_omr() {
        create_sh "
        REMOTE_NAMES=( ${!OMR[@]} )
        REMOTE_URLS=( ${OMR[@]} )
        DIR=\"${OUTPUT[omr]}\"
        COMMIT=\"${COMMIT[omr]}\"
        BRANCH=\"${BRANCH[omr]}\"
        REMOTE=\"${REMOTE[omr]}\"
        ${generic_git_cmd}
"
}

get_openj9() {
        
        create_sh "
        REMOTE_NAMES=( ${!OPENJ9[@]} )
        REMOTE_URLS=( ${OPENJ9[@]} )
        DIR=\"${OUTPUT[openj9]}\"
        COMMIT=\"${COMMIT[openj9]}\"
        BRANCH=\"${BRANCH[openj9]}\"
        REMOTE=\"${REMOTE[openj9]}\"
        ${generic_git_cmd}
"
}

get_freemarker() {

        create_sh  "
        URL=\"${REMOTE[freemarker]}\"
        OUTPUT=\"${OUTPUT[freemarker]}\"
        ${generic_curl_cmd}
        if [ ! -f ${UTILS}/freemarker.jar ]; then
                tar -C ${UTILS} -xzf ${OUTPUT[freemarker]} freemarker-2.3.8/lib/freemarker.jar --strip=2 \\
                        || rm ${OUTPUT[freemarker]} # download again if it can't extract
        fi
        "
}

get_bootjdk() {
        create_sh "
        URL=\"${REMOTE[bootjdk]}\"
        OUTPUT=\"${OUTPUT[bootjdk]}\"
        ${generic_curl_cmd}
        if [ ! -d ${UTILS}/bootjdk${VERSION}_${ARCH} ]; then
                mkdir ${DOWNLOADS}/scratch
                tar -xzf ${OUTPUT[bootjdk]} -C ${DOWNLOADS}/scratch \\
                        || rm ${OUTPUT[bootjdk]} # download again if it can't extract
                mv ${DOWNLOADS}/scratch/* ${UTILS}/bootjdk${VERSION}_${ARCH}
                rm -Rf ${DOWNLOADS}/scratch
        fi
        "
}

get_watchdog() {
        create_sh "
        URL=\"${REMOTE[watchdog]}\"
        OUTPUT=\"${OUTPUT[watchdog]}\"
        ${generic_curl_cmd}
        chmod +x ${OUTPUT[watchdog]};
        "
}

get_xdocker() {
        create_sh "
        URL=\"${REMOTE[xdocker]}\"
        OUTPUT=\"${OUTPUT[xdocker]}\"
        ${generic_curl_cmd}
        chmod +x ${OUTPUT[xdocker]};
        "
}

get_dockerfile() {
        create_sh "
        URL=\"${REMOTE[dockerfile]}\"
        OUTPUT=\"${OUTPUT[dockerfile]}\"
        ${generic_curl_cmd}
        "
}

declare -A CONFIGURE_ARGS
declare -A BUILD_ARGS
declare -A CLEAN_ARGS

do_j9() {
        echo "\
#!/bin/bash
pushd ${OUTPUT[get_source]} || exit 255
source \"${SOURCE_FLAGS}\"
(
        unset OMR_OPTIMIZE
        unset OPTIMIZATION_FLAGS
        unset UMA_DO_NOT_OPTIMIZE_CCODE
        unset UMA_OPTIMIZATION_CFLAGS
        unset UMA_OPTIMIZATION_CXXFLAGS
        unset UMA_DO_NOT_OPTIMIZE_CCODE
        unset VMDEBUG
        unset VMLINK
        unset enable_optimized
        unset enable_optimize
        unset j9_conf
        unset BUILD_CONFIG
        unset CONF
        if [ \"\${BUILD_TYPE}\" == \"debug\" ];
        then
                export OMR_OPTIMIZE=0
                export OPTIMIZATION_FLAGS='-fno-inline -fstack-protector-all'
                export UMA_DO_NOT_OPTIMIZE_CCODE=1
                export UMA_OPTIMIZATION_CFLAGS='-fno-inline -fstack-protector-all'
                export UMA_OPTIMIZATION_CXXFLAGS='-fno-inline -fstack-protector-all'
                export UMA_DO_NOT_OPTIMIZE_CCODE='1'
                export VMDEBUG='-g3 -fno-inline -fstack-protector-all -O0'
                export VMLINK='-g -O0'
                export enable_optimized=no
                export enable_optimize=no
                export j9_conf='--with-debug-level=slowdebug'
                export BUILD_CONFIG=slowdebug
                export CONF=slowdebug
        fi

        case \$1 in
                configure)
                        bash configure \\
                                --with-freemarker-jar=${UTILS}/freemarker.jar \\
                                --with-boot-jdk=${UTILS}/bootjdk${VERSION}_${ARCH} \\
                                \${j9_conf} \\
                                ${CONFIGURE_ARGS[*]} \\
                                \"\${@:2}\"
                        ;;
                build)
                        if [ \"\${BUILD_TYPE}\" == \"debug\" ];
                        then
                                ${UTILS}/casa.watchdog.sh make \\
                                        --with-extra-cflags='-O0 -g3' \\
                                        --with-extra-cxxflags='-O0 -g3' \\
                                        ${BUILD_ARGS[*]} \\
                                        \"\${@:2}\" 
                        else
                                ${UTILS}/casa.watchdog.sh make \\
                                        ${BUILD_ARGS[*]} \\
                                        \"\${@:2}\" 
                        fi
                        ;;
                clean)
                        make clean ${CLEAN_ARGS[*]} \"\${@:2}\"
                        ;;
                *)
                        echo 'not a valid command'
        esac
) 2>&1 | tee \"_\$1.log\"
popd || exit 255
" > "${OUTPUT[get_source]}/${FUNCNAME[0]}.sh"
        chmod +x "${OUTPUT[get_source]}/${FUNCNAME[0]}.sh"
}

run_all() {
        (
                sleep 1 
                while true;
                do
                        for files in "${LOGS}/"*.progress;
                        do
                                if [ -f "${files}" ]
                                then
                                        echo -e "\n\n========== LOG ${files} ============ \n\n"
                                        timeout 10 tail -f "${files}"
                                fi
                        done
                done 
        )&

        logger="$!"

        ( for file in "${SCRIPTS}"/get_*.sh; do echo "${file}"; done ) | xargs -n1 -P4 -I{} /bin/bash -c '{}'
        kill "${logger}"

}

source_env() {
	echo "\
export BUILD_TYPE=${BUILD_TYPE}
export VERSION=${VERSION}
export ARCH=${ARCH}
export FREEMARKER_PATH=${UTILS}/freemarker.jar
export JAVA_HOME=${UTILS}/bootjdk${VERSION}_${ARCH}
export PATH=${BOOTJDK_PATH}/bin:${PATH}
" > "${OUTPUT[get_source]}/${SOURCE_FLAGS}"
}

patch_debug() {
        orig_openj9_mk="${OUTPUT[openj9]}/runtime/makelib/targets.mk.linux.inc.ftl"
        openj9_mk="${UTILS}/j9.mk"
        # make the original copy
        [ -f "${orig_openj9_mk}" ] && [ ! -f "${openj9_mk}" ] && \
                cp "${orig_openj9_mk}" "${openj9_mk}"

        if [ -f "${openj9_mk}" ];
        then
                if [ "${BUILD_TYPE}" == "debug" ];
                then
                        sed "/--strip-debug/d" "${openj9_mk}" > "${orig_openj9_mk}"
                else
                        cp "${openj9_mk}" "${orig_openj9_mk}"
                fi
        fi
        
        orig_omr_mk="${OUTPUT[omr]}/omrmakefiles/rules.linux.mk"
        omr_mk="${UTILS}/omr.mk"
        # make the original copy
        [ -f "${orig_omr_mk}" ] && [ ! -f "${omr_mk}" ] && \
                cp "${orig_omr_mk}" "${omr_mk}"

        if [ -f "${omr_mk}" ];
        then
                if [ "${BUILD_TYPE}" == "debug" ];
                then
                        sed "/--strip-debug/d" "${omr_mk}" > "${orig_omr_mk}"
                else
                        cp "${omr_mk}" "${orig_omr_mk}"
                fi
        fi
}

######################
# Initial 
case "$(uname -s)" in
        Linux)
                # nothing to do
        ;;*)
                echo "This script can only be ran on a Linux host, exiting"
                exit 255
        ;;
esac

# check valid env
case "${BUILD_TYPE}" in                
[Rr]elease|[Dd]ebug) ;;*)     die -1 "BUILD_TYPE=\"${BUILD_TYPE}\"  env variable can only be \"release\" or \"debug\"";;
esac

case "${VERSION}" in
8|9|10|11|12);;*)       die -1 "VERSION=\"${VERSION}\" env variable can only be \"8, 9, 10, 11 or 12\"";;
esac

# check cmd
case $1 in
        build|configure|clean);;
        *)              die -1 "Invalid command $1";;
esac


echo "Running With the following variables"
print_script_env
echo "========="

# set env
source_env

# generate base scripts
echo " --- Generating runnables"
get_freemarker
get_bootjdk
get_dockerfile
get_watchdog
get_xdocker
get_source_jdk
get_omr
get_openj9

#generate a multithreaded cmd
echo " --- Doing setup"
run_all

echo " --- Patching debug symbols"
patch_debug

# generate the build scripts
echo " --- generate the build scripts"
do_j9

FAILURES=( "${LOGS}/"*.failure )
fail_count=0
for failures in "${FAILURES[@]}";
do
        if [ -f "${failures}" ];
        then
                fail_count=$(( fail_count + 1 ))
                echo "==== FAILED ${failures} ======="
                cat "${failures}"
        fi
done
EXIT_CODE=${fail_count}

if [ "0" == "${EXIT_CODE}" ]
then
        echo " --- Starting docker chroot environment"
        echo " do_configure.sh and do_build.sh will allow you to build"
        "${UTILS}"/xdocker.sh -f "${BUILDER}"/Dockerfile "${ARCH}" "${THIS_DIR}" "${OUTPUT[get_source]}/do_j9.sh" "$@"
        EXIT_CODE=$?
fi

echo " Done, exit with code ${EXIT_CODE}"
exit ${EXIT_CODE}
