#!/usr/bin/perl

# For testing purposes, this program can be invoked in this fashion 
# to avoid module installation:

# $ perl -I ../Xam-Binding-Trans/lib ./samsung-sdk.pl ~/Work/components/SamsungSDK/source

use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use Xam::Binding::Trans;

# Command-line arguments.
my $BASEDIR = shift @ARGV; # Base directory for the HTML documentation.
die 'BASEDIR not specified' if !$BASEDIR;

# Configuration:

# There's an error in documentation; the terms ERASER and REMOVER are used interchangingly.
# We'll stay with ERASER.
$Xam::Binding::Trans::PARAM_DESC_CORRECTIONS = {
	qr/REMOVER/ => 'ERASER'
};

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

# Render packages as Samsung.AndroidSDK or we'll get confusions with the namespaces otherwise.
$Xam::Binding::Trans::PACKAGE_CLR_TRANSFORM_RE = qr/^com.samsung.android.sdk/;
$Xam::Binding::Trans::PACKAGE_CLR_TRANSFORM_SUBST = 'Samsung.AndroidSdk';

# Parse the documentation.
sub parse {
	my $basedir = shift;

	# Create parser instance:
	my $trans = Xam::Binding::Trans->new ();
	$trans->parse ($basedir);

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

	return $trans;
}

sub process_pkg {
	my $trans = shift;
	my $pkg = shift;
	my $dir = shift;

	$dir = "$BASEDIR/$dir";
	$trans->printEnumFieldMapping ("$dir/Transforms/EnumFields.xml", $pkg);
	$trans->printEnumMethodMapping ("$dir/Transforms/EnumMethods.xml", $pkg);
	$trans->printMetadata ("$dir/Transforms/Metadata.xml", "$dir/obj/Debug/api.xml", $pkg);
}

my $dumpfile = '../dumps/state';

#my $trans = parse ($BASEDIR . '/external/Samsung_Mobile_SDK/Docs/API Reference'); $trans->dump ($dumpfile);
my $trans = Xam::Binding::Trans::load ($dumpfile);

process_pkg ($trans, 'com.samsung.android.sdk', 'Samsung.Android.Sdk');

process_pkg ($trans, qr/^com.samsung.android.sdk.visualview/, 'Samsung.Android.Sdk.Visualview');
system ("patch -d $BASEDIR -p0 < samsung-sdk-visualview.patch");

process_pkg ($trans, 'com.samsung.android.sdk.chord', 'Samsung.Android.Sdk.Chord');

process_pkg ($trans, 'com.samsung.android.sdk.gesture', 'Samsung.Android.Sdk.Gesture');

process_pkg ($trans, 'com.samsung.android.sdk.imagefilter', 'Samsung.Android.Sdk.Imagefilter');
#system ("patch -d $BASEDIR -p0 < samsung-sdk-imagefilter.patch");

process_pkg ($trans, qr/^com.samsung.android.sdk.look/, 'Samsung.Android.Sdk.Look');

process_pkg ($trans, qr/^com.samsung.android.sdk.pen/, 'Samsung.Android.Sdk.Pen');

1;
