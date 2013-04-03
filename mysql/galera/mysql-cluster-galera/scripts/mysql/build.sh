#!/bin/bash -x

if test -z "$MYSQL_SRC"
then
    echo "MYSQL_SRC variable pointing at MySQL/wsrep sources is not set. Can't continue."
    exit -1
fi

use_mysql_5.1_sources()
{
    MYSQL_MAJOR="5.1"
    export MYSQL_5_1=$MYSQL_MAJOR # for DEB build
    export MYSQL_MAJOR_VER="5"
    export MYSQL_MINOR_VER="1"
    MYSQL_VER=`grep AC_INIT $MYSQL_SRC/configure.in | awk -F '[' '{ print $3 }' | awk -F ']' '{ print $1 }'`
}
use_mariadb_5.1_sources()
{
    use_mysql_5.1_sources
}
use_mysql_5.5_sources()
{
    MYSQL_MAJOR="5.5"
    export MYSQL_5_5=$MYSQL_MAJOR # for DEB build
    export MYSQL_MAJOR_VER="5"
    export MYSQL_MINOR_VER="5"
    MYSQL_VER=`awk -F '=' 'BEGIN { ORS = "" } /MYSQL_VERSION_MAJOR/ { print $2 "." } /MYSQL_VERSION_MINOR/ { print $2 "." } /MYSQL_VERSION_PATCH/ { print $2 }' $MYSQL_SRC/VERSION`
}

if test -f "$MYSQL_SRC/configure.in"
then
    use_mysql_5.1_sources
elif test -f "$MYSQL_SRC/VERSION"
then
    use_mysql_5.5_sources
else
    echo "Unknown MySQL version in MYSQL_SRC path. Versions 5.1 and 5.5 are supported. Can't continue."
    exit -1
fi

# Initializing variables to defaults
uname -m | grep -q i686 && CPU=pentium || CPU=amd64 # this works for x86 Solaris too
DEBUG=no
DEBUG_LEVEL=1
GALERA_DEBUG=no
NO_STRIP=no
RELEASE=""
TAR=no
BIN_DIST=no
PACKAGE=no
INSTALL=no
CONFIGURE=no
SKIP_BUILD=no
SKIP_CONFIGURE=no
SKIP_CLIENTS=no
SCRATCH=no
SCONS="yes"
JOBS=1
GCOMM_IMPL=${GCOMM_IMPL:-"galeracomm"}

OS=$(uname)
case $OS in
    "Linux")
        JOBS=$(grep -c ^processor /proc/cpuinfo) ;;
    "SunOS")
        JOBS=$(psrinfo | wc -l) ;;
    *)
        echo "CPU information not available: unsupported OS: '$OS'";;
esac

usage()
{
    cat <<EOF
Usage: build.sh [OPTIONS]
Options:
    --stage <initial stage>
    --last-stage <last stage>
    -s|--scratch      build everything from scratch
    -c|--configure    reconfigure the build system (implies -s)
    -b|--bootstap     rebuild the build system (implies -c)
    -o|--opt          configure build with debug disabled (implies -c)
    -m32/-m64         build 32/64-bit binaries on x86
    -d|--debug        configure build with debug enabled (implies -c)
    -dl|--debug-level set debug level (1, implies -c)
    --with-spread     configure build with Spread (implies -c)
    --no-strip        prevent stripping of release binaries
    -j|--jobs         number of parallel compilation jobs (${JOBS})
    -p|--package      create DEB/RPM packages (depending on the distribution)
    --bin             create binary tar package
    -t|--tar          create a demo test distribution
    --sb|--skip-build skip the actual build, use the existing binaries
    --sc|--skip-configure skip configure
    --skip-clients    don't include client binaries in test package
    --scons           use scons to build galera libraries (yes)
    -r|--release <galera release>, otherwise revisions will be used

-s and -b options affect only Galera build.
EOF
}

