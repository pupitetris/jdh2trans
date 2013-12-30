package Xam::Binding::Trans;

use 5.10.0;
use strict;
use warnings FATAL => 'all';

use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use Data::Dumper;
use XML::XPath;
use Carp qw(croak carp);

=head1 NAME

Xam::Binding::Trans - Generate Enum mappings for Xamarin Studio binding library projects.

=head1 VERSION

Version 0.9

=cut

our $VERSION = '0.9';

=head1 SYNOPSIS

This module implements a class for enumeration mapping generation. An object 
from this class can read javaDoc HTML files and output XML mapping files
describing inferred enumerations and those methods which use these enumerations.

Code sample:

    use Xam::Binding::Trans;

    my $trans = Xam::Binding::Trans->new ();
    $trans->parse ('dir/to/javadoc-html');
    $trans->printEnumFieldMapping ('path/to/Transforms/EnumFields.xml'); # All found packages by default.
    $trans->printEnumMethodMapping (\*STDOUT, 'com.package.name', 'com.other.package'); # Two packages.
    $trans->printMetadata (\*STDOUT, 'api.xml', qr/^com.package.name/); # com.package.name and all of its subpackages.
    $trans->dump ('my_dump'); # Save the state of the object.

    my $new_trans = Xam::Binding::Trans::load ('my_dump'); # It's faster to load than to re-parse.
    $new_trans->printEnumFieldMapping ('path/to/Transforms/EnumFields-2.xml'); # Should print an identical file.
    ...

=head1 METHODS

=head2 Xam::Binding::Trans->new ()

Constructor. Creates a new mapper object.

=cut

sub new {
	my $class = shift;
	my $self = {
		BASEDIR => '',
		PACKAGES => {},
		CONSTS => {},
		CLASSES => {},
		METHODS => {},
		FIELDS => {},
		ENUMS => {}
	};
	bless $self, $class;
	return $self;
}

=head2 Xam::Binding::Trans::load (dump_file)

Load the contents of the file located at dump_file into a new object, restoring the saved parsing state.

=cut

sub load {
	my $file = shift;
	my $self = do $file;
	croak if !$self;
	return $self;
}

=head2 $obj->dump (dump_file)

Dump the state of the object onto a file or file descriptor for later reuse, avoiding re-parsing.

=cut

sub dump {
	my $self = shift;
	my $file = shift // \*STDOUT;

	my $fd;
	if (ref $file eq 'GLOB') {
		$fd = $file;
	} else {
		open $fd, ">$file" || croak;
	}

	my $d = Data::Dumper->new ([$self], ['self']);
	$d->Purity (1);
	$d->Indent (1);
	$d->Sortkeys (1);

	print $fd $d->Dump ();
	print $fd "\$self;\n"; # so that 'do' returns the object at the end when loading.

	close $fd;
}

sub DESTROY {
	my $self = shift;
}

=head2 $obj->parse (dir, packages ...)

Parse the structure of the given packages inside the dir path. Parse all packages found in the javaDoc
if no packages are specified. Restricting packages to parse is a good idea since parsing methods
within classes is expensive.

=cut

sub parse {
	my $self = shift;
	my $dir = shift // croak 'dir not specified for parse method.';
	my @packages = @_;

	$self->{BASEDIR} = $dir;

	$self->{PACKAGES} = $self->_parse_packages ();
	$self->{CONSTS} = $self->_parse_constants ();

	if (scalar @packages > 0) {
		my %pkgs = map { $_ => $self->{PACKAGES}{$_} } @packages;
		$self->{CLASSES} = $self->_parse_classes (\%pkgs);
	} else {
		$self->{CLASSES} = $self->_parse_classes ($self->{PACKAGES});
	}

	$self->{METHODS} = $self->_parse_methods ($self->{CLASSES});
}

sub _selectPrintPackages {
	my $self = shift;
	my @packages = @_;

	if (scalar @packages == 0) {
		@packages = sort keys %{$self->{PACKAGES}};
	} else {
		for (my $i = 0; $i < scalar @packages; $i++) {
			my $p = $packages[$i];
			if (ref $p eq 'Regexp') {
				splice (@packages, $i, 1);
				foreach my $pkg (sort keys %{$self->{PACKAGES}}) {
					if ($pkg =~ /$p/) {
						splice (@packages, $i, 0, $pkg);
						$i ++;
					}
				}
				$i --; # For the re which was removed.
			}
		}
	}

	return @packages;
}

sub numeric {
	{ $a <=> $b }
}

sub xpath_pkg_path {
	my $pkgname = shift;

	return "/api/package[\@name='$pkgname']";
}

sub xpath_class_path {
	my $class = shift;

	return xpath_pkg_path ($class->{PKG}) .
		"/$class->{TYPE}\[\@name='$class->{NAME}']";
}

sub xpath_method_path {
	my $meth = shift;

	my $param_count = scalar @{$meth->{PARAMS}};
	my $param_path = "count(parameter)=$param_count";
	$i = 0;
	while ($i < $param_count) {
		my $param = $meth->{PARAMS}[$i];
		my $type = $param->{TYPE_ORIG}? $param->{TYPE_ORIG}: $param->{TYPE};
		$i++;
		$param_path .= " and parameter[$i][\@type='$type']";
	}

	return xpath_class_path ($meth->{CLASS}) .
		"/$meth->{TYPE}[" . (($meth->{TYPE} eq 'constructor')? '': "\@name='$meth->{NAME} and ") .
		"$param_path]";
}

sub xpath_check_path {
	my $xp = shift;
	my $path = shift;
	
	return 1 if !$xp || $xp->exists ($path);
	print STDERR "Metadata: Path $path matches no nodes.\n";
	return 0;
}

=head2 $obj->printEnumFieldMapping (xml_file, packages ...)

Write an EnumFields.xml mapping file for the given packages at the xml_file location. All loaded packages
will be processed if no packages are specified.

=cut

