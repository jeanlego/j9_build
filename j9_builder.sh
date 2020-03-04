#!/bin/bash

ARGS_IN="$@"

## Returns errlvl 0 if $1 is a reachable git remote url 
reachable_host() {
        ping -c2 -W2 -q "$1" &> /dev/null
}

# set defaults 

[ "_${ARCH}" != "_" ]           || ARCH="$(uname -m)"
[ "_${VERSION}" != "_" ]        || VERSION="8"
[ "_${BUILD_TYPE}" != "_" ]     || BUILD_TYPE="release"
J9_JDK_BASE="jdk${VERSION}"


BASE_DIR=${PWD}/j9Builds
DOWNLOADS=${BASE_DIR}/downloads
LOGS=${BASE_DIR}/logs
UTILS=${BASE_DIR}/utils
BUILDER=${UTILS}/builder
SCRIPTS=${UTILS}/scripts

J9_JDK_DIR="${BASE_DIR}/${J9_JDK_BASE}"
SOURCE_FLAGS=${BASE_DIR}/j9.env
TMP_DIR=$(mktemp -d)

mkdir -p ${BASE_DIR}
mkdir -p ${DOWNLOADS}
mkdir -p ${UTILS}
rm -Rf ${SCRIPTS} && mkdir -p ${SCRIPTS}
rm -Rf ${BUILDER} && mkdir -p ${BUILDER}     
rm -Rf ${LOGS} && mkdir -p ${LOGS}     

mkdir -p ${J9_JDK_DIR}
mkdir -p ${J9_JDK_DIR}/omr
mkdir -p ${J9_JDK_DIR}/openj9


git_origin="https://github.com/CAS-Atlantic"
get_source_origin="https://github.com/ibmruntimes"

# if $(reacheable_host gitlab.casa.cs.unb.ca); then
#         git_origin="http://gitlab.casa.cs.unb.ca/omr"
#         case ${VERSION} in
#                 11)     get_source_origin="http://gitlab.casa.cs.unb.ca/omr";;
#         esac
# fi

# check valid env
case ${BUILD_TYPE} in                
release|debug) ;;*)     die -1 "BUILD_TYPE=\"${BUILD_TYPE}\"  env variable can only be \"release\" or \"debug\"";;
esac

case ${VERSION} in
8|9|10|11|12);;*)       die -1 "VERSION=\"${VERSION}\" env variable can only be \"8, 9, 10, 11 or 12\"";;
esac

print_script_env() {
        printf "\
BUILD_TYPE=${BUILD_TYPE}\n\
VERSION=${VERSION}\n\
ARCH=${ARCH}
"
}

#####################
# USAGE PRINTER
usage() {

        printf \
"\n\
$0 \n\
Usage:\n\
    build     [<makefile targets>...]          build using makefile\n\
    configure [<extra-configure-args> ... ]    trigger a configure \n\

Variables:
    VERSION             8 | 9 | 10 | 11 | 12
    BUILD_TYPE          debug | release
    ARCH                x86_64 | x86 | aarch64 ... <see openj9 hotspot release>
"
exit $1
}

die() {
        printf "\
 == ERROR: $2\n\
you called this program with \"${ARGS_IN}\" \n\
"
print_script_env

        usage $1
}

exec_or_die() {
        
        echo "Executing ${FUNCNAME[1]}"
        echo "$@" | tr -s " " > ${SCRIPTS}/${FUNCNAME[1]}.sh
        chmod +x ${SCRIPTS}/${FUNCNAME[1]}.sh
        ${SCRIPTS}/${FUNCNAME[1]}.sh 2>&1 |& tee ${LOGS}/${FUNCNAME[1]}.progress

        if [ "0" != $? ]; then 
                echo "Failed to do \"${SCRIPTS}/${FUNCNAME[1]}.sh\", see ${LOGS}/${FUNCNAME[1]}.failure"
                mv ${LOGS}/${FUNCNAME[1]}.progress ${LOGS}/${FUNCNAME[1]}.failure
                exit $?
        else
                mv ${LOGS}/${FUNCNAME[1]}.progress ${LOGS}/${FUNCNAME[1]}.success
        fi
}

