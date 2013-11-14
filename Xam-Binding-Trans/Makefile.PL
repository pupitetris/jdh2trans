use 5.10.0;
use strict;
use warnings FATAL => 'all';
use inc::Module::Install;

name     'Xam-Binding-Trans';
all_from 'lib/Xam/Binding/Trans.pm';
author   q{Arturo Espinosa <arturo.espinosa@xamarin.com>};
license  'apache';

perl_version '5.10';

tests_recursive('t');

resources (
   homepage   => 'https://github.com/pupitetris/jdh2trans',
   license    => 'http://www.apache.org/licenses/LICENSE-2.0',
   repository => 'git://github.com/Arturo Espinosa/Xam-Binding-Trans.git',
   bugtracker => 'https://github.com/pupitetris/jdh2trans/issues',
);

configure_requires (
   'Module::Install' => 0,
);

build_requires (
   'Test::More' => 0,
);

requires (
  'HTML::TreeBuilder' => 5,
);

install_as_site;
auto_install;
WriteAll;
