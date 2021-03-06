#
# rpm spec for xtrabackup
#
%{!?redhat_version:%define redhat_version 5}
%{!?buildnumber:%define buildnumber 1}
%define distribution  rhel%{redhat_version}
%define release       %{buildnumber}.%{distribution}

# xtrabackup version 2.0.6-521
%define xtrabackup_version 2.0.6
%define release 521
%define xtrabackup_revision 521

%{!?xtrabackup_revision:%define xtrabackup_revision undefined}

%define __os_install_post /usr/lib/rpm/brp-compress

Summary: XtraBackup online backup for MySQL / InnoDB 
Name: xtrabackup
Version: %{xtrabackup_version}
Release: %{release}%{?dist}
Group: Server/Databases
License: GPLv2
Packager: Percona Development Team <mysql-dev@percona.com>
URL: http://www.percona.com/software/percona-xtrabackup/
Source: xtrabackup-%{xtrabackup_version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root
Requires: mysql
Provides: xtrabackup
Obsoletes: xtrabackup
BuildRequires: libaio-devel


Source1: percona-server-5.1-xtrabackup.tar.bz2
Source2: percona-server-5.5-xtrabackup.tar.bz2
Source3: mysql-5.1.59.tar.gz
Source4: mysql-5.5.16.tar.gz

%description
Percona XtraBackup is OpenSource online (non-blockable) backup solution for InnoDB and XtraDB engines.

%package test
Summary: Test suite for Percona Xtrabackup
Group: Applications/Databases
Requires: xtrabackup
AutoReqProv: no

%description test
This package contains the test suite for Percona Xtrabackup


%prep
%setup -q
%setup -T -D -a 1
%setup -T -D -a 2

# to put mysql-5.1 in topdir and percona-server 5.1
cp %{SOURCE3} %{_builddir}/%{name}-%{version}/
pushd %{_builddir}/%{name}-%{version}/percona-server-5.1-xtrabackup/ &&
	ln -nsf ../mysql-5.1*.tar.gz ./
popd

#ln -sf ../mysql-5.1.59.tar.gz %{_builddir}/%{name}-%{version}/percona-server-5.1-xtrabackup/

# to put mysql-5.5 in topdir and percona-server 5.5
cp %{SOURCE4} %{_builddir}/%{name}-%{version}/
pushd %{_builddir}/%{name}-%{version}/percona-server-5.5-xtrabackup/ &&
	ln -nsf ../mysql-5.5*.tar.gz ./
popd


cp %{SOURCE3} %{_builddir}/%{name}-%{version}/
ln -sf ../mysql-5.1.59.tar.gz %{_builddir}/%{name}-%{version}/percona-server-5.1-xtrabackup/

%build
set -ue
export CC=${CC-"gcc"}
export CXX=${CXX-"gcc"}
export CFLAGS="%{optflags} -DXTRABACKUP_VERSION=\\\"%{xtrabackup_version}\\\" -DXTRABACKUP_REVISION=\\\"%{xtrabackup_revision}\\\"" 
CXXFLAGS="${CXXFLAGS:-%optflags}"
export CXXFLAGS="$CXXFLAGS -DXTRABACKUP_VERSION=\\\"%{xtrabackup_version}\\\" -DXTRABACKUP_REVISION=\\\"%{xtrabackup_revision}\\\" -fno-exceptions" 
#AUTO_DOWNLOAD=yes ./utils/build.sh 5.1
./utils/build.sh 5.1
cp src/xtrabackup_51 src/xbstream .
#AUTO_DOWNLOAD=yes ./utils/build.sh xtradb
./utils/build.sh xtradb
cp src/xtrabackup .
#AUTO_DOWNLOAD=yes ./utils/build.sh xtradb55
./utils/build.sh xtradb55
cp src/xtrabackup_55 .
#CXX="${CXX_56-"g++"}" AUTO_DOWNLOAD=yes ./utils/build.sh xtradb56
#cp src/xtrabackup_56 .

%install
[ "%{buildroot}" != '/' ] && rm -rf %{buildroot}
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_datadir}
# install binaries and configs

install -m 755 xtrabackup %{buildroot}%{_bindir}
install -m 755 xtrabackup_55 %{buildroot}%{_bindir}
#install -m 755 xtrabackup_56 %{buildroot}%{_bindir}
install -m 755 innobackupex %{buildroot}%{_bindir}
ln -s innobackupex %{buildroot}%{_bindir}/innobackupex-1.5.1
install -m 755 xtrabackup_51 %{buildroot}%{_bindir}
install -m 755 xbstream %{buildroot}%{_bindir}
cp -R test %{buildroot}%{_datadir}/percona-xtrabackup-test

%clean
[ "%{buildroot}" != '/' ] && rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{_bindir}/innobackupex
%{_bindir}/innobackupex-1.5.1
%{_bindir}/xtrabackup
%{_bindir}/xtrabackup_51
%{_bindir}/xtrabackup_55
#%{_bindir}/xtrabackup_56
%{_bindir}/xbstream
%doc COPYING

%files -n xtrabackup-test
%{_datadir}/percona-xtrabackup-test

###
### eof
###


%changelog
* Mon Sep 27 2010 Aleksandr Kuzminsky
- Version 1.4

* Wed Jun 30 2010 Aleksandr Kuzminsky
- Version 1.3 ported on Percona Server 11

* Thu Mar 11 2010 Aleksandr Kuzminsky
- Ported to MySQL 5.1 with InnoDB plugin

* Fri Mar 13 2009 Vadim Tkachenko
- initial release


