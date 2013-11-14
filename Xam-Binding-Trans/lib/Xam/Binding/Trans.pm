package Xam::Binding::Trans;

use 5.10.0;
use strict;
use warnings FATAL => 'all';

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
	my $self = {};
	bless $self, $class;
	return $self;
}

sub DESTROY {
	my $self = shift;
	
}

=head2 $obj->parse (dir, packages ...)

Parse the structure of the given packages inside the dir path. Parse all packages found in the javaDoc
if no packages are specified.

=cut

sub parse {
	my $self = shift;
	my $dir = shift;
	my @packages = @_;
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

1; # End of Xam::Binding::Trans
