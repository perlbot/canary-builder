package Runner;

use strict;
use warnings;
use IPC::Run qw/start pump finish timeout/;
use Time::HiRes qw/usleep utime time/;
use Syntax::Keyword::Try;
use IO::Async::Function;


# quick and dirty readline like thing from a string buffer.  give the first full line preset and rewrite the buffer
sub _get_line {
  my $line;
  ($line, $_[0]) = $_[0] =~ /\A([^\n]*\n)?(.*?)\Z/sm;

  return $line
}

# take in a code ref to run and capture into a local buffer, also call $log_capture_sub for each line output
# returns the full exit_code, signal, full buffer and possibly return value of the sub?
# cgroup is a name prefix for the cgroup to be used when running and later killed
sub run_code {
  my ($code, $log_capture_sub, $timeout, $cgroup_name, $stdin) = +{@_}->@{qw/code logger timeout cgroup stdin/};
  my ($log_buffer, $exit_code, $exit_signal) = ("", 0, 0);
  my ($stdout_buffer, $stderr_buffer) = ("", "");
  my $cgroup_suffix = 'SUFF';

  my ($stdout, $stderr);

  $log_capture_sub //= sub {}; # dummy if not provided

  my $kill_cgroup = sub {
	  # TODO kill
  };

  my $wrapper = sub {
    # TODO move into cgroup and stuff

    # TODO premature optimization
    goto $code;
  };

  my $harness = start $wrapper, \$stdin, \$stdout, \$stderr;

  local $SIG{TERM} = $kill_cgroup;

  my $error;

  my $start = time();
  my $end;
  try {
    while ($harness->pumpable) {
      usleep(100); # try not to chew up the cpu
      $harness->pump_nb;

      my $time = time();
      # eat up any output into the buffers and callbacks
      my $gotout = 0;
      do {
        my $stdout_line = _get_line($stdout);
        my $stderr_line = _get_line($stderr);

        $gotout = defined($stdout_line) || defined($stderr_line);

        if (defined $stdout_line) {
          $log_capture_sub->({line => $stdout_line, time => $time, channel => 'stdout'});
          $log_buffer .= $stdout_line;
          $stdout_buffer .= $stdout_line;
        }
        if (defined $stderr_line) {
          $log_capture_sub->({line => $stderr_line, time => $time, channel => 'stderr'});
          $log_buffer .= $stderr_line;
          $stderr_buffer .= $stderr_line;
        }
      } while($gotout);

      # implement my own time out, for better handling, later.
      if ($timeout && $time - $start > $timeout) {
        die "Timed out\n";
      }
    }
  } catch {
    $error = $@;
  } finally {
    $end = time();

    # try to clean up after ourselves
    $harness->kill_kill();
    $harness->finish();

    # we only care about the first child
    my ($first_child) = $harness->full_results();

    ($exit_code, $exit_signal) = ($first_child >> 8, $first_child & 0xFF);
    $kill_cgroup->();
  }

  return +{exit_code => $exit_code, exit_signal => $exit_signal, buffer => $log_buffer, error => $error, stdout_buffer => $stdout_buffer, stderr_buffer => $stderr_buffer, time_elapsed => $end - $start};
}

1;
