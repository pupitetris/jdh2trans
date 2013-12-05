#!/usr/bin/perl

# For testing purposes, this program can be invoked in this fashion 
# to avoid module installation:

# $ perl -I Xam-Binding-Trans/lib ./example.pl ~/SamsungSDK/source/external/Samsung_Mobile_SDK/Docs/API\ Reference

use strict;
#use warnings FATAL => 'all';

use Data::Dumper;
use Xam::Binding::Trans;

# Command-line arguments.
my $BASEDIR = $ARGV[0]; # Base directory for the HTML documentation.

die 'BASEDIR not specified' if $BASEDIR eq '';


# Configuration:

# When using arg names as prefix to find enums, remove the "Info" and "Option" words.
$Xam::Binding::Trans::ARG_PREFIX_CLEANUP_RE = qr/(?:Info|Option)$/;

# When using get/set method names as prefix to find enums, remove the "Text" beginning word.
# For a various SpenObjectTextBox set/getters.
$Xam::Binding::Trans::METHOD_PREFIX_CLEANUP_RE = qr/(?:^Text|Type$)/;

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
	my $argname = uc ($meth->{ARGS}->[0]->{NAME});
	$argname = 'FEATURE' if $argname eq 'ID';
	my $prefix = $meth->{CLASS}->{FULLNAME} . ".${argname}_";
	my $values = $trans->_collect_values_by_prefix ($prefix);

	my $argname;
	if (scalar keys %$values == 0) {
		# Maybe nasty consts with unconventional names.
		if ($key eq 'com.samsung.android.sdk.multiwindow.SMultiWindow.isFeatureEnabled(int)') {
			$values = $trans->_collect_values_by_prefix ('com.samsung.android.sdk.multiwindow.SMultiWindow.MULTIWINDOW');
			$argname = 'type';
		} elsif ($key eq 'com.samsung.android.sdk.pen.Spen.isFeatureEnabled(int)') {
			$values = $trans->_collect_values_by_prefix ('com.samsung.android.sdk.pen.Spen.DEVICE_');
			$argname = 'type';
		} else {
			# OK, maybe it is not implemented.
			next;
		}
	}

	if (scalar keys %$values == 0) {
		$DB::single = 1;
		die;
	}

	my $new_enum = $trans->_create_enum_straight ($values, $argname);
	$trans->_method_set_arg_type ($meth, 0, $new_enum);
}

$DB::single = 1;

#$trans->outEnumFields ('com.package.name', 'path/to/Transforms/EnumFields.xml');
#$trans->outEnumMethods ('com.package.name', 'path/to/Transforms/EnumMethods.xml');

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

#$Data::Dumper::Varname = 'CLASSES';
#print Dumper ($trans->{CLASSES});

$Data::Dumper::Varname = 'CONSTS';
print Dumper ($trans->{CONSTS});

#$Data::Dumper::Varname = 'ENUMS';
#print Dumper ($trans->{ENUMS});

#$Data::Dumper::Varname = 'METHODS';
#print Dumper ($trans->{METHODS});

1;
