#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';

use BuildPerl;
use Path::Tiny;
use Function::Parameters;

use IO::Async::Loop;
use Logger;

init_logger(); # TODO move this until after arg parsing

# TODO config?
my $basepath = path('/home/perlbot/perl5/custom/');
my $srcpath = path('/home/perlbot/build/perl5');

my %args = (
 #skip_build => 1, randid => "EJQFU", time => "2020-07-23", 
 srcpath => $srcpath, basepath => $basepath
);

my $loop = IO::Async::Loop->new();

my $fut = BuildPerl::build_perls($loop, %args);

$fut->get();


