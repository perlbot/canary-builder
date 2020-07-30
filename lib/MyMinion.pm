package MyMinion;

use strict;
use warnings;

use Minion;
use parent 'Exporter';

# TODO config file
our @connection = (Pg => 'postgresql://canary:canarybuilder2387@localhost/canary');

our $minion = Minion->new(@connection);
our @EXPORT=qw/$minion/;

1;