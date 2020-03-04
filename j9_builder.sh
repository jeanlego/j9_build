#!/bin/bash

ARGS_IN=( "$@" )

## Returns errlvl 0 if $1 is a reachable git remote url 
reachable_host() {
        ping -c2 -W2 -q "$1" &> /dev/null
}

# set defaults 

[ "_${ARCH}" != "_" ]           || ARCH="$(uname -m)"
[ "_${VERSION}" != "_" ]        || VERSION="8"
[ "_${BUILD_TYPE}" != "_" ]     || BUILD_TYPE="release"
J9_JDK_BASE="jdk${VERSION}"

BASE_DIR="${PWD}"/j9Builds
DOWNLOADS="${BASE_DIR}"/downloads
LOGS="${BASE_DIR}"/logs
UTILS="${BASE_DIR}"/utils
BUILDER="${UTILS}"/builder
SCRIPTS="${UTILS}"/scripts

J9_JDK_DIR="${BASE_DIR}/${J9_JDK_BASE}"
SOURCE_FLAGS="${BASE_DIR}"/j9.env

mkdir -p "${BASE_DIR}"
mkdir -p "${DOWNLOADS}"
mkdir -p "${UTILS}"
rm -Rf "${SCRIPTS}" && mkdir -p "${SCRIPTS}"
rm -Rf "${BUILDER}" && mkdir -p "${BUILDER}"     
rm -Rf "${LOGS}" && mkdir -p "${LOGS}"     

mkdir -p "${J9_JDK_DIR}"
mkdir -p "${J9_JDK_DIR}/omr"
mkdir -p "${J9_JDK_DIR}/openj9"

git_origin="https://github.com/CAS-Atlantic"
get_source_origin="https://github.com/ibmruntimes"

# check valid env
case "${BUILD_TYPE}" in                
release|debug) ;;*)     die -1 "BUILD_TYPE=\"${BUILD_TYPE}\"  env variable can only be \"release\" or \"debug\"";;
esac

case "${VERSION}" in
8|9|10|11|12);;*)       die -1 "VERSION=\"${VERSION}\" env variable can only be \"8, 9, 10, 11 or 12\"";;
esac

declare -A URL
declare -A OUTPUT
declare -A BRANCH
declare -A REMOTE

URL[get_source]="${get_source_origin}/openj9-openjdk-jdk${VERSION}.git"
BRANCH[get_source]="openj9"
REMOTE[get_source]="origin"
OUTPUT[get_source]="${J9_JDK_DIR}"

URL[openj9]="${git_origin}/openj9.git"
BRANCH[openj9]="master"
REMOTE[openj9]="origin"
OUTPUT[openj9]="${J9_JDK_DIR}/openj9"

URL[omr]="${git_origin}/omr.git"
BRANCH[omr]="master"
REMOTE[omr]="origin"
OUTPUT[omr]="${J9_JDK_DIR}/omr"

URL[freemarker]="https://sourceforge.net/projects/freemarker/files/freemarker/2.3.8/freemarker-2.3.8.tar.gz/download"
OUTPUT[freemarker]="${DOWNLOADS}/freemarker.tgz"

URL[bootjdk]="https://api.adoptopenjdk.net/v2/binary/nightly/openjdk${VERSION}?openjdk_impl=hotspot&os=linux&arch=${ARCH}&release=latest&type=jdk"
OUTPUT[bootjdk]="${DOWNLOADS}/bootjdk${VERSION}_${ARCH}.tar.gz"

URL[dockerfile]="https://raw.githubusercontent.com/CAS-Atlantic/openj9/52fa8dc53987972998512f45b91fe4cca268b652/buildenv/docker/jdk11/x86_64/ubuntu18/Dockerfile"
OUTPUT[dockerfile]="${BUILDER}/Dockerfile"

URL[watchdog]="https://raw.githubusercontent.com/CAS-Atlantic/openj9/aarch64_casa_watchdog_script/casa.watchdog.sh"
OUTPUT[watchdog]="${UTILS}/casa.watchdog.sh"

URL[xdocker]="https://raw.githubusercontent.com/CAS-Atlantic/xdocker/master/xdocker.sh"
OUTPUT[xdocker]="${UTILS}/xdocker.sh"

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
    build     [<makefile targets>...]          build using makefile
    configure [<extra-configure-args> ... ]    trigger a configure

Variables:
    VERSION             8 | 9 | 10 | 11 | 12
    BUILD_TYPE          debug | release
    ARCH                x86_64 | x86 | aarch64 ... <see openj9 hotspot release>
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
#!/bin/sh
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

generic_git_cmd='
        if [ ! -f "${DIR}/.git" ]; then
                git -C "${DIR}" init
                git -C "${DIR}" remote add "${REMOTE}" "${REMOTE_URL}"
        fi
        git -C "${DIR}" fetch --progress "${REMOTE}" "${BRANCH}"
        if [ "_$(git rev-parse --abbrev-ref HEAD)" != "_${BRANCH}" ]; then
                git -C "${DIR}" checkout --progress -b "${BRANCH}" "${REMOTE}/${BRANCH}"
        fi
'

generic_curl_cmd='
        if [ ! -f "${OUTPUT}" ]; then
                curl -L --output "${OUTPUT}" "${URL}"
        fi
'

get_source_jdk() {
        create_sh "
        DIR=\"${OUTPUT[get_source]}\"
        BRANCH=\"${BRANCH[get_source]}\"
        REMOTE_URL=\"${URL[get_source]}\"
        REMOTE=\"${REMOTE[get_source]}\"
        ${generic_git_cmd}
"
}