sub printEnumFieldMapping {
	my $self = shift;
	my $xml_file = shift;

	my @packages = $self->_selectPrintPackages (@_);

	my $fd;
	if (ref $xml_file eq 'GLOB') {
		$fd = $xml_file;
	} else {
		open $fd, ">$xml_file" || croak;
	}

	print $fd "<enum-field-mappings>\n";
	
	foreach my $pkgname (@packages) {
		my $pkg = $self->{PACKAGES}{$pkgname};
		croak "Package $pkgname not found" if !$pkg;
		print $fd "\n\n\t<!-- Package $pkgname -->\n";
		my $jni_pkg = pkgname_to_jni ($pkgname);
		my $clr_pkg = pkgname_to_clr ($pkgname);

		foreach my $class_key (sort keys %{$pkg->{CLASSES}}) {
			my $class = $pkg->{CLASSES}{$class_key};
			my $classname = $class->{NAME};
			my $jni_class = "$jni_pkg/$classname";

			my $name_prefix = $classname;
			$name_prefix =~ s/\.//g;

			foreach my $enum_key (sort keys %{$class->{ENUMS}}) {
				my $enum = $class->{ENUMS}{$enum_key};

				print $fd "\n\t<mapping\n";
				print $fd "\t\tclr-enum-type=\"$clr_pkg.$name_prefix" . 
					name_const_to_camel ($enum->{NAME}) . "\"\n";
				print $fd "\t\tjni-$class->{TYPE}=\"$jni_pkg/$classname\">\n\n";
				
				foreach my $val (sort numeric keys %{$enum->{PAIRS}}) {
					my $pair = $enum->{PAIRS}{$val};
					print $fd "\t\t<field value=\"$val\" jni-name=\"$pair->{CONST}{NAME}\" clr-name=\"" . 
						name_const_to_camel ($pair->{NAME}) . "\" />\n";
				}

				print $fd "\t</mapping>\n";
			}
		}
	}

	print $fd "\n</enum-field-mappings>\n";
}

=head2 $obj->printEnumMethodMapping (xml_file, packages ...)

Write an EnumMethods.xml mapping file for the given packages at the xml_file location. All loaded packages
will be processed if no packages are specified.

=cut

sub printEnumMethodMapping {
	my $self = shift;
	my $xml_file = shift;

	my @packages = $self->_selectPrintPackages (@_);

	my $fd;
	if (ref $xml_file eq 'GLOB') {
		$fd = $xml_file;
	} else {
		open $fd, ">$xml_file" || croak;
	}

	print $fd "<enum-method-mappings>\n";

	foreach my $pkgname (@packages) {
		my $pkg = $self->{PACKAGES}{$pkgname};
		croak "Package $pkgname not found" if !$pkg;
		print $fd "\n\n\t<!-- Package $pkgname -->\n";
		my $jni_pkg = pkgname_to_jni ($pkgname);

		foreach my $class_key (sort keys %{$pkg->{CLASSES}}) {
			my $class = $pkg->{CLASSES}{$class_key};
			my $classname = $class->{NAME};
			my $jni_class = "$jni_pkg/$classname";
			my $mapping_flag = 0; # We only print mapping tag if we find a suitable method.

			foreach my $h ($class->{CTORS}, $class->{METHODS}) {
				foreach my $meth_key (sort keys %$h) {
					next if $meth_key !~ /enum:/;
					my $meth = $h->{$meth_key};

					# Method name is ambiguous and we have to do the transform in Metadata.xml.
					next if $class->{HIST}{$meth->{NAME}} > 1;

					if (!$mapping_flag) {
						$mapping_flag = 1;
						print $fd "\n\t<mapping\n";
						print $fd "\t\tjni-$class->{TYPE}=\"$jni_pkg/$classname\">\n\n";
					}

					foreach my $param (@{$meth->{PARAMS}}) {
						next if ref $param->{TYPE} ne 'ENUM';

						my $clr_prefix = $param->{TYPE}{CLASS}{NAME};
						$clr_prefix =~ s/\.//g;
						$clr_prefix = pkgname_to_clr ($param->{TYPE}{PKG}) . ".$clr_prefix";
						
						print $fd 
							"\t\t<method\n" .
							"\t\t\tjni-name=\"$meth->{NAME}\"\n" .
							"\t\t\tparameter=\"$param->{NAME}\"\n" .
							"\t\t\tclr-enum-type=\"$clr_prefix" .
							name_const_to_camel ($param->{TYPE}{NAME}) . "\" />\n\n";
					}

					if (ref $meth->{RETURN} eq 'ENUM') {
						my $clr_prefix = $meth->{RETURN}{CLASS}{NAME};
						$clr_prefix =~ s/\.//g;
						$clr_prefix = pkgname_to_clr ($meth->{RETURN}{PKG}) . ".$clr_prefix";
						
						print $fd 
							"\t\t<method\n" .
							"\t\t\tjni-name=\"$meth->{NAME}\"\n" .
							"\t\t\tparameter=\"return\"\n" .
							"\t\t\tclr-enum-type=\"$clr_prefix" .
							name_const_to_camel ($meth->{RETURN}{NAME}) . "\" />\n\n";
					}
				}
			}

			if ($mapping_flag) {
				print $fd "\t</mapping>\n";
			}
		}
	}

	print $fd "\n</enum-method-mappings>\n";
}

=head2 $obj->printMetadata (xml_file, api_file, packages ...)

Write an Metadata.xml file for the given packages at the xml_file location. All loaded packages
will be processed if no packages are specified. api_file is the api.xml file produced by Xamarin
Studio after compiling the binding package; use the empty string if none is available.

=cut

