#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Pod::Markdown;

my $parser = Pod::Markdown->new;
$parser->parse_from_file ('Xam-Binding-Trans/lib/Xam/Binding/Trans.pm', 'README.md') || die;
open my $fd, '>README.md';
print $fd $parser->as_markdown;
close $fd;