# Parse command line
while test $# -gt 0
do
    case $1 in
        -b|--bootstrap)
            BOOTSTRAP="yes" # Bootstrap the build system
            CONFIGURE="yes"
            ;;
        --bin)
            BIN_DIST="yes"
            ;;
        -c|--configure)
            CONFIGURE="yes" # Reconfigure the build system
            ;;
        -s|--scratch)
            SCRATCH="yes"   # Build from scratch (run make clean)
            ;;
        -o|--opt)
            OPT="yes"       # Compile without debug
            ;;
        -d|--debug)
            DEBUG="yes"     # Compile with debug
            NO_STRIP="yes"  # Don't strip the binaries
            ;;
        --dl|--debug-level)
            shift;
            DEBUG_LEVEL=$1
            ;;
        --gd|--galera-debug)
            GALERA_DEBUG="yes"
            ;;
        -r|--release)
            RELEASE="$2"    # Compile without debug
            shift
            ;;
        -t|--tar)
            TAR="yes"       # Create a TGZ package
            ;;
        -i|--install)
            INSTALL="yes"
            ;;
        -p|--package)
            PACKAGE="yes"   # Create a DEB package
            CONFIGURE="yes" # don't forget to reconfigure with --prefix=/usr
            ;;
        -j|--jobs)
            shift;
            JOBS=$1
            ;;
        --no-strip)
            NO_STRIP="yes"  # Don't strip the binaries
            ;;
        --with*-spread)
            WITH_SPREAD="$1"
            ;;
        -m32)
            CFLAGS="$CFLAGS -m32"
            CXXFLAGS="$CXXFLAGS -m32"
            CONFIGURE="yes"
            CPU="pentium"
            TARGET="i686"
            ;;
        -m64)
            CFLAGS="$CFLAGS -m64"
            CXXFLAGS="$CXXFLAGS -m64"
            CONFIGURE="yes"
            CPU="amd64"
            TARGET="x86_64"
            ;;
        --sb|--skip-build)
            SKIP_BUILD="yes"
            ;;
        --sc|--skip-configure)
            SKIP_CONFIGURE="yes"
            ;;
        --skip-clients)
            SKIP_CLIENTS="yes"
            ;;
        --scons)
            SCONS="yes"
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unrecognized option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$PACKAGE" == "yes" ]
then
    # check whether sudo accepts -E to preserve environment
    echo "testing sudo"
    if sudo -E $(which epm) --version >/dev/null 2>&1
    then
        echo "sudo accepts -E"
        SUDO_ENV="sudo -E"
        SUDO="sudo"
    else
        echo "sudo does not accept param -E"
        if [ $(id -ur) != 0 ]
        then
            echo "error, must build as root"
            exit 1
        else
            SUDO_ENV=""
            SUDO=""
            echo "I'm root, can continue"
        fi
    fi

    # If packaging with epm, make sure that mysql user exists in build system to
    # get file ownerships right.
    echo "Checking for mysql user and group for epm:"
    getent passwd mysql >/dev/null
    if [ $? != 0 ]
    then
        echo "Error: user 'mysql' does not exist"
        exit 1
    else
        echo "User 'mysql' ok"
    fi
    getent group mysql >/dev/null
    if [ $? != 0 ]
    then
        echo "Error: group 'mysql' doest not exist"
        exit 1
    else
        echo "Group 'mysql' ok"
    fi
fi

if [ "$OPT"     == "yes" ]; then CONFIGURE="yes"; fi
if [ "$DEBUG"   == "yes" ]; then CONFIGURE="yes"; fi
if [ "$INSTALL" == "yes" ]; then TAR="yes"; fi
if [ "$SKIP_BUILD" == "yes" ]; then CONFIGURE="no"; fi

which dpkg >/dev/null 2>&1 && DEBIAN=1 || DEBIAN=0

# export command options for Galera build
export BOOTSTRAP CONFIGURE SCRATCH OPT DEBUG WITH_SPREAD CFLAGS CXXFLAGS \
       PACKAGE CPU TARGET SKIP_BUILD RELEASE DEBIAN SCONS JOBS DEBUG_LEVEL

set -eu

# Absolute path of this script folder
BUILD_ROOT=$(cd $(dirname $0); pwd -P)
GALERA_SRC=${GALERA_SRC:-$BUILD_ROOT/../../}
# Source paths are either absolute or relative to script, get absolute
MYSQL_SRC=$(cd $MYSQL_SRC; pwd -P; cd $BUILD_ROOT)
GALERA_SRC=$(cd $GALERA_SRC; pwd -P; cd $BUILD_ROOT)


######################################
##                                  ##
##          Build Galera            ##
##                                  ##
######################################
# Also obtain SVN revision information
if [ "$TAR" == "yes" ] || [ "$BIN_DIST" == "yes" ]
then
    cd $GALERA_SRC
    debug_opt=""
    if [ $GALERA_DEBUG == "yes" ]
    then
        debug_opt="-d"
    fi
    scripts/build.sh $debug_opt # options are passed via environment variables
    GALERA_REV=$(bzr revno 2>/dev/null)     || \
    GALERA_REV=$(svnversion | sed s/\:/,/g) || \
    GALERA_REV=$(echo "xxxx")
