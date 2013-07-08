Summary: vbucket library for Couchbase
Name: libvbucket
Version: 1.8.0
Release: 901.1
Vendor: Couchbase, Inc.
Packager: Couchbase SDK Team <support@couchbase.com>
License: Apache-2
Group: System Environment/Libraries
URL: http://www.couchbase.com
Source: %{name}-%{version}.tar.gz
#BuildRoot: %{_topdir}/build/%{name}-%{version}-%{release}

%description
libvbucket is a library providing vbucket distribution layer for Couchbase
clients.

%package devel
Group: Development/Libraries
Summary: vbucket library for Couchbase - Header files
Requires: %{name}

%description devel
Development files for the vbucket library for Couchbase.

%prep
%setup -q -n %{name}-%{version}
echo 'm4_define([VERSION_NUMBER], [%{version}])' >m4/version.m4
config/autorun.sh
%configure

%build
%{__make} %{_smp_mflags}

%install
%{__make} install DESTDIR="%{buildroot}" AM_INSTALL_PROGRAM_FLAGS=""

%clean
%{__rm} -rf %{buildroot}

%post -n %{name} -p /sbin/ldconfig

%postun -n %{name} -p /sbin/ldconfig

%files
%defattr(-, root, root)
%{_libdir}/libvbucket.so.*

%files devel
%defattr(-, root, root)
%doc README.markdown LICENSE
%{_bindir}/vbucketkeygen
%{_bindir}/vbuckettool
%{_includedir}/libvbucket
%{_libdir}/libvbucket.la
%{_libdir}/libvbucket.so
%{_libdir}/pkgconfig/libvbucket.pc
%{_mandir}/**/*

%changelog
* Tue Mar 06 2012 Sergey Avseyev <sergey@couchbase.com> - 1.8.0.3
[Mark Nunberg]
- Fixed libvbucket.pc.in

[Sergey Avseyev]
- Always sign deb packages

* Tue Feb 14 2012 Matt Ingenthron <matt@couchbase.com> - 1.8.0.2
[Matt Ingenthron]
- Updated package metadata for 1.8.0.2 release.

[Pierre Joye]
- Fix windows build on <vc10

[Sergey Avseyev]
- Fix vbucket_compare() for ketama distribution
- Fill REST api hostname for Ketama distribution
- make test more portable (for windows)

[Trond Norbye]
- Add an MT-safe creation interface
- Fixed memory leak
- Fix up NMakefile
- Fix visibility attribute for compiling

* Sun Jan 22 2012 Sergey Avseyev <sergey.avseyev@gmail.com> - 1.8.0.1
- Unbundled release from Couchbase Server 1.8.0.  This release allows
  for libvbucket to be installed in common locations.  There have been
  minor changes to support portability to c89 based systems.

* Mon Dec 05 2011 Sergey Avseyev <sergey.avseyev@gmail.com> - 1.7.2
- Initial packaging
