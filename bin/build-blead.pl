#!perl

use strict;
use warnings;

use lib './lib';

use BuildPerl;

use IO::Async::Loop;

my $loop = IO::Async::Loop->new();

my $fut = BuildPerl::build_perls($loop);

$fut->get();


