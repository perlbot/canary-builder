#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin.'/../lib';

use Mojolicious::Lite;
use MyMinion;

plugin Minion => @MyMinion::connection;
plugin 'Minion::Admin';
 
app->start;

exit 1;