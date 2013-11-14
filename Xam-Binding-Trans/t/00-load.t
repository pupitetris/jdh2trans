#!perl -T
use 5.10;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Xam::Binding::Trans' ) || print "Bail out!\n";
}

diag( "Testing Xam::Binding::Trans $Xam::Binding::Trans::VERSION, Perl $], $^X" );
