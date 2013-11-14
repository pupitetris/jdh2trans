#!/usr/bin/perl

# For testing purposes, this program can be invoked in this fashion 
# to avoid module installation:

# $ perl -I Xam-Binding-Trans/lib ./example.pl ~/SamsungSDK/source/external/Samsung_Mobile_SDK/Docs/API\ Reference

use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use Xam::Binding::Trans;

# Command-line arguments.
my $BASEDIR = $ARGV[0]; # Base directory for the HTML documentation.

die 'BASEDIR not specified' if $BASEDIR eq '';

my $trans = Xam::Binding::Trans->new ();
$trans->parse ($BASEDIR);
#$trans->outEnumFields ('com.package.name', 'path/to/Transforms/EnumFields.xml');
#$trans->outEnumMethods ('com.package.name', 'path/to/Transforms/EnumMethods.xml');

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

$Data::Dumper::Varname = 'CLASSES';
print Dumper ($trans->{CLASSES});

$Data::Dumper::Varname = 'CONSTS';
print Dumper ($trans->{CONSTS});

1;
