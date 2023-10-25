package BuildPerlTask;

use strict;
use warnings;

use MyMinion;
use Path::Tiny;
use Runner;
use Git::Wrapper;
use Perl::Build;
use Time::Moment;
use Syntax::Keyword::Try;
use Data::Dumper;

$minion->add_task(clean_git => sub {
  my ($job, $srcpath, $perlid) = @_;
  # Wait until we're done with the git repo
  sleep 1 until $minion->lock('git_repo_lock_'.$srcpath, 7200, {limit => 1});
  sleep 1 until $minion->lock('build_'.$perlid, 7200, {limit => 1});
    
  my $git = Git::Wrapper->new({dir => $srcpath});

  # TODO log this
  # $logger->debug("gitclean", $perlid, {line => "Cleaning git..."});

  try {
    $git->clean({f => 1, d => 1});
  } catch {
    #$logger->debug("gitclean", $perlid, {line => $@->output, time => time(), channel => "stdout"});
    #$logger->error("gitclean", $perlid, {line => $@->error, time => time(), channel => "stderr"});
    #$logger->debug("gitclean", $perlid, {line => $@->status, time => time(), channel => "cmdstatus"});
    $minion->unlock("git_repo_lock_".$srcpath);
    $minion->unlock("build_".$perlid);
    die "Failed to git ".$@->error;
  # Don't unlock the repo yet!
  }

  # TODO check the output of this
  Runner::run_code(
    code => sub {
      chdir $srcpath;
      exec("make clean");
    }, 
    timeout => 240, 
    cgroup => "make-clean-$perlid",
    stdin => "", 
    logger => sub {print "$perlid: makeclean: ".$_[0]->{line}; },
    #logger => sub {$logger->debug("makeclean", $perlid, @_)}
  );
  
  $job->finish("Cleaned git for $perlid in $srcpath");
});

$minion->add_task(checkout_git => sub {
  my ($job, $srcpath, $perlid, $refid) = @_;

  if ($minion->lock('git_repo_lock_'.$srcpath, 0) || $minion->lock('build_'.$perlid, 0)) {
    my $repolock = $minion->lock('git_repo_lock_'.$srcpath, 0);
    my $buildlock = $minion->lock('build_'.$perlid, 0);
    
    if ($repolock) {
      $minion->unlock('build_'.$perlid);
    }

    die "Locks were invalidated before checkout $srcpath $perlid";
  }

  my $git = Git::Wrapper->new({dir => $srcpath});

  try {
    $git->checkout($refid);
  } catch {
    #$logger->debug("gitcheckout", $perlid, {line => $git->output, time => time(), channel => "stdout"});
    #$logger->error("gitcheckout", $perlid, {line => $git->error, time => time(), channel => "stderr"});
    #$logger->debug("gitcheckout", $perlid, {line => $git->status, time => time(), channel => "cmdstatus"});
    $minion->unlock("git_repo_lock_".$srcpath);
    $minion->unlock("build_".$perlid);

    die "Failed to git checkout ".$@->error;
  }

  $job->finish("Successfully checked out $refid");
});

$minion->add_task(build_perl => sub {
  my ($job, $srcpath, $perlid, $basepath, $opts) = @_;

  if ($minion->lock('git_repo_lock_'.$srcpath, 0) || $minion->lock('build_'.$perlid, 0)) {
    my $repolock = $minion->lock('git_repo_lock_'.$srcpath, 0);
    my $buildlock = $minion->lock('build_'.$perlid, 0);
    
    if ($repolock) {
      $minion->unlock('build_'.$perlid);
    }

    die "Locks were invalidated before build $srcpath $perlid";
  }
  
  try {
    my $dst = path($basepath)->child($perlid);

    my $ret_data = Runner::run_code(code => sub {
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
          ($opts->{threads} ? '-Dusethreads' : ()),
        ],
        test => 1,
        jobs => 2
      );

      $dst->child('.tested')->touch();
    }, logger => sub {print "$perlid: ".$_[0]->{line}; }, timeout => 60*60, cgroup => "canary-$perlid", stdin => "");


  } catch {
    die $@; # rethrow everything
  } finally {
    # always unlock the repo
    $minion->unlock('git_repo_lock_'.$srcpath);
    $minion->unlock('build_'.$perlid);
  }

});

$minion->add_task(record_perl_dashv => sub {
  my ($job, $perlid, $basepath) = @_;

  my $perlbin = path($basepath)->child($perlid)->child("bin");
  my ($perlexe) = $perlbin->children(qr/^perl5/);


  # TODO check the output of this
  my $result = Runner::run_code(
    code => sub {
      exec($perlexe, '-V');
    }, 
    timeout => 240,
    cgroup => "perl-dashv-$perlid",
    stdin => "", 
    logger => sub {print "$perlid-dashv: ".$_[0]->{line}; },
  );

  # TODO call Logger->... for saving this

  if ($result->{exit_code}) {
    $job->fail("Failed to -V: ".$result->{exit_code}." ".$result->{error});
  } else {
    $job->finish($result->{buffer});
  }


});

sub build_perl {
  my ($srcpath, $basepath, $perlid, $branch, $opts, $basenotes, $real_parent) = @_;

  my $cleangit_id = $minion->enqueue(clean_git => [$srcpath, $perlid] => {notes => $basenotes, parents => [$real_parent // ()]});
  my $checkoutgit_id = $minion->enqueue(checkout_git => [$srcpath, $perlid, $branch] => {notes => $basenotes, parents => [$cleangit_id]});
  my $build_id = $minion->enqueue(build_perl => [$srcpath, $perlid, $basepath, $opts] => {notes => $basenotes, parents => [$checkoutgit_id]});
  $minion->enqueue(record_perl_dashv => [$perlid, $basepath] => {notes => $basenotes, parents => [$build_id]});

  return $build_id;
}

1;