get_omr() {
        create_sh "
        DIR=\"${OUTPUT[omr]}\"
        BRANCH=\"${BRANCH[omr]}\"
        REMOTE_URL=\"${URL[omr]}\"
        REMOTE=\"${REMOTE[omr]}\"
        ${generic_git_cmd}
"
}

get_openj9() {
        
        create_sh "
        DIR=\"${OUTPUT[openj9]}\"
        BRANCH=\"${BRANCH[openj9]}\"
        REMOTE_URL=\"${URL[openj9]}\"
        REMOTE=\"${REMOTE[openj9]}\"
        ${generic_git_cmd}
"
}

get_freemarker() {

        create_sh  "
        URL=\"${URL[freemarker]}\"
        OUTPUT=\"${OUTPUT[freemarker]}\"
        ${generic_curl_cmd}
        if [ ! -f ${UTILS}/freemarker.jar ]; then
                tar -C ${UTILS} -xzf ${DOWNLOADS}/freemarker.tgz freemarker-2.3.8/lib/freemarker.jar --strip=2
        fi
        "
}

get_bootjdk() {
        create_sh "
        URL=\"${URL[bootjdk]}\"
        OUTPUT=\"${OUTPUT[bootjdk]}\"
        ${generic_curl_cmd}
        if [ ! -d ${UTILS}/bootjdk${VERSION}_${ARCH} ]; then
                mkdir ${DOWNLOADS}/scratch
                tar -xzf ${DOWNLOADS}/bootjdk${VERSION}_${ARCH}.tar.gz -C ${DOWNLOADS}/scratch
                mv ${DOWNLOADS}/scratch/* ${UTILS}/bootjdk${VERSION}_${ARCH}
                rm -Rf ${DOWNLOADS}/scratch
        fi
        "
}

get_watchdog() {
        create_sh "
        URL=\"${URL[watchdog]}\"
        OUTPUT=\"${OUTPUT[watchdog]}\"
        ${generic_curl_cmd}
        "
}

get_xdocker() {
        create_sh "
        URL=\"${URL[xdocker]}\"
        OUTPUT=\"${OUTPUT[xdocker]}\"
        ${generic_curl_cmd}
        "
}

get_dockerfile() {
        create_sh "
        URL=\"${URL[dockerfile]}\"
        OUTPUT=\"${OUTPUT[dockerfile]}\"
        ${generic_curl_cmd}
        "
}

run_all() {
        ( for file in "${SCRIPTS}"/get_*.sh; do echo "${file}"; done ) | xargs -n1 -P4 -I{} /bin/bash -c '{}'
}

source_env() {

	echo "\
export BUILD_TYPE=${BUILD_TYPE}
export VERSION=${VERSION}
export ARCH=${ARCH}
export FREEMARKER_PATH=${UTILS}/freemarker.jar
export JAVA_HOME=${UTILS}/bootjdk${VERSION}_${ARCH}
export PATH=${BOOTJDK_PATH}/bin:${PATH}
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
export CXXFLAGS='-O0 -g3'
export CFLAGS='-O0 -g3'
export j9_conf='--with-debug-level=slowdebug'
export BUILD_CONFIG=slowdebug
export CONF=slowdebug
" > "${SOURCE_FLAGS}"

        if [ "${BUILD_TYPE}" != "debug" ]
        then 
	        echo "\
unset j9_conf
unset BUILD_CONFIG
unset CONF
" >> "${SOURCE_FLAGS}"
        fi
}

patch_debug() {
        sed -i "/--strip-debug/d" "${J9_JDK_DIR}/openj9/runtime/makelib/targets.mk.linux.inc.ftl"
        sed -i "/--strip-debug/d" "${J9_JDK_DIR}/omr/omrmakefiles/rules.linux.mk"
}

clean_cmd() {
        exec_or_die "\
                source ${SOURCE_FLAGS}; \
                make clean; \
                " 
}
configure_cmd() {
        exec_or_die "\
                source ${SOURCE_FLAGS}; \
                chmod +x ./configure; \
                bash configure --with-freemarker-jar=${FREEMARKER_PATH} --with-boot-jdk=${JAVA_HOME} ${j9_conf} \$* ;\
                popd; \
                " 
}

build_cmd() {
        exec_or_die "\
                source ${SOURCE_FLAGS}; \
                pushd ${J9_JDK_DIR}; \
                chmod +x ${UTILS}/casa.watchdog.sh ;\
                ${UTILS}/casa.watchdog.sh make $* ;\
                popd ;\
                "
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

case $1 in
        configure|build);;
        *)              die -1 "Invalid command $1";;
esac

echo "Running With the following variables"
print_script_env
echo "========="


# set env
source_env

source "${SOURCE_FLAGS}"

# generate base scripts
get_freemarker
get_bootjdk
get_dockerfile
get_watchdog
get_xdocker
get_source_jdk
get_omr
get_openj9

#generate a multithreaded cmd
run_all



patch_debug

if [ "${EXIT_CODE}" == "0" ]; then

        if [ "_${XDOCKER}" == "_" ]; then

                echo "Starting docker chroot environment"
                echo "####"
                chmod +x "${UTILS}/xdocker.sh"
                "${UTILS}/xdocker.sh" -f "${BUILDER}/Dockerfile ${ARCH}" ./
        else
                case $1 in
                        configure)        
                                configure_cmd "${@:2}"
                        ;;
                        build)          
                                build_cmd "${@:2}"
                        ;;
                        *)              
                                die -1 "Invalid command $*"
                        ;;
                esac
        fi
        EXIT_CODE=$?
fi

exit ${EXIT_CODE}
