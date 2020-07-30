#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin.'/../lib';

use MyMinion;

# TODO enqueue jobs

$minion->perform_jobs();

exit 1;