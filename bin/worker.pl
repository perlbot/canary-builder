#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin.'/../lib';
use Path::Tiny;

use MyMinion;
use BuildPerlTask;
use CpanmTasks;
use Function::Parameters qw/:std/; # TODO remove this

#$minion->perform_jobs();
my $worker = $minion->worker;
$worker->status->{jobs} = 2;
$worker->run;

exit 1;
