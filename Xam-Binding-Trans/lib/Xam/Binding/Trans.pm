package Xam::Binding::Trans;

use 5.10.0;
use strict;
use warnings FATAL => 'all';

use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use Carp qw(croak carp);

=head1 NAME

Xam::Binding::Trans - Generate Enum mappings for Xamarin Studio binding library projects.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

This module implements a class for enumeration mapping generation. An object 
from this class can read javaDoc HTML files and output XML mapping files
describing inferred enumerations and those methods which use these enumerations.

Code sample:

    use Xam::Binding::Trans;

    my $trans = Xam::Binding::Trans->new ();
    $trans->parse ('dir/to/javadoc-html');
    $trans->outEnumFields ('com.package.name', 'path/to/Transforms/EnumFields.xml');
    $trans->outEnumMethods ('com.package.name', 'path/to/Transforms/EnumMethods.xml');

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

=head2 $obj->outEnumFields (xml_file, packages ...)

Write an EnumFields.xml mapping file for the given packages at the xml_file location. All loaded packages
will be processed if no packages are specified.

=cut

sub outEnumFields {
	my $self = shift;
	my $xml_file = shift;
	my @packages = @_;
}

=head2 $obj->outEnumMethods (xml_file, packages ...)

Write an EnumMethods.xml mapping file for the given packages at the xml_file location. All loaded packages
will be processed if no packages are specified.

=cut

sub outEnumMethods {
	my $self = shift;
	my $xml_file = shift;
	my @packages = @_;
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

=head2 ARG_PREFIX_CLEANUP_RE

Regular expression (use qr/myregexp/) to clean up names for arguments that are candidates for enums.

=cut

our $ARG_PREFIX_CLEANUP_RE;

=head2 METHOD_PREFIX_CLEANUP_RE

Regular expression (use qr/myregexp/) to clean up get/set method names used for candidates for enums.

=cut

our $METHOD_PREFIX_CLEANUP_RE;

=head1 SEE ALSO

    "Binding a Java Library (.jar)" from Xamarin, Inc.

	L<http://docs.xamarin.com/guides/android/advanced_topics/java_integration_overview/binding_a_java_library_(.jar)/>

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
					map { ref $_->{TYPE} eq 'ENUM'? 'enum ' . $_->{TYPE}{FULLNAME}: $_->{TYPE} } @{$meth->{ARGS}})
		. ')';
}