sub printMetadata {
	my $self = shift;
	my $xml_file = shift;
	my $api_file = shift;

	my @packages = $self->_selectPrintPackages (@_);

	my $xp;
	$xp = XML::XPath->new (filename => $api_file) if $api_file;

	my $fd;
	if (ref $xml_file eq 'GLOB') {
		$fd = $xml_file;
	} else {
		open $fd, ">$xml_file" || croak;
	}

	print $fd "<metadata>\n";

	print $fd "\n\t<!-- Namespace renaming -->\n";
	foreach my $pkgname (@packages) {
		my $pkg = $self->{PACKAGES}{$pkgname};
		croak "Package $pkgname not found" if !$pkg;
		my $jni_pkg = pkgname_to_jni ($pkgname);
		my $clr_pkg = pkgname_to_clr ($pkgname);

		my $path = "/api/package[\@name='$pkgname']";
		xpath_check_path ($xp, $path);
		print $fd "\t\t<attr path=\"$path\" name=\"managedName\">$clr_pkg</attr>\n";
	}

	print $fd "\n\t<!-- Parameter names -->\n";
	foreach my $pkgname (@packages) {
		print $fd "\t\t<!-- Package $pkgname -->\n";
		my $pkg = $self->{PACKAGES}{$pkgname};

		foreach my $class_key (sort keys %{$pkg->{CLASSES}}) {
			my $class = $pkg->{CLASSES}{$class_key};

			my $found_in_class = 0;
			foreach my $h ($class->{CTORS}, $class->{METHODS}) {
				foreach my $meth_key (sort keys %$h) {
					my $meth = $h->{$meth_key};

					my $meth_path = xpath_method_path ($meth);
					next if !xpath_check_path ($xp, $meth_path);

					if (!$found_in_class) {
						$found_in_class = 1;
						print $fd "\t\t\t<!-- " . 
							(($class->{TYPE} eq 'interface')? 'Interface': 'Class') .
							" $class->{NAME} -->\n";
					}

					print $fd "\t\t\t\t<!-- Method $meth->{PROTO} -->\n";
					foreach my $param (@{$meth->{PARAMS}}) {
						my $path = "$meth_path/parameter[position()=$param->{POS}]";
						if (xpath_check_path ($xp, $path)) {
							print $fd "\t\t\t\t\t<attr path=\"$path\"\n";
							print $fd "\t\t\t\t\t\tname=\"name\">$param->{NAME}</attr>\n";
						}
					}
				}
			}
		}
	}

	# Event handlers
	my $found_events = 0;
	foreach my $pkgname (@packages) {
		my $pkg = $self->{PACKAGES}{$pkgname};

		my $found_in_pkg = 0;
		foreach my $class_key (sort keys %{$pkg->{CLASSES}}) {
			my $class = $pkg->{CLASSES}{$class_key};

			my $found_in_class = 0;
			foreach my $h ($class->{METHODS}) {
				foreach my $meth_key (sort keys %$h) {
					my $meth = $h->{$meth_key};
					my $methname = $meth->{NAME};
					
					next if $methname !~ /^[oO]n./;

					my $evtname = $methname;
					$evtname =~ s/^o/O/;

					my $meth_path = xpath_method_path ($meth);
					next if !xpath_check_path ($xp, $meth_path);

					if (!$found_events) {
						$found_events = 1;
						print $fd "\n\t<!-- Events -->\n";
					}

					if (!$found_in_pkg) {
						$found_in_pkg = 1;
						print $fd "\t\t<!-- Package $pkgname -->\n";
					}

					if (!$found_in_class) {
						$found_in_class = 1;
						print $fd "\t\t\t<!-- " . 
							(($class->{TYPE} eq 'interface')? 'Interface': 'Class') .
							" $class->{NAME} -->\n";
					}

					print $fd "\t\t\t\t<!-- Method $meth->{PROTO} -->\n";

					print $fd "\t\t\t\t\t<attr path=\"$meth_path\"\n";
					print $fd "\t\t\t\t\t\tname=\"eventName\">$evtname</attr>\n";
				}
			}
		}
	}

	# Workaround for EnumMethods not supporting overloads
	my $found_overloads = 0;
	foreach my $pkgname (@packages) {
		my $pkg = $self->{PACKAGES}{$pkgname};

		my $found_in_pkg = 0;
		foreach my $class_key (sort keys %{$pkg->{CLASSES}}) {
			my $class = $pkg->{CLASSES}{$class_key};

			my $found_in_class = 0;
			foreach my $h ($class->{CTORS}, $class->{METHODS}) {
				foreach my $meth_key (sort keys %$h) {
					next if $meth_key !~ /enum:/; # We are looking for methods that use enums.
					my $meth = $h->{$meth_key};
					my $methname = $meth->{NAME};
					
					next if $class->{HIST}{$methname} < 2; # Method has to be an overload.

					if (!$found_overloads) {
						$found_overloads = 1;
						print $fd "\n\t<!-- Workarounds for EnumMethods not supporting overloads -->\n";
					}

					if (!$found_in_pkg) {
						$found_in_pkg = 1;
						print $fd "\t\t<!-- Package $pkgname -->\n";
					}

					if (!$found_in_class) {
						$found_in_class = 1;
						print $fd "\t\t\t<!-- " . 
							(($class->{TYPE} eq 'interface')? 'Interface': 'Class') .
							" $class->{NAME} -->\n";
					}

					my $meth_path = xpath_method_path ($meth);
					next if !xpath_check_path ($xp, $meth_path);

					print $fd "\t\t\t\t<!-- Method $meth->{PROTO} -->\n";
					foreach my $param (@{$meth->{PARAMS}}) {
						next if ref $param->{TYPE} ne 'ENUM';
						my $path = "$meth_path/parameter[position()=$param->{POS}]";
						if (xpath_check_path ($xp, $path)) {
							my $clr_prefix = $param->{TYPE}{CLASS}{NAME};
							$clr_prefix =~ s/\.//g;
							$clr_prefix = pkgname_to_clr ($param->{TYPE}{PKG}) . ".$clr_prefix";

							print $fd "\t\t\t\t\t<attr path=\"$path\"\n";
							print $fd "\t\t\t\t\t\tname=\"enumType\">$clr_prefix" .
								name_const_to_camel ($param->{TYPE}{NAME}) . "</attr>\n";
						}
					}

					if (ref $meth->{RETURN} eq 'ENUM') {
						# Fixme: this is just a supposition.
						my $clr_prefix = $meth->{RETURN}{CLASS}{NAME};
						$clr_prefix =~ s/\.//g;
						$clr_prefix = pkgname_to_clr ($meth->{RETURN}{PKG}) . ".$clr_prefix";

						print $fd "\t\t\t\t\t<attr path=\"$meth_path\"\n";
						print $fd "\t\t\t\t\t\tname=\"return\">$clr_prefix" . 
							name_const_to_camel ($meth->{RETURN}{NAME}) . "</attr>\n";
					}
				}
			}
		}
	}

	print $fd "\n</metadata>\n";
}

=head1 CONFIGURATION

=head2 ENUM_IGNORE_VALUES_FOR_ENUM_NAME

A hash whose keys indicate enum values that will not be used to infer enumeration names.

=cut

our %ENUM_IGNORE_VALUES_FOR_ENUM_NAME = ();

=head2 ONLY_PARSE_INT_CONSTANTS

Boolean, if true, ignore any constants whose type is not int (default 1, do ignore).

=cut

our $ONLY_PARSE_INT_CONSTANTS = 1;

=head2 PARAM_DESC_CORRECTIONS

Hash ref of regular expressions (use qr/myregexp/) vs. replacements to correct the descriptive text of 
parameters and return values.

Sample:

    $Xam::Binding::Trans::PARAM_DESC_CORRECTIONS = {
    	qr/REMOVER/ => 'ERASER'
    };

=cut

our $PARAM_DESC_CORRECTIONS;

=head2 PARAM_PREFIX_CLEANUP_RE

Regular expression (use qr/myregexp/) to clean up names for parameters that are candidates for enums.

=cut

our $PARAM_PREFIX_CLEANUP_RE;

=head2 METHOD_PREFIX_CLEANUP_RE

Regular expression (use qr/myregexp/) to clean up get/set method names used for candidates for enums.

