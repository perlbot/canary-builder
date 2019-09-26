use strict;
use warnings;
use Test::More;

require_ok('Runner');

my $output = Runner::run_code(code => sub {print "Hi\n";} );

my $time_ran = delete $output->{time_elapsed};
ok(defined($time_ran), "Got time elapsed");
is_deeply($output, {buffer => "Hi\n", exit_signal => 0, exit_code => 0, error => undef}, "output deeply 1");

$output = Runner::run_code(code => sub {sleep(30)}, timeout => 5);

$time_ran = delete $output->{time_elapsed};
ok($time_ran >= 5, "Timed out in good order");
is_deeply($output, {buffer => "", exit_signal => 15, exit_code => 0, error => "Timed out\n"}, "output deeply 2");

done_testing;
