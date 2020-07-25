package BuildPerl;

use v5.24;

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
use Logger;
use InstallModules;
use Capture::Tiny qw/capture/;

fun build_perl($loop, $perlid, %args) {
  my ($randid, $baseid, $threads, $basepath, $srcpath) = @args{qw/randid baseid threads basepath srcpath/};

  state $function = do {
    my $func = IO::Async::Function->new(
      code => sub {
        my ($perlid, $args) = @_;
        my ($randid, $baseid, $threads, $basepath, $srcpath) = $args->@{qw/randid baseid threads basepath srcpath/};
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
      }, logger => sub {$logger->debug("BUILD", $perlid, @_)}, timeout => 60*60, cgroup => "canary-$perlid", stdin => "");

      return $ret_data;
    });

    $loop->add($func);

    $func;
  };

  return $function->call(args => [$perlid, \%args])->get();
}

sub clean_git {
  my ($loop, $perlid, $srcpath) = @_;
  my $git = Git::Wrapper->new({dir => $srcpath});

  $logger->debug("gitclean", $perlid, {line => "Cleaning git..."});

  try {
    $git->clean({f => 1, d => 1});
  } catch {
    $logger->debug("gitclean", $perlid, {line => $@->output, time => time(), channel => "stdout"});
    $logger->error("gitclean", $perlid, {line => $@->error, time => time(), channel => "stderr"});
    $logger->debug("gitclean", $perlid, {line => $@->status, time => time(), channel => "cmdstatus"});

    die "Failed to git";
  }

  state $function = do {
    my $func = IO::Async::Function->new(
      code => sub {
        my ($perlid, $srcpath) = @_;
        Runner::run_code(
          code => sub {
            chdir $srcpath;
            my $output = capture {
              system("make clean");
            }; 
            $logger->debug("makeclean", $perlid, {line => "output: $output"});
            }, 
          timeout => 240, 
          cgroup => "make-clean-$perlid",
          stdin => "", 
          logger => sub {$logger->debug("makeclean", $perlid, @_)}
        );
    });

    $loop->add($func);

    $func;
  };

  return $function->call(args => [$perlid, $srcpath])->get();
}

sub checkout_git {
  my ($loop, $perlid, $srcpath, $refid) = @_;
  my $git = Git::Wrapper->new({dir => $srcpath});

  try {
    $git->checkout($refid);
  } catch {
    $logger->debug("gitcheckout", $perlid, {line => $git->output, time => time(), channel => "stdout"});
    $logger->error("gitcheckout", $perlid, {line => $git->error, time => time(), channel => "stderr"});
    $logger->debug("gitcheckout", $perlid, {line => $git->status, time => time(), channel => "cmdstatus"});
    die "Failed to git"
  }
}

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

  return $baseid
}

fun build_perls($loop, %args) {
  my $time = $args{time} // Time::Moment->now()->strftime("%Y-%m-%d");
  my $randid = $args{randid} // join('', map {chr(65+rand()*26)} 1..5);
  my $branch = $args{branch} // "blead";
  my $srcpath = $args{srcpath} or die "Need srcpath";
  my $basepath = $args{basepath} or die "Need basepath";

  my $baseid = get_baseid($time, $branch, $randid);

  my $starting_fut = $loop->new_future;

  my $seq_fut = $starting_fut;

  $logger->debug("prepare", $baseid, {line => "PREPARED ".Dumper([\%args, $time, $randid, $branch])});

  my @final_futures = ();

  for my $opts ({threads => 0}, {threads => 1}) { # TODO more permutations?
    # pre-create a new future for us to mark as done when we finish
    my $perlid = get_perl_id($time, $branch, $randid, $opts);
    my $real_fut = $loop->new_future;
    push @final_futures, $real_fut;
    $logger->debug("prepare", $perlid, {line => "Setting opts ".Dumper($opts)});

    my $next_fut = $seq_fut->followed_by(async sub {
        try {
          clean_git($loop, $perlid, $srcpath); 
        } catch {
          print "FAILED! $@";
        }
        checkout_git($loop, $perlid, $srcpath, $branch);
        my $fut;
        $logger->debug("prebuild", $perlid, {line => "checking skip_build ".$args{skip_build}});
        unless ($args{skip_build}) {
          $fut = build_perl($loop, baseid => $baseid, randid => $randid, %$opts);
        } else {
          $fut = Future->done();
        }

        # TODO trigger cpan and fuzz testing here
        $fut->on_ready(sub {
            try {
              print "START\n";
              my $fut2 = InstallModules::install_modules($loop, $perlid, $basepath);
              $fut2->get();
              print "END\n";
            } catch {
              $logger->error("cpanmsetup", $perlid, {line=>"Failed to cpanm: $@"})
            } finally {
              $real_fut->done(@_); # TODO real data here
            }
        });
        return $fut;
      });

    $seq_fut = $next_fut;
  }

  $logger->debug("prepare", $baseid, {line => "Futures setup, kick off"});

  $starting_fut->done(); # kick it off
  push @final_futures, $seq_fut; # keep from orphaning the final sequence future.

  return Future->wait_all(@final_futures);
}


1;
