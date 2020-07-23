#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';

use BuildPerl;

use IO::Async::Loop;

my $loop = IO::Async::Loop->new();

my $fut = BuildPerl::build_perls($loop, skip_build => 1, randid => "EJQFU", time => "2020-07-23");

$fut->get();


