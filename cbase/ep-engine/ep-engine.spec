Name:           ep-engine
Version:        1.8.0
Release:        903.1%{dist}
Epoch:          0
Summary:        EP engine for memcached
Group:          System Environment/Libraries
License:        DSAL
URL:            http://github.com/northscale/bucket_engine
Source0:        http://github.com/northscale/bucket_engine/downloads/%{name}-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-%(%{__id_u} -n)
BuildRequires:	memcached-devel >= 1.4.4-902

%description
This memcached engine provides ep and isolation between other
memcached engine instances.

%prep
%setup -q -n %{name}-%{version}

%build
config/autorun.sh
%configure 

make %{?_smp_mflags}

#%check
#make test

%install
rm -rf %{buildroot}
make install DESTDIR=%{buildroot}
#find $RPM_BUILD_ROOT -type f -name '*.la' -exec rm -f {} ';'

#find %{buildroot} -type f -name 'memcacheConstants.py*' -exec rm -f {} ';'
#find %{buildroot} -type f -name 'mc_bin_client.py*' -exec rm -f {} ';'
#find %{buildroot} -type f -name 'sqlite3' -exec rm -f {} ';'
mv %{buildroot}/%{_bindir}/sqlite3 %{buildroot}/%{_bindir}/cbsqlite3

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%dir %attr (0755, root, bin) %{_libdir}
%dir %attr (0755, root, bin) %{_datadir}
%attr (-, root, bin) %{_libdir}/memcached/ep.so*
#%attr (-, root, bin) %{_datadir}/bucket_engine/*

%{_bindir}/cbbackup-merge-incremental
%{_bindir}/cbvbucketctl
%{_bindir}/cbbackup-incremental
%{_bindir}/cbdbmaint
%{_bindir}/cbadm-online-update
%{_bindir}/cbadm-tap-registration
%{_bindir}/cbstats
%{_bindir}/cbadm-online-restore
%{_bindir}/cbflushctl
%{_bindir}/squasher.sql
%{_bindir}/cbsqlite3
%{_bindir}/cbdbconvert
%{_bindir}/cbdbupgrade
%{_bindir}/cbrestore
%{_bindir}/analyze_core
%{_bindir}/cbbackup

%{_libdir}/memcached/ep.la
%{_libdir}/memcached/ep_testsuite.la
%{_libdir}/memcached/ep_testsuite.so
%{_libdir}/memcached/ep_testsuite.so.0
%{_libdir}/memcached/ep_testsuite.so.0.0.0
%{_libdir}/memcached/timing_tests.la
%{_libdir}/memcached/timing_tests.so
%{_libdir}/memcached/timing_tests.so.0
%{_libdir}/memcached/timing_tests.so.0.0.0

%{_mandir}/man1/cbadm-online-update.1m.gz
%{_mandir}/man1/cbbackup-incremental.1m.gz


#%{_libdir}/memcached/bucket_engine.a

%{_libdir}/python/*


%changelog
* Mon Feb  8 2010 Trond Norbye <trond.norbye@gmail.com> - 1.0-1
- Initial
