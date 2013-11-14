use 5.10;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

name     'Xam-Binding-Trans';
all_from 'lib/Xam/Binding/Trans.pm';
author   q{Arturo Espinosa <arturo.espinosa@xamarin.com>};
license  'apache';

perl_version 5.10;

tests_recursive('t');

resources (
   #homepage   => 'http://yourwebsitehere.com',
   #IRC        => 'irc://irc.perl.org/#Xam-Binding-Trans',
   license    => 'http://www.apache.org/licenses/LICENSE-2.0',
   #repository => 'git://github.com/Arturo Espinosa/Xam-Binding-Trans.git',
   bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Xam-Binding-Trans',
);

configure_requires (
   'Module::Install' => 0,
);

build_requires (
   'Test::More' => 0,
);

requires (
   #'ABC'              => 1.6,
   #'Foo::Bar::Module' => 5.0401,
);

install_as_cpan;
auto_install;
WriteAll;
