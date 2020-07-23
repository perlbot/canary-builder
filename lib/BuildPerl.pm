package BuildPerl;

use strict;
use warnings;

use Runner;
use Function::Parameters qw/:std/;
use Git::Wrapper;
use IO::Async::Function;
use Perl::Build;
use Path::Tiny;
use Time::Moment;
use Future;
use Future::AsyncAwait;
use Syntax::Keyword::Try;
use Data::Dumper;

# TODO config?
my $basepath = path('/home/perlbot/perl5/custom/');
my $srcpath = path('/home/perlbot/build/perl5');

fun build_perl($loop, %args) {
  my ($randid, $baseid, $threads) = @args{qw/randid baseid threads/};

  my $function = IO::Async::Function->new(
    code => sub {
      my $logger = fun($data) {
        chomp($data->{line});
        printf("BUILD (%s-%s): %s\n", $baseid, $threads ? 'threaded' : 'unthreaded', $data->{line}); # TODO better logging
      };

      # max an hour
      my $ret_data = Runner::run_code(code => sub {
        my $dst = $basepath->child($baseid . ($threads ? '-threads' : '') );

        Perl::Build->install(
          src_path => $srcpath,
          dst_path => $dst,
          configure_options => [
            '-de',
            '-Dusedevel',
            '-Accflags="-fpie -fPIC -mtune=native -fstack-protector-all -pie -D_FORTIFY_SOURCE=2 -ggdb  -DPERL_EMERGENCY_SBRK"',
            '-Aldflags="-Wl,-z,now -Wl,-zrelro -Wl,-z,noexecstack"',
            '-Duseshrplib',
            '-Dusemymalloc=y',
            '-Uversiononly',
            ($threads ? '-Dusethreads' : ()),
          ],
          test => 1,
          jobs => 4
        );

        $dst->child('.tested')->touch();
      }, logger => $logger, timeout => 60*60, cgroup => "canary-$baseid".($threads?"-threads":""), stdin => "");

      return $ret_data;
    },
  );

  $loop->add($function); # TODO make this take args and be shared/common among all runs instead of this currying stuff?

  # TODO make this take args properly
  my $future = $function->call(args => []);

  return $future;
}

fun clean_git() {
  my $git = Git::Wrapper->new({dir => $srcpath});

  $git->clean({f => 1, d => 1});
  Runner::run_code(code => sub {chdir $srcpath; system("make clean");}, timeout => 240, cgroup => "make-clean-...", stdin => "");
}

fun checkout_git($refid) {
  my $git = Git::Wrapper->new({dir => $srcpath});

  $git->checkout($refid);
}

# TODO move these two functions to a library
fun get_baseid($time, $branch, $randid) {
    return sprintf "%s-%s-%s", $branch, $time, $randid;
}

fun get_perl_bin($time, $branch, $randid, $opts) {
  my $baseid = get_baseid($time, $branch, $randid);

  for my $k (qw(threads quadmath)) {
    next if !defined $opts->{$k} || !$opts->{$k};
    $baseid .= "-$k";
  }

  return $baseid
}

fun build_perls($loop, %args) {
  my $time = $args{datetime} // Time::Moment->now()->strftime("%Y-%m-%d");
  my $randid = $args{randid} // join('', map {chr(65+rand()*26)} 1..5);
  my $branch = $args{branch} // "blead";

  print Dumper(\%args, $time, $randid, $branch);

  my $baseid = get_baseid($time, $branch, $randid);

  my $starting_fut = $loop->new_future;

  my $seq_fut = $starting_fut;

  my @final_futures = ();

  for my $opts ({threads => 0}, {threads => 1}) { # TODO more permutations?
    # pre-create a new future for us to mark as done when we finish
    my $real_fut = $loop->new_future;
    push @final_futures, $real_fut;

    my $next_fut = $seq_fut->followed_by(sub {
        clean_git();
        checkout_git($branch);
        my $fut;
        print "Building?\n";
        unless ($args{skip_build}) {
          $fut = build_perl($loop, baseid => $baseid, randid => $randid, %$opts);
        } else {
          $fut = Future->done();
        }

        my $perlbin = get_perl_bin($time, $branch, $randid, $opts);

        # TODO trigger cpan and fuzz testing here
        $fut->on_ready(async sub {
            try {
              print "INSIDE CPANM! $perlbin\n";
            } catch {
            } finally {
              $real_fut->done(@_); # TODO real data here
            }
        });
        return $fut;
      });

    $seq_fut = $next_fut;
  }

  $starting_fut->done(); # kick it off
  push @final_futures, $seq_fut; # keep from orphaning the final sequence future.

  return Future->wait_all(@final_futures);
}


1;