sub name_camel_to_const {
	my $name = shift;
	if ($ARG_PREFIX_CLEANUP_RE) {
		$name =~ s/$ARG_PREFIX_CLEANUP_RE//g;
	}
	$name =~ s/([A-Z][^A-Z])/_$1/g;
	$name =~ s/^_//;
	return uc ($name);
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
		last if $i <= 1; # can't be smaller, so we quit at this point.
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
sub _method_set_arg_type {
	my $self = shift;
	my $meth = shift;
	my $argno = shift;
	my $type = shift;

	# you can specify a fullname.
	if (ref $meth eq '') {
		my $m = $self->{METHODS}{$meth};
		carp "Method $meth not found" if !$m;
		$meth = $m;
	}

	$meth->{ARGS}->[$argno]->{TYPE} = $type;

	my $fullname = $meth->{FULLNAME};
	$meth->{FULLNAME} = get_method_fullname ($meth);
	delete $self->{METHODS}{$fullname};
	$self->{METHODS}{$meth->{FULLNAME}} = $meth;
}

# Merge the enum key/value pairs into the existing enums.
sub _enums_merge {
	my $self = shift;
	my $enum = shift;

	my $fullname = $enum->{FULLNAME};

	my $orig = $self->{ENUMS}{$fullname};
	return $self->{ENUMS}{$fullname} = $enum if !$orig;

	my $orig_pairs = $orig->{PAIRS};
	my $enum_pairs = $enum->{PAIRS};

	foreach my $k (keys %$orig_pairs) {
		if (exists $enum_pairs->{$k} && 
			$orig_pairs->{$k} ne $enum_pairs->{$k}) {
			$DB::single = 1;
			carp "Incompatible enums $fullname";
		}
	}

	foreach my $k (keys %$enum_pairs) {
		if (exists $orig_pairs->{$k}) {
			if ($orig_pairs->{$k} ne $enum_pairs->{$k}) {
				$DB::single = 1;
				carp "Incompatible enums $fullname";
			}
		} else {
			$orig_pairs->{$k} = $enum_pairs->{$k};
		}
	}

	return $orig;
}

sub _collect_values_by_prefix {
	my $self = shift;
	my $prefix = shift;
	my $values = shift // {};

	foreach my $key (keys %{$self->{CONSTS}}) {
		my $const = $self->{CONSTS}{$key};
		if ($key =~ /^$prefix/ && !exists $values->{$const->{NAME}}) {
			$values->{$const->{NAME}} = $const;
		}
	}

	return $values;
}

# Easy enums that use the same class
sub _create_enum_straight {
	my $self = shift;
	my $consts = shift;
	my $argname = shift;

	my $a_const = (values %$consts)[0];

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
		if (! defined $argname) {
			$DB::single = 1;
			carp "No max common prefix found for enum name";
			return;
		}
		$name = name_camel_to_const ($argname);
		$offset = 0;
	}
	
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
		
		$pairs{$const->{VALUE}} = $valkey;
		$const->{USED} = 1;
	}

	my $enum = bless {
		CLASS => $a_const->{CLASS},
		PKG => $a_const->{PKG},
		NAME => $name,
		FULLNAME => $a_const->{PKG} . '.' . $a_const->{CLASS} . '.' . $name,
		PAIRS => \%pairs
	 }, 'ENUM';

	return $self->_enums_merge ($enum);
}

