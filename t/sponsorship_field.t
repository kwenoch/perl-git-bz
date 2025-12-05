#!/usr/bin/perl

use Modern::Perl;
use Test::More;
use Test::MockModule;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Commands::Attach;
use GitBz::Bug;

# Test plan
plan tests => 6;

# Mock bug data for testing
sub create_mock_bug {
    my %data = @_;
    return bless {
        data => {
            id              => 12345,
            summary         => 'Test bug',
            status          => 'NEW',
            cf_sponsors     => $data{cf_sponsors}     || '',
            cf_sponsorship  => $data{cf_sponsorship}  || '',
            cf_patch_complexity => '',
            depends_on      => [],
        },
        _attachments => [],
    }, 'GitBz::Bug';
}

# Mock commands object
my $mock_commands = {
    client => undef,
};

# Create attach object
my $attach = GitBz::Commands::Attach->new($mock_commands);

# Test 1: cf_sponsorship updated from '---' to 'Sponsored'
{
    my $bug = create_mock_bug(
        cf_sponsors    => 'Old Sponsor',
        cf_sponsorship => '---'
    );

    my $content = "Sponsors: New Sponsor\n";
    my ( $comment, $obsoletes, $updates ) = $attach->parse_bug_updates( $content, $bug );

    is_deeply( $updates->{cf_sponsors}{add}, ['New Sponsor'], 'Sponsors field updated' );
    is( $updates->{cf_sponsorship}, 'Sponsored', 'Sponsorship changed from --- to Sponsored' );
}

# Test 2: cf_sponsorship updated from 'Unsponsored' to 'Sponsored'
{
    my $bug = create_mock_bug(
        cf_sponsors    => '',
        cf_sponsorship => 'Unsponsored'
    );

    my $content = "Sponsors: ACME Corp\n";
    my ( $comment, $obsoletes, $updates ) = $attach->parse_bug_updates( $content, $bug );

    is( $updates->{cf_sponsorship}, 'Sponsored', 'Sponsorship changed from Unsponsored to Sponsored' );
}

# Test 3: cf_sponsorship updated from 'Seeking sponsor' to 'Sponsored'
{
    my $bug = create_mock_bug(
        cf_sponsors    => '',
        cf_sponsorship => 'Seeking sponsor'
    );

    my $content = "Sponsors: ByWater Solutions\n";
    my ( $comment, $obsoletes, $updates ) = $attach->parse_bug_updates( $content, $bug );

    is( $updates->{cf_sponsorship}, 'Sponsored', 'Sponsorship changed from Seeking sponsor to Sponsored' );
}

# Test 4: cf_sponsorship NOT updated when already 'Sponsored'
{
    my $bug = create_mock_bug(
        cf_sponsors    => 'Existing Sponsor',
        cf_sponsorship => 'Sponsored'
    );

    my $content = "Sponsors: Existing Sponsor, New Sponsor\n";
    my ( $comment, $obsoletes, $updates ) = $attach->parse_bug_updates( $content, $bug );

    is( $updates->{cf_sponsorship}, undef, 'Sponsorship not changed when already Sponsored' );
}

# Test 5: cf_sponsorship NOT updated when sponsors field not changed
{
    my $bug = create_mock_bug(
        cf_sponsors    => 'Same Sponsor',
        cf_sponsorship => 'Seeking sponsor'
    );

    my $content = "Status: ASSIGNED\n";
    my ( $comment, $obsoletes, $updates ) = $attach->parse_bug_updates( $content, $bug );

    is( $updates->{cf_sponsorship}, undef, 'Sponsorship not changed when sponsors not updated' );
}

done_testing();