fetch() {
	OUTPUT="$1"
	URL="$2"
        [ ! -f ${OUTPUT} ] \
        && reachable_host "${URL}" \
        && exec_or_die "curl --output ${OUTPUT} ${URL}"

}

get_freemarker() {
	fetch \
		"${DOWNLOADS}/freemarker.tgz" \
		"https://sourceforge.net/projects/freemarker/files/freemarker/2.3.8/freemarker-2.3.8.tar.gz/download"
}

get_bootjdk() {
	fetch \
		"${DOWNLOADS}/bootjdk${VERSION}_${ARCH}.tar.gz" \
		"https://api.adoptopenjdk.net/v2/binary/nightly/openjdk${VERSION}?openjdk_impl=hotspot&os=linux&arch=${ARCH}&release=latest&type=jdk"
}

get_dockerfile() {
	fetch \
		"${BUILDER}/Dockerfile" \
		"https://raw.githubusercontent.com/CAS-Atlantic/openj9/52fa8dc53987972998512f45b91fe4cca268b652/buildenv/docker/jdk11/x86_64/ubuntu18/Dockerfile"
}

get_watchdog() {
	fetch \
		"${UTILS}/casa.watchdog.sh" \
		"https://raw.githubusercontent.com/CAS-Atlantic/openj9/aarch64_casa_watchdog_script/casa.watchdog.sh"
}

get_xdocker() {
	fetch \
		"${UTILS}/xdocker.sh" \
		"https://raw.githubusercontent.com/CAS-Atlantic/xdocker/master/xdocker.sh"
}

git_init() {
        [ ! -f $1/.git ] &&
              exec_or_die "\
                        git -C $1 init &&
                        git -C ${J9_JDK_DIR} remote add origin ${get_source_origin}/openj9-openjdk-jdk${VERSION}.git"

}

init_source_jdk() {
        [ ! -f ${J9_JDK_DIR}/.git ] &&
                exec_or_die "\
                        git -C ${J9_JDK_DIR} init &&
                        git -C ${J9_JDK_DIR} remote add origin ${get_source_origin}/openj9-openjdk-jdk${VERSION}.git
                        "
}

init_source_omr() {
	[ ! -f ${J9_JDK_DIR}/omr/.git ] &&
                exec_or_die "\
                        git -C ${J9_JDK_DIR}/omr init &&
                        git -C ${J9_JDK_DIR}/omr remote add origin ${git_origin}/openj9-omr.git
                        "
}

init_source_openj9() {
        [ ! -f ${J9_JDK_DIR}/openj9/.git ] &&
                exec_or_die "\
                        git -C ${J9_JDK_DIR}/openj9 init &&
                        git -C ${J9_JDK_DIR}/openj9 remote add origin ${git_origin}/openj9.git
                        "
}

fetch_branch_jdk() {
        exec_or_die "\
                git -C ${J9_JDK_DIR} fetch --progress origin openj9 &&
                git -C ${J9_JDK_DIR} checkout --progress -b openj9 origin/openj9
                "
}

fetch_branch_openj9() {
        exec_or_die "
                git -C ${J9_JDK_DIR}/openj9 fetch --progress origin master &&
                git -C ${J9_JDK_DIR}/openj9 checkout --progress -b master origin/master
                "
}

fetch_branch_omr() {
        exec_or_die "
                git -C ${J9_JDK_DIR}/omr fetch --progress origin openj9 &&
                git -C ${J9_JDK_DIR}/omr checkout --progress -b openj9 origin/openj9
                "
}

get_source_jdk() {
        init_source_jdk
        fetch_branch_jdk
}

get_source_omr() {
        init_source_omr
        fetch_branch_omr
}

