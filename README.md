# NAME

Xam::Binding::Trans - Generate Enum mappings for Xamarin Studio binding library projects.

# VERSION

Version 0.9

# SYNOPSIS

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

# METHODS

## Xam::Binding::Trans->new ()

Constructor. Creates a new mapper object.

## Xam::Binding::Trans::load (dump\_file)

Load the contents of the file located at dump\_file into a new object, restoring the saved parsing state.

## $obj->dump (dump\_file)

Dump the state of the object onto a file or file descriptor for later reuse, avoiding re-parsing.

## $obj->parse (dir, packages ...)

Parse the structure of the given packages inside the dir path. Parse all packages found in the javaDoc
if no packages are specified. Restricting packages to parse is a good idea since parsing methods
within classes is expensive.

## $obj->printEnumFieldMapping (xml\_file, packages ...)

Write an EnumFields.xml mapping file for the given packages at the xml\_file location. All loaded packages
will be processed if no packages are specified.

## $obj->printEnumMethodMapping (xml\_file, packages ...)

Write an EnumMethods.xml mapping file for the given packages at the xml\_file location. All loaded packages
will be processed if no packages are specified.

## $obj->printMetadata (xml\_file, api\_file, packages ...)

Write an Metadata.xml file for the given packages at the xml\_file location. All loaded packages
will be processed if no packages are specified. api\_file is the api.xml file produced by Xamarin
Studio after compiling the binding package; use the empty string if none is available.

# CONFIGURATION

## ENUM\_IGNORE\_VALUES\_FOR\_ENUM\_NAME

A hash whose keys indicate enum values that will not be used to infer enumeration names.

## ONLY\_PARSE\_INT\_CONSTANTS

Boolean, if true, ignore any constants whose type is not int (default 1, do ignore).

## PARAM\_PREFIX\_CLEANUP\_RE

Regular expression (use qr/myregexp/) to clean up names for parameters that are candidates for enums.

## METHOD\_PREFIX\_CLEANUP\_RE

Regular expression (use qr/myregexp/) to clean up get/set method names used for candidates for enums.

## PARAM\_NAME\_ENUM\_EXCLUDE\_RE

Regular expression (use qr/myregexp/) specifying those parameter names that won't be checked to see if they are enums.

# SEE ALSO

"Binding a Java Library (.jar)" from Xamarin, Inc.

[http://docs.xamarin.com/guides/android/advanced_topics/java_integration_overview/binding_a_java_library_(.jar%29/](http://docs.xamarin.com/guides/android/advanced_topics/java_integration_overview/binding_a_java_library_(.jar%29/)

# AUTHOR

Arturo Espinosa, `<arturo.espinosa at xamarin.com>`

# SUPPORT

You can find documentation for this module with the perldoc command.

	perldoc Xam::Binding::Trans

Github project location for source code and bug reports:

[https://github.com/pupitetris/jdh2trans](https://github.com/pupitetris/jdh2trans)

# LICENSE AND COPYRIGHT

Copyright (C) 2013 Xamarin, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.


