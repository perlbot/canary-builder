package CpanmTasks::Utils;

use Dist::BuildProcess;
use Dist::BuildProcess::Driver;
use Dist::BuildProcess::BuildEnv;
use Dist::BuildProcess::CommandPhase;
use Dist::BuildProcess::Targets;

use File::Basename qw(basename);
use Path::Tiny;

use File::Fetch;
use Cwd qw/getcwd/;
use CPAN::Common::Index::MetaDB;

sub dist_url_for {
  my ($for) = @_;
  state $cpan_idx = CPAN::Common::Index::MetaDB->new;
  my ($res) = $cpan_idx->search_packages({package => $for});
  die "No dist for ".$for->{package} unless my $uri = $res->{uri};
  die "Confused by ${uri}" unless $uri =~ m{^cpan:///distfile/(.)(.)(.*)$};
  my $cpan_path = "$1/$1$2/$1$2$3";
  # TODO locate a specific mirror
  return "http://cpanproxy.localhost/authors/id/${cpan_path}";
}


sub fetch_into {
  my ($url, $into) = @_;
  my $ff = File::Fetch->new(uri => $url);
  die File::Fetch->error unless $ff;
  $ff->fetch(to => $into) || die $ff->error;
  return 0;
}

sub extract_file {
  my ($base, $file) = @_;
  #local $CWD = $base;

  # TODO use Archive::Tar or Archive::Zip or something
  if ($file =~ /\.zip/) {
    system(unzip => $file);
  } else {
    system(tar => -xf => $file);
  }
}

sub get_phase_deps {
  my $phase = shift;
  my $module = shift;
  my $opts = shift;
  my $url = dist_url_for($module);
  my $cwd = getcwd();
  my $temp = Path::Tiny->tempdir(TEMPLATE => "module-deps-$module-XXXXXX");

  say $url;
  fetch_into($url, $temp);
  chdir($temp);

  extract_file($temp, basename($url));

  # Find the directory, if it's not the only one in there then we've got a problem.
  ($opts->{build_dir}) = grep {$_->is_dir} $temp->children;

  my $bp = Dist::BuildProcess->new($opts);
  my $deps = $bp->${\($phase."_deps")}(sloppy => 1);

  chdir($cwd); # TODO use a scope guard of some kind, try catch finally?
}

sub 

my $be = Dist::BuildProcess::BuildEnv->new(perl_binary => "/usr/bin/perl", make_binary => "/usr/bin/make");

get_deps("Path::Tiny", {perl => "/usr/bin/perl", install_target => undef, build_dir => "./", build_env => $be});


1;