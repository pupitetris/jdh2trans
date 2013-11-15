package Xam::Binding::Trans;

use 5.10.0;
use strict;
use warnings FATAL => 'all';

use HTML::TreeBuilder 5 -weak; # Ensure weak references in use
use Carp qw(croak);

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
		$self->{CLASSES} = $self->_parse_classes (\@packages);
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

	$fullname =~ s/.*\.([A-Z][a-z0-9][^.]+).*/$1/;
	return $fullname;
}

sub pkg_from_fullname {
	my $fullname = shift;

	$fullname =~ s/\.[A-Z].*//;
	return $fullname;
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
			$title = $class->{'PKG'};
		}
		$type =~ s/((^|<)([A-Z][a-zA-Z0-9_]))/$2$title.$3/;
	}
	return $type;
}

# Private methods

# The good stuff.
sub _type_enum_test {
	my $self = shift;
	my $dd = shift;
	my $class = shift;

	return 'int';
}

sub _type_qualify {
	my $self = shift;
	my $type = shift;
	my $class = shift;
	my $anchors = shift;
	my $ul = shift;
	my $argno = shift;

	$type = &type_qualify ($type, $class, $anchors);
	return $type if $type ne 'int';

	# OK, the type is an int, try to see if it is an enum.
	
	# Get the element with the definitions.
	my $dl = $ul->look_down (_tag => 'dl');
	return 'int' if !defined $dl;

	my $subtitle = ($argno < 0)?
		'Returns:': 
		'Parameters:';

	# Find the definition for the argument/return value we are analyzing.
	my $found_dt = 0;
	my $thisarg = 0;
	foreach my $d ($dl->look_down (_tag => qr/d[td]/)) {
		if ($d->tag eq 'dt') {
			# The right dt already found and this is another dt, we failed.
			last if $found_dt;

			$found_dt = 1 if $d->as_text () eq $subtitle;
			next;
		}
		next if !$found_dt;
		if ($argno < 0 || $thisarg == $argno) {
			return $self->_type_enum_test ($d, $class);
		}
		$thisarg ++;
	}
	
	# We couldn't find the definition. Assume it's an ordinary int then.
	return 'int';
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

	my $type = ($name eq $class->{'NAME'})? 'ctor': 'method';

	my @anchors = $pre->look_down (_tag => 'a');
	$ret = $self->_type_qualify ($ret, $class, \@anchors, $ul, -1) if defined $ret;

	my @args = ();
	my $argno = 0;
	foreach my $pair (split (',', $args)) {
		my ($type, $name) = split (' ', $pair);
		$type = $self->_type_qualify ($type, $class, \@anchors, $ul, $argno);
		push @args, { 'TYPE' => $type, 'NAME' => $name };
		$argno++;
	}

	my $fullname = 
		$class->{'FULLNAME'} . '.' . $name .
		'(' . join (',', map { $_->{'TYPE'} } @args) . ')';

	return {
		'CLASS' => $class,
		'TYPE' => $type,
		'FULLNAME' => $fullname,
		'VISIBILITY' => $visibility,
		'STATIC' => $static,
		'RETURN' => $ret,
		'NAME' => $name,
		'ARGS' => \@args
		};
}

sub _parse_packages {
	my $self = shift;
	my %packages = ();
	open my $fd, "$self->{BASEDIR}/package-list" || croak "Package list file `$self->{BASEDIR}/package-list` not found.";
	while (<$fd>) {
		s/$EOL//;
		$packages{$_} = { 'NAME' => $_ };
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

			my $a = $tr->look_down (_tag => 'a');
			my $fullname = $a->attr ('name');
			$consts{$fullname} = {
				'FULLNAME' => $fullname,
				'NAME' => &name_from_fullname ($fullname),
				'CLASS' => &class_from_fullname ($fullname),
				'PKG' => &pkg_from_fullname ($fullname),
				'TYPE' => $type,
				'VALUE' => $value
			};
		}
	}
	return \%consts;
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
			'FULLNAME' => $fullname,
			'PKG' => $pkg,
			'NAME' => $name,
			'TYPE' => $type
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

# Parse methods for the given class.
sub _parse_methods_for_class {
	my $self = shift;
	my $class = shift;
	my $methods = shift // {};

	my %new_methods = ();
	my %ctors = ();

	my $pkg_path = $class->{'PKG'};
	$pkg_path =~ tr#.#/#;

	my $fname = "$self->{BASEDIR}/$pkg_path/" . $class->{'NAME'} . ".html";

	my $tree = HTML::TreeBuilder->new_from_file ($fname);
	$tree->elementify ();

	# Check fields declared to be used by the class so we can account for them below.
	my %fields = ();
	my $field_a = $tree->look_down (_tag => 'a', name => 'field_detail');
	if ($field_a) {
		foreach my $h4 ($field_a->parent->look_down (_tag => 'h4')) {
			$fields {${$h4->content}[0]} = 1;
		}
	}

	my $ctor_a = $tree->look_down (_tag => 'a', name => 'constructor_detail');
	if ($ctor_a) {
		foreach my $ul ($ctor_a->parent->look_down (_tag => 'ul', class => qr/blockList.*/)) {
			my $proto = $self->_parse_proto ($ul, $class);
			$ctors{$proto->{'FULLNAME'}} = $proto;
			$methods->{$proto->{'FULLNAME'}} = $proto;
		}
	}

	my $method_a = $tree->look_down (_tag => 'a', name => 'method_detail');
	if ($method_a) {
		foreach my $ul ($method_a->parent->look_down (_tag => 'ul', class => qr/blockList.*/)) {
			my $proto = $self->_parse_proto ($ul, $class);
			$new_methods{$proto->{'FULLNAME'}} = $proto;
			$methods->{$proto->{'FULLNAME'}} = $proto;
		}
	}

	$class->{'CTORS'} = \%ctors;
	$class->{'METHODS'} = \%new_methods;
	
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