=cut

our $METHOD_PREFIX_CLEANUP_RE;

=head2 PARAM_NAME_ENUM_EXCLUDE_RE

Regular expression (use qr/myregexp/) specifying those parameter names that won't be checked to see if they are enums.

=cut

our $PARAM_NAME_ENUM_EXCLUDE_RE;

=head2 PACKAGE_CLR_TRANSFORM_RE

Regular expression (use qr/myregexp/) that will be applied to be replaced by PACKAGE_CLR_TRANSFROM_SUBST
to generate the CLR version of packages.

=cut

our $PACKAGE_CLR_TRANSFORM_RE = qr/^com\./;

=head2 PACKAGE_CLR_TRANSFORM_SUBST

A string of what is to be put in place of what is matched by PACKAGE_CLR_TRANSFORM_RE to generate the CLR version
of package names.

=cut

our $PACKAGE_CLR_TRANSFORM_SUBST = '';

=head1 SEE ALSO

"Binding a Java Library (.jar)" from Xamarin, Inc.

L<http://docs.xamarin.com/guides/android/advanced_topics/java_integration_overview/binding_a_java_library_(.jar%29/>

=head1 AUTHOR

Arturo Espinosa, C<< <arturo.espinosa at xamarin.com> >>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Xam::Binding::Trans

Github project location for source code and bug reports:

L<https://github.com/pupitetris/jdh2trans>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013 Xamarin, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

L<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


=cut

our $EOL = "\r\n";

# Utility routines.

sub name_from_fullname {
	my $fullname = shift;

	$fullname =~ s/.*\.([^\.]+)/$1/;
	return $fullname;
}

sub class_from_fullname {
	my $fullname = shift;

	$fullname =~ s/[a-z0-9.]*\.((?:[A-Z]+[a-z0-9][^.]+\.?)+).*/$1/;
	$fullname =~ s/\.$//;
	return $fullname;
}

sub pkg_from_fullname {
	my $fullname = shift;

	$fullname =~ s/\.[A-Z].*//;
	return $fullname;
}

sub get_method_fullname {
	my $meth = shift;

	return $meth->{CLASS}{FULLNAME} . '.' . $meth->{NAME} .
		'(' . join (',', 
					map { ref $_->{TYPE} eq 'ENUM'? 'enum:' . $_->{TYPE}{FULLNAME}: $_->{TYPE} } @{$meth->{PARAMS}})
		. ')' . ($meth->{RETURN}? 
				 '=' . (ref $meth->{RETURN} eq 'ENUM'? 'enum:' . $meth->{RETURN}{FULLNAME}: $meth->{RETURN}):
				 '');
}

sub name_camel_to_const {
	my $name = shift;
	if ($PARAM_PREFIX_CLEANUP_RE) {
		$name =~ s/$PARAM_PREFIX_CLEANUP_RE//g;
	}
	$name =~ s/([A-Z][^A-Z])/_$1/g;
	$name =~ s/^_//;
	return uc ($name);
}

sub name_const_to_camel {
	my $name = shift;
	if (!$name) {
		$DB::single = 1;
	}
	return join ('', map {ucfirst (lc ($_))} split ('_', $name));
}

sub pkgname_to_clr {
	my $pkgname = shift;

	if ($PACKAGE_CLR_TRANSFORM_RE) {
		$pkgname =~ s/$PACKAGE_CLR_TRANSFORM_RE/$PACKAGE_CLR_TRANSFORM_SUBST/g;
	}

	my @words = split ('\.', $pkgname);
	
	return join ('.', map {ucfirst $_} @words);
}

sub pkgname_to_jni {
	my $pkgname = shift;

	$pkgname =~ tr#.#/#;
	return $pkgname;
}

sub type_qualify {
	my $type = shift;
	my $class = shift;
	my $anchors = shift;

	while ($type =~ /(^[A-Z]|<[A-Z])/) {
		my $anchor = shift @$anchors;
		my $title;
		if ($anchor) {
			$title = $anchor->attr('title');
			$title =~ s/(class or interface|class|interface) in //;
		} else {
			$title = $class->{PKG};
		}
		$type =~ s/((^|<)([A-Z][a-zA-Z0-9_]))/$2$title.$3/;
	}
	return $type;
}

# Find in the consts collection, the longest prefix in their names, common to all.
sub find_max_common_prefix {
	my $consts = shift; # A hash of consts

	# Find the number of words that compose the max common prefix
	# among the received values.
	my $name_min_idx = 999;
	my $prev_words;
	foreach my $const (values %$consts) {
		next if exists $ENUM_IGNORE_VALUES_FOR_ENUM_NAME{$const->{NAME}};

		my @words = split ('_', $const->{NAME});
		pop @words; # Remove last word: prefix can't be the whole name of a given const.

		# On first iteration we just get something to compare with and skip.
		if (ref $prev_words ne 'ARRAY') {
			$prev_words = \@words;
			next;
		}

		my $i;
		for ($i = 0; $i < scalar @words && $i < scalar @$prev_words && $i < $name_min_idx; $i++) {
			last if $words[$i] ne $prev_words->[$i];
		}
		$name_min_idx = $i if $i < $name_min_idx;
		last if $i < 1; # can't be smaller, so we quit at this point.
	}
	$name_min_idx = 0 if $name_min_idx == 999;

	if (scalar (keys %$consts) == 1) {
		# A ridiculous enumeration with only one value. Just take first word.
		# (solves com.samsung.android.sdk.gesture.Sgesture.TYPE_HAND_PRIMITIVE)
		$name_min_idx = 1;
	}
	
	# These consts are not similar at all.
	return '' if $name_min_idx < 1;

	# We reuse prev_words, since any of the names should contain the max common prefix.
	return join ('_', (@$prev_words)[0 .. $name_min_idx - 1]);
}

sub type_may_be_enum {
	my $type = shift;
	return $type eq 'int' || $type =~ /<[^>]*java.lang.Integer[^>]*>/;
}

sub type_replace_integer_with_enum {
	my $type = shift;
	my $enum = shift;

	return $enum if $type eq 'int';

	my $str = 'enum:' . $enum->{FULLNAME};

	$type =~ s/(?:int|java.lang.Integer)/$str/;
	return $type;
}

# Private methods

# The good stuff.

