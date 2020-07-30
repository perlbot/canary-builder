package MyMinion;

use strict;
use warnings;

use Minion;

our $minion = Minion->new(Pg => 'postgresql://canary:canarybuilder2387@localhost/canary');

1;