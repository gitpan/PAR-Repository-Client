use strict;
use warnings;
use Config;

BEGIN {eval "require Errno;"; };

use Test::More tests => 3;

my %copy = %Config::Config;
untie(%Config::Config);
$copy{version} = '5.8.7';
$copy{archname} = 'my_arch';
tie %Config::Config => 'Config', \%copy;

use_ok('PAR::Repository::Client');

my @tests = (
	'Math::Symbolic' => {
        'Math-Symbolic-0.502-my_arch-5.8.6.par' => '0.502',
        'Math-Symbolic-0.500-my_arch-5.8.7.par' => '0.500',
        'Math-Symbolic-0.501-my_arch-5.8.7.par' => '0.501',
        'Math-Symbolic-0.501-any_arch-5.8.7.par' => '0.501',
    },
    'Math-Symbolic-0.501-my_arch-5.8.7.par',

	'Math::Symbolic' => {
        'Math-Symbolic-0.502-any_arch-5.8.7.par' => '0.502',
        'Math-Symbolic-0.502-any_arch-any_version.par' => '0.502',
        'Math-Symbolic-0.500-my_arch-5.8.7.par' => '0.500',
        'Math-Symbolic-0.501-my_arch-5.8.7.par' => '0.501',
        'Math-Symbolic-0.501-any_arch-5.8.7.par' => '0.501',
    },
    'Math-Symbolic-0.502-any_arch-5.8.7.par',
);

my $obj = bless {} => 'PAR::Repository::Client';
while (@tests) {
	my $ns = shift @tests;
	my $h  = shift @tests;
    my $expect = shift @tests;
	my $res = $obj->prefered_distribution($ns, $h);
	is($res, $expect);
}