# Change the type of a given method while keeping consistency.
sub _method_set_param_type {
	my $self = shift;
	my $meth = shift;
	my $param_no = shift;
	my $type = shift;

	# you can specify a fullname.
	if (ref $meth eq '') {
		my $m = $self->{METHODS}{$meth};
		carp "Method $meth not found" if !$m;
		$meth = $m;
	}

	$meth->{PARAMS}->[$param_no]->{TYPE} = $type;

	my $fullname = $meth->{FULLNAME};
	$meth->{FULLNAME} = get_method_fullname ($meth);
	delete $self->{METHODS}{$fullname};
	$self->{METHODS}{$meth->{FULLNAME}} = $meth;

	my $class = $meth->{CLASS};
	if ($meth->{TYPE} eq 'constructor') {
		delete $class->{CTORS}{$fullname};
		$class->{CTORS}{$meth->{FULLNAME}} = $meth;
	} else {
		delete $class->{METHODS}{$fullname};
		$class->{METHODS}{$meth->{FULLNAME}} = $meth;
	}
}

# Merge the enum key/value pairs into the existing enums.
sub _enums_merge {
	my $self = shift;
	my $enum = shift;
	my $orig = shift;

	my $fullname = $enum->{FULLNAME};

	if (!$orig) {
		$orig = $self->{ENUMS}{$fullname};
		if (!$orig) {
			$enum->{CLASS}{ENUMS}{$fullname} = $enum;
			$self->{ENUMS}{$fullname} = $enum;
			return $enum;
		}
	} else {
		if ($enum->{NAME} ne '') {
			my $offset = length ($orig->{NAME}) - length ($enum->{NAME});
			if ($offset > 0) {
				if ($enum->{NAME} ne substr ($orig->{NAME}, 0, -$offset)) {
					$DB::single = 1;
					carp "Incompatible enums $orig->{FULLNAME} and $enum->{FULLNAME}";
				}
				
				# Name changed for the better: smaller prefix.
				my $add = substr ($orig->{NAME}, -$offset);
				$add =~ s/^_//;
				
				# Fixme: we should keep method fullnames consistent too.
				$fullname = $enum->{FULLNAME};
				delete $self->{ENUMS}{$orig->{FULLNAME}};
				$self->{ENUMS}{$fullname} = $orig;
				delete $orig->{CLASS}{ENUMS}{$orig->{FULLNAME}};
				$orig->{CLASS}{ENUMS}{$fullname} = $orig;

				$orig->{FULLNAME} = $fullname;
				$orig->{NAME} = $enum->{NAME};

				foreach my $pair (values %{$orig->{PAIRS}}) {
					$pair->{NAME} = $add . '_' . $pair->{NAME};
				}

			} elsif ($offset < 0) {
				if ($orig->{NAME} ne substr ($enum->{NAME}, 0, $offset)) {
					$DB::single = 1;
					carp "Incompatible enums $orig->{FULLNAME} and $enum->{FULLNAME}";
				}

				# enum prefix is bigger, adapt names to avoid incompatibility warnings.
				my $add = substr ($enum->{NAME}, $offset);
				$add =~ s/^_//;
				
				foreach my $pair (values %{$enum->{PAIRS}}) {
					$pair->{NAME} = $add . '_' . $pair->{NAME};
				}

			}
		}
	}

	my $orig_pairs = $orig->{PAIRS};
	my $enum_pairs = $enum->{PAIRS};

	foreach my $k (keys %$orig_pairs) {
		if (exists $enum_pairs->{$k} && 
			$orig_pairs->{$k}{NAME} ne $enum_pairs->{$k}{NAME}) {
			$DB::single = 1;
			carp "Incompatible enums $fullname for value $k";
		}
	}

	foreach my $k (keys %$enum_pairs) {
		if (exists $orig_pairs->{$k}) {
			if ($orig_pairs->{$k}{NAME} ne $enum_pairs->{$k}{NAME}) {
				$DB::single = 1;
				carp "Incompatible enums $fullname for value $k";
			}
		} else {
			$orig_pairs->{$k} = $enum_pairs->{$k};
			$orig_pairs->{$k}{CONST}{USED} = $orig;
		}
	}

	return $orig;
}

sub _collect_values_by_prefix {
	my $self = shift;
	my $prefix = shift;
	my $values = shift // {};

	OUTER: foreach my $key (keys %{$self->{CONSTS}}) {
		my $const = $self->{CONSTS}{$key};
		if ($key =~ /^$prefix/ && !$const->{USED} && !exists $values->{$const->{NAME}}) {
			foreach my $orig_const (values %$values) {
				next OUTER if $orig_const->{VALUE} == $const->{VALUE};
			}
			$values->{$const->{NAME}} = $const;
		}
	}

	return $values;
}

# Easy enums that use the same class
sub _create_enum_straight {
	my $self = shift;
	my $consts = shift;
	my $param_name = shift;

	my $a_const = (values %$consts)[0];

	my $orig;
	$orig = $a_const->{USED} if $a_const->{USED};

	my $offset;
	my $name = find_max_common_prefix ($consts);

	if ($name ne '') {
		# Now that we have a maningful prefix, try to find qualifying consts that may not
		# have been mentioned in the documentation.
		my $size = scalar keys %$consts;
		$self->_collect_values_by_prefix ($a_const->{PKG} . '.' . $a_const->{CLASS} . '.' . $name, $consts);
		# If we actually found more consts, recalculate prefix; it may have changed.
		$name = find_max_common_prefix ($consts) if $size != scalar keys %$consts;

		$offset = length ($name) + 1;
	} else {
		if (! defined $param_name) {
			$DB::single = 1;
			carp "No max common prefix found for enum name";
			return;
		}
		$name = name_camel_to_const ($param_name);
		$offset = 0;
	}
	
	my $classname = $a_const->{PKG} . '.' . $a_const->{CLASS};

	# Creating new enum
	my $enum = bless { 
		CLASS => $self->{CLASSES}{$classname},
		PKG => $a_const->{PKG},
		NAME => $name,
		FULLNAME => "$classname.$name"
	}, 'ENUM';

	# Build value-key pairs.
	my %pairs = ();
	foreach my $const (values %$consts) {
		my $valkey;
	    if (exists $ENUM_IGNORE_VALUES_FOR_ENUM_NAME{$const->{NAME}}) {
			$valkey = $const->{NAME};
		} else {
			if ($offset > 0 && substr ($const->{NAME}, 0, $offset) eq $name . '_') {
				$valkey = substr ($const->{NAME}, $offset);
			} else {
				$valkey = $const->{NAME};
			}
		}
		
		# Creating new pair
		$pairs{$const->{VALUE}} = {
			CONST => $const,
			NAME => $valkey,
			VAL => $const->{VALUE}
		};

		if ($const->{USED} && $orig && $const->{USED} != $orig) {
			$DB::single = 1;
			carp "Reusing const $const->{FULLNAME}, orig $orig->{FULLNAME}, new $enum->{FULLNAME}";
		}
		$const->{USED} = ($orig)? $orig: $enum;
	}

	$enum->{PAIRS} = \%pairs;

	return $self->_enums_merge ($enum, $orig);
}

