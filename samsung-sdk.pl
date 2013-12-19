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


# Configuration:

# When using param names as prefix to find enums, remove the "Info" and "Option" words.
$Xam::Binding::Trans::PARAM_PREFIX_CLEANUP_RE = qr/(?:Info|Option)$/;

# When using get/set method names as prefix to find enums, remove the "Text" beginning word.
# For a various SpenObjectTextBox set/getters.
$Xam::Binding::Trans::METHOD_PREFIX_CLEANUP_RE = qr/(?:^Text|Type$)/;

# duration (for com.samsung.android.sdk.visualview.SVSlide) is always in ms.
$Xam::Binding::Trans::PARAM_NAME_ENUM_EXCLUDE_RE = qr/^duration$/;

# Consts named "SUCCESS" are ignored when looking for max common prefix.
%Xam::Binding::Trans::ENUM_IGNORE_VALUES_FOR_ENUM_NAME = (
	'SUCCESS' => 1
	);

# This is the default: non-int constants are ommited from CONSTS structure to simplify reports.
$Xam::Binding::Trans::ONLY_PARSE_INT_CONSTANTS = 1;


# Create parser instance:
my $trans = Xam::Binding::Trans->new ();
$trans->parse ($BASEDIR);

# Some classes are supposed to implement SsdkInterface:isFeatureEnabled(int) and 
# the valid values provided by the class for this method are not explicitly documented.
foreach my $key (keys %{$trans->{METHODS}}) {
	next if $key !~ /isFeatureEnabled\(int\)$/;

	my $meth = $trans->{METHODS}->{$key};
	my $param_name = uc ($meth->{PARAMS}->[0]->{NAME});
	$param_name = 'FEATURE' if $param_name eq 'ID';
	my $prefix = $meth->{CLASS}->{FULLNAME} . ".${param_name}_";
	my $values = $trans->_collect_values_by_prefix ($prefix);

	if (scalar keys %$values == 0) {
		# Maybe nasty consts with unconventional names.
		if ($key eq 'com.samsung.android.sdk.multiwindow.SMultiWindow.isFeatureEnabled(int)') {
			$values = $trans->_collect_values_by_prefix ('com.samsung.android.sdk.multiwindow.SMultiWindow.MULTIWINDOW');
			$param_name = 'type';
		} elsif ($key eq 'com.samsung.android.sdk.pen.Spen.isFeatureEnabled(int)') {
			$values = $trans->_collect_values_by_prefix ('com.samsung.android.sdk.pen.Spen.DEVICE_');
			$param_name = 'type';
		} else {
			# OK, maybe it is not implemented.
			next;
		}
	}

	if (scalar keys %$values == 0) {
		$DB::single = 1;
		die;
	}

	my $new_enum = $trans->_create_enum_straight ($values, $param_name);
	$trans->_method_set_param_type ($meth, 0, $new_enum);
}

# Animation types
my $pkg = 'com.samsung.android.sdk.visualview.animation';
my $values = $trans->_collect_values_by_prefix ($pkg . '.SVAnimation.');
my $enum = $trans->_create_enum_straight ($values, 'TYPE');
$trans->_method_set_param_type ("$pkg.SVBasicAnimation.constructor(int,float[],float[])", 0, $enum);
$trans->_method_set_param_type ("$pkg.SVBasicAnimation.constructor(int,float,float)", 0, $enum);
$trans->_method_set_param_type ("$pkg.SVKeyFrameAnimation.constructor(int)", 0, $enum);

$DB::single = 1;

$trans->dump ();

#$trans->printEnumFieldMapping (\*STDOUT, sort keys %{$trans->{PACKAGES}});
#$trans->printEnumMethodMapping (\*STDOUT, qr/^com.samsung.android.sdk.visualview/);
#$trans->printMetadata (\*STDOUT);

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

#$Data::Dumper::Varname = 'CLASSES';
#print Dumper ($trans->{CLASSES});

#$Data::Dumper::Varname = 'CONSTS';
#print Dumper ($trans->{CONSTS});

#$Data::Dumper::Varname = 'ENUMS';
#print Dumper ($trans->{ENUMS});

#$Data::Dumper::Varname = 'METHODS';
#print Dumper ($trans->{METHODS});

#$Data::Dumper::Varname = 'SELF';
#print Dumper ($trans);

1;
