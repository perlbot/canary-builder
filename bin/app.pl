#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin.'/../lib';
use Path::Tiny;

use MyMinion;
use BuildPerlTask;
use Function::Parameters qw/:std/; # TODO remove this

# TODO enqueue jobs

my %args; # TODO parse from cli

# TODO move these two functions to a library
fun get_baseid($time, $branch, $randid) {
    return sprintf "%s-%s-%s", $branch, $time, $randid;
}

fun get_perl_id($time, $branch, $randid, $opts) {
  my $baseid = get_baseid($time, $branch, $randid);

  for my $k (qw(threads quadmath)) {
    next if !defined $opts->{$k} || !$opts->{$k};
    $baseid .= "-$k";
  }

  return $baseid;
}

my $time = $args{time} // Time::Moment->now()->strftime("%Y-%m-%d");
my $randid = $args{randid} // join('', map {chr(65+rand()*26)} 1..5);
my $branch = $args{branch} // "blead";
my $basepath = path($args{basepath} // '/home/perlbot/perl5/custom/');
my $srcpath = path($args{srcpath} // '/home/perlbot/build/perl5');

my $baseid = get_baseid($time, $branch, $randid);
my $perlid = get_perl_id($time, $branch, $randid, {threads => 0});

my $prev_perl;

for my $opts ({threads => 0}, {threads => 1}) {
  my $basenotes = {$perlid => 1, srcpath => $srcpath, basepath=>$basepath, options => $opts};

  my $build_id = BuildPerlTask::build_perl($srcpath, $basepath, $perlid, $branch, $opts, $basenotes, $prev_perl);
  $prev_perl = $build_id;

  # TODO schedule cpanm installs
}

$minion->perform_jobs();

exit 1;