sub _type_enum_test {
	my $self = shift;
	my $type = shift;
	my $dd = shift; # Element containing the description
	my $class = shift;
	my $method_name = shift;

	my $txt = $dd->format;
	if ($PARAM_DESC_CORRECTIONS) {
		foreach my $re (keys %$PARAM_DESC_CORRECTIONS) {
			my $subst = $PARAM_DESC_CORRECTIONS->{$re};
			$txt =~ s/$re/$subst/g;
		}
	}
	
	my @toks = split (/\s*[\s,*]\s*/, $txt);

	my $param_name;
	if (scalar @toks > 2 && $toks[2] eq '-') {
		# Type belongs to an parameter.
		$param_name = $toks[1];
		splice @toks, 0, 3;

		# If method is a setter, override param_name.
		if ($method_name && $method_name =~ /^(?:set|get)/) {
			$param_name = $method_name;
			$param_name =~ s/^(?:set|get)([A-Z]+[^A-Z]+)/$1/;
			if ($METHOD_PREFIX_CLEANUP_RE) {
				$param_name =~ s/$METHOD_PREFIX_CLEANUP_RE//;
			}
		}
	} elsif ($method_name) {
		# Type belongs to a return value and a method name was provided.
		if ($method_name =~ /^get/) {
			# Method is a getter.
			$param_name = $method_name;
			$param_name =~ s/^get([A-Z]+[^A-Z]+)/$1/;
			if ($METHOD_PREFIX_CLEANUP_RE) {
				$param_name =~ s/$METHOD_PREFIX_CLEANUP_RE//;
			}
		}
	}

	my %values = ();
	my %prefix_hist = (); # package-class concats.
	my $found = 0;
	foreach my $tok (@toks) {
		# If it looks like a constant and we aren't repeating...
		$tok =~ s/\.$//;
		if ($tok =~ /^[a-zA-Z0-9.]*[A-Z0-9_]+$/ && ! exists $values{$tok}) {
			foreach my $const_fullname (keys %{$self->{CONSTS}}) {
				# Add const to results if it ends just like our token.
				if ($const_fullname =~ /[_.]$tok$/) {
					my $const = $self->{CONSTS}{$const_fullname};
					next if $const->{TYPE} ne 'int';

					my $classname = $const->{PKG} . '.' . $const->{CLASS};
					$prefix_hist{$classname} = {} if !exists $prefix_hist{$classname};
					$prefix_hist{$classname}{$tok} = $const;

					if (exists $values{$tok}) {
						if (ref $values{$tok} ne 'ARRAY') {
							$values{$tok} = [$values{$tok}];
						}
						push @{$values{$tok}}, $const;
					} else {
						$values{$tok} = $const;
					}
					$found ++;
				}
			}
		}
	}

	if ($found > 0) {
		# We actually found candidates.
		
		# Give priority to current class.
		my $hist_for_class = $prefix_hist{$class->{FULLNAME}};
		if ($hist_for_class &&
			scalar (keys %$hist_for_class) == scalar (keys %values)) {
			# We got all of our bases covered with the consts we found in the current class.
			return type_replace_integer_with_enum ($type, $self->_create_enum_straight ($hist_for_class, $param_name));
		}

		if (scalar (keys %prefix_hist) == 1) {
			# Only one prefix found, great!
			if ($found == scalar (keys %values)) {
				# No duplicate candidates, yay.
				return type_replace_integer_with_enum ($type, $self->_create_enum_straight (\%values, $param_name));
			} else {
				$DB::single = 1;
				carp "Multiple candidates found";
			}
		}

		foreach my $prefix (values %prefix_hist) {
			if (scalar (keys %$prefix) == scalar (keys %values)) {
				# All bases covered with the consts found in this prefix.
				return type_replace_integer_with_enum ($type, $self->_create_enum_straight ($prefix, $param_name));
			}
		}

		$DB::single = 1;
		carp "More than one prefix";
	}

	# Uff, try to use the param_name to find relevant constants.
	if (defined $param_name) {
		return $self->_type_search_enum_by_name ($type, $param_name,
												 $class->{PKG}, $class->{FIELDS}, 0);
	}

	return $type;
}

sub _type_search_enum_by_name {
	my $self = shift;
	my $type = shift;
	my $name = shift;
	my $pkg = shift;
	my $fields = shift;
	my $search_sub_packages = shift;

	return $type if !type_may_be_enum ($type);

	# Take up to the second-to-last word.
	my $str = name_camel_to_const ($name);
	$str =~ s/_[^_]+$/_/;

	my %consts = ();

	foreach my $ff (values %$fields) {
		my $const = $ff->{IS_ENUM_VALUE};
		next if !$const;
		next if index ($const->{NAME}, $str) < 0;
		$consts{$const->{NAME}} = $const;
	}

	if (scalar keys %consts == 0 || find_max_common_prefix (\%consts) eq '') {
		# Consts not found in this class fields, try in this package.
		%consts = ();
		foreach my $const (values %{$self->{PACKAGES}{$pkg}{CONSTS}}) {
			if (index ($const->{NAME}, $str) > -1) {
				$consts{$const->{NAME}} = $const;
			}
		}
	}

	# If consts not found in this package either, try in sub-packages.
	if ($search_sub_packages && (scalar keys %consts == 0 || find_max_common_prefix (\%consts) eq '')) {
		foreach my $pname (keys %{$self->{PACKAGES}}) {
			if ($pname ne $pkg && index ($pname, $pkg) > -1) {
				# It's a sub-package.
				my $pp = $self->{PACKAGES}{$pname};
				%consts = ();
				foreach my $cname (keys %{$pp->{CONSTS}}) {
					if (index ($cname, $str) > -1) {
						$consts{$cname} = $pp->{CONSTS}{$cname};
					}
				}
				# Get out if we made it.
				last if scalar keys %consts > 0 && find_max_common_prefix (\%consts) ne '';
			}
		}
	}

	# If all failed, give up.
	if (scalar keys %consts == 0) {
		return $type;
	}

	my $prefix = find_max_common_prefix (\%consts);
	if ($prefix eq '') {
		return $type;
	}

	# OK, we got something meaningful (hopefully), go process the enum.
	return type_replace_integer_with_enum ($type, $self->_create_enum_straight (\%consts));
}