get_source_openj9() {
        init_source_openj9
        fetch_branch_openj9
}

extract_freemarker() {
        [ ! -f "${UTILS}/freemarker.jar" ] &&
                exec_or_die  "\
                        tar -C ${UTILS} \
                                -xzf ${DOWNLOADS}/freemarker.tgz freemarker-2.3.8/lib/freemarker.jar --strip=2 \
                        "
}

extract_bootjdk() {
        [ ! -d "${UTILS}/bootjdk${VERSION}_${ARCH}" ] &&
                exec_or_die "\
                        tar -xzf ${DOWNLOADS}/bootjdk${VERSION}_${ARCH}.tar.gz -C ${TMP_DIR} &&
                        mv ${TMP_DIR}/* ${UTILS}/bootjdk${VERSION}_${ARCH}
                        "
}

source_env() {

	echo "\
export BUILD_TYPE=${BUILD_TYPE}
export VERSION=${VERSION}
export ARCH=${ARCH}
export FREEMARKER_PATH="${UTILS}/freemarker.jar"
export JAVA_HOME="${UTILS}/bootjdk${VERSION}_${ARCH}"
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
" > ${SOURCE_FLAGS}

        if [ "${BUILD_TYPE}" != "debug" ]
        then 
	        echo "\
unset j9_conf
unset BUILD_CONFIG
unset CONF
" >> ${SOURCE_FLAGS}
        fi
}

patch_debug() {
        sed -i "/--strip-debug/d" ${J9_JDK_DIR}/openj9/runtime/makelib/targets.mk.linux.inc.ftl
        sed -i "/--strip-debug/d" ${J9_JDK_DIR}/omr/omrmakefiles/rules.linux.mk
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
                bash configure --with-freemarker-jar=${FREEMARKER_PATH} --with-boot-jdk=${JAVA_HOME} ${j9_conf} $@ ;\
                popd; \
                " 
}

build_cmd() {
        exec_or_die "\
                source ${SOURCE_FLAGS}; \
                pushd ${J9_JDK_DIR}; \
                chmod +x ${UTILS}/casa.watchdog.sh ;\
                ${UTILS}/casa.watchdog.sh make $@ ;\
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
                exit -1
        ;;
esac

case $1 in
        configure|build);;
        *)              die -1 "Invalid command $1";;
esac

echo "Running With the following variables"
print_script_env
echo "========="

pids=()

# set env

[ "_${XDOCKER}" == "_" ] && source_env

source ${SOURCE_FLAGS}

( get_freemarker && extract_freemarker )& pids+=( "$!" )

( get_bootjdk && extract_bootjdk )& pids+=( "$!" )

( get_dockerfile )& pids+=( "$!" )

( get_watchdog )& pids+=( "$!" )

( get_xdocker )& pids+=( "$!" )

( get_source_jdk )& pids+=( "$!" )

( get_source_omr )& pids+=( "$!" )

( get_source_openj9 )& pids+=( "$!" )

# Wait for all processes to finish
EXIT_CODE=0
for p in $pids; do
        if wait $p; then
                echo "Process $p success"
        else
                EXIT_CODE=$(( 1 + ${EXIT_CODE} ))
                echo "Process $p fail"
        fi
done

get_source 

patch_debug

if [ "${EXIT_CODE}" == "0" ]; then

        if [ "_${XDOCKER}" == "_" ]; then

                echo "Starting docker chroot environment"
                echo "####"
                chmod +x ${UTILS}/xdocker.sh
                ${UTILS}/xdocker.sh -f ${BUILDER}/Dockerfile ${ARCH} ./
        else
                case $1 in
                        configure)        
                                configure_cmd "${@:2}"
                        ;;
                        build)          
                                build_cmd "${@:2}"
                        ;;
                        *)              
                                die -1 "Invalid command $@"
                        ;;
                esac
        fi
        EXIT_CODE=$?
fi

exit ${EXIT_CODE}