fi

######################################
##                                  ##
##           Build MySQL            ##
##                                  ##
######################################
# Obtain MySQL version and revision number
cd $MYSQL_SRC
WSREP_REV=$(bzr revno) || \
WSREP_REV="XXXX"
# this does not work on an unconfigured source MYSQL_VER=$(grep '#define VERSION' $MYSQL_SRC/include/config.h | sed s/\"//g | cut -d ' ' -f 3 | cut -d '-' -f 1-2)

if [ "$PACKAGE" == "yes" ] || [ "$BIN_DIST" == "yes" ]
then
    # fetch and patch pristine sources
    cd /tmp
    mysql_tag=mysql-$MYSQL_VER
    if [ "$SKIP_BUILD" == "no" ] || [ ! -d $mysql_tag ]
    then
        mysql_orig_tar_gz=$mysql_tag.tar.gz
        url2=http://ftp.sunet.se/pub/unix/databases/relational/mysql/Downloads/MySQL-$MYSQL_MAJOR
        url1=ftp://sunsite.informatik.rwth-aachen.de/pub/mirror/www.mysql.com/Downloads/MySQL-$MYSQL_MAJOR
        if [ ! -r $mysql_orig_tar_gz ]
        then
            echo "Downloading $mysql_orig_tar_gz... currently works only for 5.1.x"
            wget -N $url1/$mysql_orig_tar_gz || wget -N $url2/$mysql_orig_tar_gz
        fi
        echo "Getting wsrep patch..."
        patch_file=$(${BUILD_ROOT}/get_patch.sh $mysql_tag $MYSQL_SRC)
        echo "Patching source..."
        rm -rf $mysql_tag # need clean sources for a patch
        tar -xzf $mysql_orig_tar_gz
        cd $mysql_tag/
        patch -p1 -f < $patch_file >/dev/null || :
        chmod a+x ./BUILD/*wsrep
        CONFIGURE="yes"
    else
        cd $mysql_tag/
    fi
    MYSQL_SRC=$(pwd -P)
    if [ "$CONFIGURE" == "yes" ]
    then
        echo "Regenerating config files"
        time ./BUILD/autorun.sh
    fi
fi

echo  "Building mysqld"

export WSREP_REV
export MAKE="make -j$JOBS"

if [ "$SKIP_BUILD" == "no" ]
then
    if [ "$CONFIGURE" == "yes" ] && [ "$SKIP_CONFIGURE" == "no" ]
    then
        rm -f config.status
        if [ "$DEBUG" == "yes" ]
        then
            DEBUG_OPT="-debug"
        else
            DEBUG_OPT=""
        fi

        # This will be put to --prefix by SETUP.sh.
        export MYSQL_BUILD_PREFIX="/usr"

        # There is no other way to pass these options to SETUP.sh but
        # via env. variable
        [ $MYSQL_MAJOR = "5.5" ] && LAYOUT="--layout=RPM" || LAYOUT=""

        [ $DEBIAN -ne 0 ] && \
        MYSQL_SOCKET_PATH="/var/run/mysqld/mysqld.sock" || \
        MYSQL_SOCKET_PATH="/var/lib/mysql/mysql.sock"

        export wsrep_configs="$LAYOUT \
                              --libexecdir=/usr/sbin \
                              --localstatedir=/var/lib/mysql/ \
                              --with-extra-charsets=all \
                              --with-ssl \
                              --with-unix-socket-path=$MYSQL_SOCKET_PATH"

        BUILD/compile-${CPU}${DEBUG_OPT}-wsrep > /dev/null
    else  # just recompile and relink with old configuration
        #set -x
        make > /dev/null
        #set +x
    fi
fi # SKIP_BUILD

# gzip manpages
# this should be rather fast, so we can repeat it every time
if [ "$PACKAGE" == "yes" ]
then
    cd $MYSQL_SRC/man && for i in *.1 *.8; do gzip -c $i > $i.gz; done || :
fi

######################################
##                                  ##
##      Making of demo tarball      ##
##                                  ##
######################################

install_mysql_5.1_demo()
{

    MYSQL_LIBS=$MYSQL_DIST_DIR/lib/mysql
    MYSQL_PLUGINS=$MYSQL_DIST_DIR/lib/mysql/plugin
    MYSQL_CHARSETS=$MYSQL_DIST_DIR/share/mysql/charsets
    install -m 644 -D $MYSQL_SRC/sql/share/english/errmsg.sys $MYSQL_DIST_DIR/share/mysql/english/errmsg.sys
    install -m 755 -D $MYSQL_SRC/sql/mysqld $MYSQL_DIST_DIR/sbin/mysqld
    if [ "$SKIP_CLIENTS" == "no" ]
    then
        # Hack alert:
        #  install libmysqlclient.so as libmysqlclient.so.16 as client binaries
        #  seem to be linked against explicit version. Figure out better way to 
        #  deal with this.
        install -m 755 -D $MYSQL_SRC/libmysql/.libs/libmysqlclient.so $MYSQL_LIBS/libmysqlclient.so.16
    fi
    if test -f $MYSQL_SRC/storage/innodb_plugin/.libs/ha_innodb_plugin.so
    then
        install -m 755 -D $MYSQL_SRC/storage/innodb_plugin/.libs/ha_innodb_plugin.so \
                $MYSQL_PLUGINS/ha_innodb_plugin.so
    fi
    install -m 755 -d $MYSQL_BINS
    if [ "$SKIP_CLIENTS" == "no" ]
    then
        if [ -x $MYSQL_SRC/client/.libs/mysql ]    # MySQL
        then
            MYSQL_CLIENTS=$MYSQL_SRC/client/.libs
        elif [ -x $MYSQL_SRC/client/mysql ]        # MariaDB
        then
            MYSQL_CLIENTS=$MYSQL_SRC/client
        else
            echo "Can't find MySQL clients. Aborting."
            exit 1
        fi
        install -m 755 -s -t $MYSQL_BINS  $MYSQL_CLIENTS/mysql
        install -m 755 -s -t $MYSQL_BINS  $MYSQL_CLIENTS/mysqldump
        install -m 755 -s -t $MYSQL_BINS  $MYSQL_CLIENTS/mysqladmin
    fi

    install -m 755 -t $MYSQL_BINS     $MYSQL_SRC/scripts/wsrep_sst_common
    install -m 755 -t $MYSQL_BINS     $MYSQL_SRC/scripts/wsrep_sst_mysqldump
    install -m 755 -t $MYSQL_BINS     $MYSQL_SRC/scripts/wsrep_sst_rsync
    install -m 755 -d $MYSQL_CHARSETS
    install -m 644 -t $MYSQL_CHARSETS $MYSQL_SRC/sql/share/charsets/*.xml
    install -m 644 -t $MYSQL_CHARSETS $MYSQL_SRC/sql/share/charsets/README
}

install_mysql_5.5_demo()
{
    export DESTDIR=$BUILD_ROOT/dist/mysql

    mkdir -p $DIST_DIR/mysql/etc
    pushd $MYSQL_SRC
    cmake -DCMAKE_INSTALL_COMPONENT=Server -P cmake_install.cmake
    cmake -DCMAKE_INSTALL_COMPONENT=Client -P cmake_install.cmake
    cmake -DCMAKE_INSTALL_COMPONENT=SharedLibraries -P cmake_install.cmake
    cmake -DCMAKE_INSTALL_COMPONENT=ManPages -P cmake_install.cmake
    popd
    pushd $MYSQL_DIST_DIR
        mv usr/* ./ && rm -r usr
        [ -d lib64 ] && [ ! -a lib ] && mv lib64 lib || :
    popd
}

if [ $TAR == "yes" ]; then
    echo "Creating demo distribution"
    # Create build directory structure
    DIST_DIR=$BUILD_ROOT/dist
    MYSQL_DIST_DIR=$DIST_DIR/mysql
    MYSQL_DIST_CNF=$MYSQL_DIST_DIR/etc/my.cnf
    GALERA_DIST_DIR=$DIST_DIR/galera
    MYSQL_BINS=$MYSQL_DIST_DIR/bin

    cd $BUILD_ROOT
    rm -rf $DIST_DIR

    # Install required MySQL files in the DIST_DIR
    if [ $MYSQL_MAJOR == "5.1" ]; then
        install_mysql_5.1_demo
        install -m 644 -D my-5.1.cnf $MYSQL_DIST_CNF
    else
        install_mysql_5.5_demo > /dev/null
        install -m 644 -D my-5.5.cnf $MYSQL_DIST_CNF
    fi

    cat $MYSQL_SRC/support-files/wsrep.cnf | \
        sed 's/root:$/root:rootpass/' >> $MYSQL_DIST_CNF
    pushd $MYSQL_BINS; ln -s wsrep_sst_rsync wsrep_sst_rsync_wan; popd
    tar -xzf mysql_var_$MYSQL_MAJOR.tgz -C $MYSQL_DIST_DIR
    install -m 644 LICENSE.mysql $MYSQL_DIST_DIR

    # Copy required Galera libraries
    GALERA_BINS=$GALERA_DIST_DIR/bin
    GALERA_LIBS=$GALERA_DIST_DIR/lib
    install -m 644 -D ../../LICENSE $GALERA_DIST_DIR/LICENSE.galera
    install -m 755 -d $GALERA_BINS
    install -m 755 -d $GALERA_LIBS

    if [ "$SCONS" == "yes" ]
    then
        SCONS_VD=$GALERA_SRC
        cp -P $SCONS_VD/garb/garbd        $GALERA_BINS
        cp -P $SCONS_VD/libgalera_smm.so* $GALERA_LIBS
    else
        echo "Autotools compilation not supported any more."
        exit 1
    fi

    install -m 644 LICENSE       $DIST_DIR
    install -m 755 mysql-galera  $DIST_DIR
    install -m 644 README        $DIST_DIR
    install -m 644 QUICK_START   $DIST_DIR

    # Strip binaries if not instructed otherwise
    if test "$NO_STRIP" != "yes"
    then
        for d in $GALERA_BINS $GALERA_LIBS \
                 $MYSQL_DIST_DIR/bin $MYSQL_DIST_DIR/lib $MYSQL_DIST_DIR/sbin
        do
            for f in $d/*
            do
                file $f | grep 'not stripped' >/dev/null && strip $f || :
            done
        done
    fi

fi # if [ $TAR == "yes" ]

if [ "$BIN_DIST" == "yes" ]
then
. bin_dist.sh
fi

if [ "$TAR" == "yes" ] || [ "$BIN_DIST" == "yes" ]
then

if [ "$RELEASE" != "" ]
then
    GALERA_RELEASE="galera-$RELEASE-$(uname -m)"
else
    GALERA_RELEASE="$WSREP_REV,$GALERA_REV"
fi

RELEASE_NAME=$(echo mysql-$MYSQL_VER-$GALERA_RELEASE | sed s/\:/_/g)
rm -rf $RELEASE_NAME
mv $DIST_DIR $RELEASE_NAME

# Hack to avoid 'file changed as we read it'-error 
sync
sleep 1

# Pack the release
tar -czf $RELEASE_NAME.tgz $RELEASE_NAME

fi # if [ $TAR == "yes"  || "$BIN_DIST" == "yes" ]

if [ "$TAR" == "yes" ] && [ "$INSTALL" == "yes" ]
then
    cmd="$GALERA_SRC/tests/scripts/command.sh"
    $cmd stop
    $cmd install $RELEASE_NAME.tgz
fi

get_arch()
{
    if file $MYSQL_SRC/sql/mysqld | grep "80386" >/dev/null 2>&1
    then
        echo "i386"
    else
        echo "amd64"
    fi
}

build_packages()
{
    pushd $GALERA_SRC/scripts/mysql

    local ARCH=$(get_arch)
    local WHOAMI=$(whoami)

    if [ $DEBIAN -eq 0 ] && [ "$ARCH" == "amd64" ]
    then
        ARCH="x86_64"
        export x86_64=$ARCH # for epm
    fi

    local STRIP_OPT=""
    [ "$NO_STRIP" == "yes" ] && STRIP_OPT="-g"

    export MYSQL_VER MYSQL_SRC GALERA_SRC RELEASE_NAME
    export WSREP_VER=${RELEASE:-"$WSREP_REV"}

    echo $MYSQL_SRC $MYSQL_VER $ARCH
    rm -rf $ARCH

    set +e
    if [ $DEBIAN -ne 0 ]
    then #build DEB
        local deb_basename="mysql-server-wsrep"
        pushd debian
        $SUDO_ENV $(which epm) -n -m "$ARCH" -a "$ARCH" -f "deb" \
             --output-dir $ARCH $STRIP_OPT $deb_basename
        RET=$?
        $SUDO /bin/chown -R $WHOAMI.users $ARCH
    else # build RPM
        echo "RPMs are now built by a separate script."
        return 1
    fi

    return $RET
}

if [ "$PACKAGE" == "yes" ]
then
    build_packages
fi
#