sub _type_qualify {
	my $self = shift;
	my $type = shift;
	my $class = shift;
	my $anchors = shift;
	my $ul = shift; # HTML element class blockList* with full definition.
	my $param_no = shift;
	my $method_name = shift;
	my $param_name = shift;

	$type = &type_qualify ($type, $class, $anchors);
	return $type if $PARAM_NAME_ENUM_EXCLUDE_RE && $param_name && $param_name =~ /$PARAM_NAME_ENUM_EXCLUDE_RE/;
	return $type if ! type_may_be_enum ($type);

	# OK, the type uses an integer, try to see if such integer is an enum.
	# If something fails, assume the type is an ordinary type.
	
	# Get the element with the definitions.
	my $dl = $ul->look_down (_tag => 'dl');
	if (defined $dl) {

		my $subtitle;
		if ($param_no >= 0) {
			$subtitle = 'Parameters:'; # A method parameter
		} elsif ($param_no == -1) {
			$subtitle = 'Returns:'; # A method return value
		} else {
			$subtitle = 'See Also:'; # A field
		}

		# Find the definition for the parameter/return value we are analyzing.
		my $found_dt = 0;
		my $thisparam = 0;
		foreach my $d ($dl->look_down (_tag => qr/d[td]/)) {
			if ($d->tag eq 'dt') {
				# The right dt has already been found and this is another dt, we failed.
				last if $found_dt;

				$found_dt = 1 if $d->as_text () eq $subtitle;
				next;
			}
			next if !$found_dt;
			if ($param_no < 0 || $thisparam == $param_no) {
				# OK, this dd has got the stuff we are looking for.
				return $self->_type_enum_test ($type, $d, $class, $method_name);
			}
			$thisparam ++;
		}

	}
	
	# We couldn't find the definition. OK, try by name...
	if ($param_name) {
		return $self->_type_search_enum_by_name ($type, $param_name,
												 $class->{PKG}, $class->{FIELDS}, 0);
	}

	# Everything failed. Assume it's an ordinary type then.
	return $type;
}

sub _parse_proto {
	my $self = shift;
	my $ul = shift;
	my $class = shift;
	
	my $pre = $ul->look_down (_tag => 'pre');

	my $str = $pre->as_text ();
	$str =~ s/[\xA0 \r\n]+/ /g; # collapse white space.

	# get visibility, return value and parameters
	$str =~ /^(public|protected|) ?(static|) ?(?:([^ ]*) )?([^(]+)\(([^)]*)\)/;

	# The matched string. Not using $& because it causes regexp engine to become slow.
	my $proto_str = substr ($str, $-[0], $+[0] - $-[0]);

	my ($visibility, $static, $ret, $name, $params) = ($1, $2, $3, $4, $5);

	my $type;
	if ($name eq $class->{NAME}) {
		$type = 'constructor';
		$name = 'constructor';
	} else {
		$type = 'method';
	}

	my @anchors = $pre->look_down (_tag => 'a');
	$ret = $self->_type_qualify ($ret, $class, \@anchors, $ul, -1, $name) if defined $ret;

	my @params = ();
	my $param_no = 0;
	my $param_type = '';
	foreach my $pair (split (',', $params)) {
		my ($t, $param_name) = split (' ', $pair);
		$param_type .= $t;

		# Types with generics may contain commas, go get the next portion of the type.
		if (!$param_name) {
			$param_type .= ',';
			next;
		}

		$new_type = $self->_type_qualify ($param_type, $class, \@anchors, $ul, $param_no, $name, $param_name);

		# Creating new param
		my $param = {
			TYPE => $new_type, 
			NAME => $param_name,
			POS => $param_no + 1
		};

		if ($new_type ne $param_type) {
			$param->{TYPE_ORIG} = $param_type;
		}

		push @params, $param;
		$param_no++;

		$param_type = '';
	}

	# Creating new method
	my $meth = {
		CLASS => $class,
		TYPE => $type,
		VISIBILITY => $visibility,
		STATIC => $static,
		RETURN => $ret,
		NAME => $name,
		PROTO => $proto_str,
		PARAMS => \@params
	};

	$meth->{FULLNAME} = get_method_fullname ($meth);

	return $meth;
}

sub _parse_packages {
	my $self = shift;
	my %packages = ();
	open my $fd, "$self->{BASEDIR}/package-list" || croak "Package list file `$self->{BASEDIR}/package-list` not found.";
	while (<$fd>) {
		s/$EOL//;

		# Creating new package
		$packages{$_} = { 
			NAME => $_,
			CONSTS => {},
			CLASSES => {}
		};
	}
	close $fd;
	return \%packages;
}

sub _parse_constants {
	my $self = shift;
	my %consts = ();

	my $tree = HTML::TreeBuilder->new_from_file ("$self->{BASEDIR}/constant-values.html");
	$tree->elementify ();

	# search inside all li items that have constants for a class/interface inside.
	foreach my $li ($tree->look_down (_tag => 'li', class => qr/blockList.*/)) {
		# each tr contains a constant.
		foreach my $tr ($li->look_down (_tag => 'tr')) {
			next if !defined $tr->attr('class') || $tr->attr ('class') eq '';

			my @codes = $tr->look_down (_tag => 'code');
			my @content = $codes[0]->content_list;

			my $value = ${$codes[2]->content}[0];

			my $type = $content[0];
			$type =~ s/public.static.final.//;

			# We assume here that constants won't be complex types (usually just int or java.lang.String).
			if ($type eq '') {
				my $type_a = $content[1];
				$type = $type_a->attr ('title');
				$type =~ s/(class or interface|class|interface) in //;
				$type .= '.' . ${$type_a->content}[0];

				# type is probably a string, so try to remove quotes from value.
				$value =~ s/(^"|"$)//g;
			}

			# To find enums, we only care about int constants.
			next if $ONLY_PARSE_INT_CONSTANTS && $type ne 'int';

			my $a = $tr->look_down (_tag => 'a');
			my $fullname = $a->attr ('name');
			my $pkg = pkg_from_fullname ($fullname);

			# Creating new const
			my $const = {
				FULLNAME => $fullname,
				NAME => name_from_fullname ($fullname),
				CLASS => class_from_fullname ($fullname),
				PKG => $pkg,
				TYPE => $type,
				USED => 0,
				VALUE => $value
			};
			$consts{$fullname} = $const;
			$self->{PACKAGES}{$pkg}{CONSTS}{$fullname} = $const;
		}
	}
	return \%consts;
}

