#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib 'lib';

my @modules = qw(
    GitBz::Commands
    GitBz::Config
    GitBz::Credentials
    GitBz::Exception
    GitBz::Git
    GitBz::RestClient
);

plan tests => scalar @modules;

for my $module (@modules) {
    use_ok($module) or BAIL_OUT("Failed to load $module");
}

done_testing();
