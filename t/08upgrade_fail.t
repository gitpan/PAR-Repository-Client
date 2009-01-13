use strict;
use warnings;
use Test::More tests => 11;
BEGIN { use_ok('PAR::Repository::Client') };


chdir('t') if -d 't';
push @INC, qw(lib t/lib);
require RepoMisc;

{
  # successful upgrade
  my $path = File::Spec->catdir('data', 'lib_higher');
  ok(-d $path, 'INC path exists');
  unshift @INC, $path;

  my $client = RepoMisc::client_ok( 'data/repo_with_compatible_module' );

  my $idir = RepoMisc::set_installation_targets($client);
  
  ok(!$client->upgrade_module("FunnyTestModule"), 'FunnyTestModule was not upgraded');
  ok(!$client->error, "no error after non-upgrade") or diag("Error: ".$client->error);
  can_ok('FunnyTestModule', 'funny');
  is(FunnyTestModule->VERSION, '5.68', 'FunnyTestModule VERSION okay'); # the new, non-upgraded one

  ok(!-f File::Spec->catdir($idir, 'FunnyTestModule.pm'), 'Upgraded file does not exist');
}