sub _create_int_const {
	my $self = shift;
	my $class = shift;
	my $name = shift;
	my $value = shift;

	my $fullname = $class->{FULLNAME} . '.' . $name;
	
	# Creating new const
	my $const = {
		FULLNAME => $fullname,
		NAME => $name,
		CLASS => $class->{NAME},
		PKG => $class->{PKG},
		TYPE => 'int',
		USED => 0,
		VALUE => $value,
		VALUE_IS_COOKED => 1 # The value was created by us.
	};

	$self->{CONSTS}{$fullname} = $const;
	$self->{PACKAGES}{$class->{PKG}}{CONSTS}{$fullname} = $const;

	return $const;
}

# Parse classes (and interfaces) for the given package.
sub _parse_classes_from_pkg {
	my $self = shift;
	my $pkg = shift;
	my $classes = shift // {};

	my $pkg_path = $pkg;
	$pkg_path =~ tr#.#/#;

	my $fname = "$self->{BASEDIR}/$pkg_path/package-frame.html";

	my $tree = HTML::TreeBuilder->new_from_file ($fname);
	$tree->elementify ();
	
	my $index_container = $tree->look_down (class => 'indexContainer');
	foreach my $a ($index_container->look_down (_tag => 'a')) {
		my $type = $a->attr ('title');
		$type =~ s/ .*//;

		# The name is inside the a. Interface names are enclosed within italics.
		my $name = ${$a->content}[0];
		$name = ${$name->content}[0] if $type eq 'interface';
		
		my $fullname = $pkg . '.' . $name;

		# Creating new class
		my $class = {
			FULLNAME => $fullname,
			PKG => $pkg,
			NAME => $name,
			TYPE => $type,
			METHODS => {},
			CTORS => {},
			ENUMS => {}
		};

		$classes->{$fullname} = $class;
		$self->{PACKAGES}{$pkg}{CLASSES}{$fullname} = $class;
	}

	return $classes;
}

# Parse classes for the given packages.
sub _parse_classes {
	my $self = shift;
	my $packages = shift;
	my $classes = shift // {};

	foreach my $pkg (sort keys %$packages) {
		$self->_parse_classes_from_pkg ($pkg, $classes);
	}

	return $classes;
}

sub _parse_fields_for_class {
	my $self = shift;
	my $class = shift;
	my $tree = shift;
	my $fields = shift // {};

	# Check fields declared to be used by the class so we can account for them below.
	my $field_a = $tree->look_down (_tag => 'a', name => 'field_detail');
	if ($field_a) {
		my $new_const_num = 0;
		foreach my $h4 ($field_a->parent->look_down (_tag => 'h4')) {
			my $li = $h4->parent;
			my $name = ${$h4->content}[0];
			my $pre = $li->look_down (_tag => 'pre');

			my $str = $pre->as_text ();
			$str =~ s/[\xA0 \r\n]+/ /g; # collapse white space.

			# get visibility, return value and parameters
			$str =~ /^(public|protected|) ?(static|) ?(final|) ?(?:([^ ]*) )?/;

			my ($visibility, $static, $final, $type) = ($1, $2, $3, $4);

			my $is_enum_value = ($static && $type eq 'int' && $name =~ /^[A-Z0-9_]+$/)? 1: '';

			my $fullname = $class->{FULLNAME} . '.' . $name;

			if ($is_enum_value) {
				# Find which const this represents.
				my $a = $li->look_down (_tag => 'a', href => qr/constant-values/);
				my $const_fullname;
				if ($a) {
					$const_fullname = $a->attr ('href');
					$const_fullname =~ s/.*#//;
				} else {
					$const_fullname = $fullname;
				}
				if (exists $self->{CONSTS}{$const_fullname}) {
					$is_enum_value = $self->{CONSTS}{$const_fullname};
				} else {
					$is_enum_value = $self->_create_int_const ($class, $name, $new_const_num);
					$new_const_num ++;
				}
			} else {
				$type = $self->_type_qualify ($type, $class, [], $li->parent, -2);
			}

			# Creating new field
			my $field = {
				FULLNAME => $fullname,
				CLASS => $class,
				TYPE => $type,
				VISIBILITY => $visibility,
				STATIC => $static,
				FINAL => $final,
				NAME => $name,
				IS_ENUM_VALUE => $is_enum_value,
			};

			$fields->{$fullname} = $field;
		}

		$class->{FIELDS} = $fields;

		# Now try (really hard) to infer which fields use enum.
		foreach my $field (values %$fields) {
			next if $field->{IS_ENUM_VALUE};

			$field->{TYPE} = $self->_type_search_enum_by_name ($field->{TYPE}, $field->{NAME}, 
															   $field->{CLASS}{PKG}, $fields, 1);
		}
	}

	return $fields;
}

# Parse methods for the given class.
sub _parse_methods_for_class {
	my $self = shift;
	my $class = shift;
	my $methods = shift // {};

	my %new_methods = ();
	my %ctors = ();
	my %hist = ();

	my $pkg_path = $class->{PKG};
	$pkg_path =~ tr#.#/#;

	my $fname = "$self->{BASEDIR}/$pkg_path/" . $class->{NAME} . ".html";

	my $tree = HTML::TreeBuilder->new_from_file ($fname);
	$tree->elementify ();

	# Do this here because new consts may be created and used here for enums.
	# Some consts are not declared in the global constants index page.
	$self->_parse_fields_for_class ($class, $tree);

	my $ctor_a = $tree->look_down (_tag => 'a', name => 'constructor_detail');
	if ($ctor_a) {
		foreach my $ul ($ctor_a->parent->look_down (_tag => 'ul', class => qr/blockList.*/)) {
			my $proto = $self->_parse_proto ($ul, $class);
			$ctors{$proto->{FULLNAME}} = $proto;
			$methods->{$proto->{FULLNAME}} = $proto;
			$hist{$proto->{NAME}} ++;
		}
	}

	my $method_a = $tree->look_down (_tag => 'a', name => 'method_detail');
	if ($method_a) {
		foreach my $ul ($method_a->parent->look_down (_tag => 'ul', class => qr/blockList.*/)) {
			my $proto = $self->_parse_proto ($ul, $class);
			$new_methods{$proto->{FULLNAME}} = $proto;
			$methods->{$proto->{FULLNAME}} = $proto;
			$hist{$proto->{NAME}} ++;
		}
	}

	$class->{CTORS} = \%ctors;
	$class->{METHODS} = \%new_methods;
	$class->{HIST} = \%hist;
	
	return $methods;
}

# Parse methods for the given classes.
sub _parse_methods {
	my $self = shift;
	my $classes = shift;
	my $methods = shift // {};

	foreach my $class (sort keys %$classes) {
		$self->_parse_methods_for_class ($classes->{$class}, $methods);
	}

	return $methods;
}

1; # End of Xam::Binding::Trans