sub _type_enum_test {
	my $self = shift;
	my $type = shift;
	my $dd = shift; # Element containing the description
	my $class = shift;
	my $method_name = shift;

	my @toks = split (/\s*[\s,*]\s*/, $dd->format);

	my $argname;
	if (scalar @toks > 2 && $toks[2] eq '-') {
		# Type belongs to an argument.
		$argname = $toks[1];
		splice @toks, 0, 3;

		# If method is a setter, override argname.
		if ($method_name && $method_name =~ /^set/) {
			$argname = $method_name;
			$argname =~ s/^set([A-Z]+[^A-Z]+)/$1/;
			if ($METHOD_PREFIX_CLEANUP_RE) {
				$argname =~ s/$METHOD_PREFIX_CLEANUP_RE//;
			}
		}
	} elsif ($method_name) {
		# Type belongs to a return value and a method name was provided.
		if ($method_name =~ /^get/) {
			# Method is a getter.
			$argname = $method_name;
			$argname =~ s/^get([A-Z]+[^A-Z]+)/$1/;
			if ($METHOD_PREFIX_CLEANUP_RE) {
				$argname =~ s/$METHOD_PREFIX_CLEANUP_RE//;
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
			return type_replace_integer_with_enum ($type, $self->_create_enum_straight ($hist_for_class, $argname));
		}

		if (scalar (keys %prefix_hist) == 1) {
			# Only one prefix found, great!
			if ($found == scalar (keys %values)) {
				# No duplicate candidates, yay.
				return type_replace_integer_with_enum ($type, $self->_create_enum_straight (\%values, $argname));
			} else {
				$DB::single = 1;
				carp "Multiple candidates found";
			}
		}

		foreach my $prefix (values %prefix_hist) {
			if (scalar (keys %$prefix) == scalar (keys %values)) {
				# All bases covered with the consts found in this prefix.
				return type_replace_integer_with_enum ($type, $self->_create_enum_straight ($prefix, $argname));
			}
		}

		$DB::single = 1;
		carp "More than one prefix";
	}

	# Uff, try to use the argname as prefix to find relevant constants within the class.
	if (defined $argname) {
		my $prefix = $self->_collect_values_by_prefix ($class->{FULLNAME} . '.' . name_camel_to_const ($argname));
		if (scalar (keys %$prefix) > 0) {
			return type_replace_integer_with_enum ($type, $self->_create_enum_straight ($prefix));
		}
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

	# Take all but the last word, in const format.
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
	my $argno = shift;
	my $method_name = shift;
	my $arg_name = shift;

	$type = &type_qualify ($type, $class, $anchors);
	return $type if ! type_may_be_enum ($type);

	# OK, the type uses an integer, try to see if such integer is an enum.
	# If something fails, assume the type is an ordinary type.
	
	# Get the element with the definitions.
	my $dl = $ul->look_down (_tag => 'dl');
	if (!defined $dl) {
		# No description element! OK, try by name...
		if ($arg_name) {
			return $self->_type_search_enum_by_name ($type, $arg_name,
													 $class->{PKG}, $class->{FIELDS}, 0);
		}
		return $type;
	}

	my $subtitle;
	if ($argno >= 0) {
		$subtitle = 'Parameters:'; # A method argument
	} elsif ($argno == -1) {
		$subtitle = 'Returns:'; # A method return value
	} else {
		$subtitle = 'See Also:'; # A field
	}

	# Find the definition for the argument/return value we are analyzing.
	my $found_dt = 0;
	my $thisarg = 0;
	foreach my $d ($dl->look_down (_tag => qr/d[td]/)) {
		if ($d->tag eq 'dt') {
			# The right dt has already been found and this is another dt, we failed.
			last if $found_dt;

			$found_dt = 1 if $d->as_text () eq $subtitle;
			next;
		}
		next if !$found_dt;
		if ($argno < 0 || $thisarg == $argno) {
			# OK, this dd has got the stuff we are looking for.
			return $self->_type_enum_test ($type, $d, $class, $method_name);
		}
		$thisarg ++;
	}
	
	# We couldn't find the definition. Assume it's an ordinary type then.
	return $type;
}

sub _parse_proto {
	my $self = shift;
	my $ul = shift;
	my $class = shift;
	
	my $pre = $ul->look_down (_tag => 'pre');

	my $str = $pre->as_text ();
	$str =~ tr/\xA0 \r\n/ /d; # transform nbsp into space and remove all other white-space.

	# get visibility, return value and arguments
	$str =~ /^(public|protected|) ?(static|) ?(?:([^ ]*) )?([^(]+)\(([^)]*)\)/;

	my ($visibility, $static, $ret, $name, $args) = ($1, $2, $3, $4, $5);

	my $type = ($name eq $class->{NAME})? 'ctor': 'method';

	my @anchors = $pre->look_down (_tag => 'a');
	$ret = $self->_type_qualify ($ret, $class, \@anchors, $ul, -1, $name) if defined $ret;

	my @args = ();
	my $argno = 0;
	foreach my $pair (split (',', $args)) {
		my ($type, $arg_name) = split (' ', $pair);
		$type = $self->_type_qualify ($type, $class, \@anchors, $ul, $argno, $name, $arg_name);
		push @args, { TYPE => $type, NAME => $arg_name };
		$argno++;
	}

	my $meth = {
		CLASS => $class,
		TYPE => $type,
		VISIBILITY => $visibility,
		STATIC => $static,
		RETURN => $ret,
		NAME => $name,
		ARGS => \@args
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
		$packages{$_} = { 
			NAME => $_,
			CONSTS => {}
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
		$classes->{$fullname} = {
			FULLNAME => $fullname,
			PKG => $pkg,
			NAME => $name,
			TYPE => $type
		};
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

			# get visibility, return value and arguments
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
			$self->{FIELDS}{$fullname} = $field;
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
		}
	}

	my $method_a = $tree->look_down (_tag => 'a', name => 'method_detail');
	if ($method_a) {
		foreach my $ul ($method_a->parent->look_down (_tag => 'ul', class => qr/blockList.*/)) {
			my $proto = $self->_parse_proto ($ul, $class);
			$new_methods{$proto->{FULLNAME}} = $proto;
			$methods->{$proto->{FULLNAME}} = $proto;
		}
	}

	$class->{CTORS} = \%ctors;
	$class->{METHODS} = \%new_methods;
	
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
