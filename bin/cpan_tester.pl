#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';

use InstallModules;
use IO::Async::Loop;

my $loop = IO::Async::Loop->new();

my $fut = InstallModules::read_cpanfile($loop, "/home/perlbot/perlbuut/cpanfile", "/home/perlbot/perl5/custom/blead/bin/perl", "baseidhere");

my $data = $fut->get();
print Dumper($data);
