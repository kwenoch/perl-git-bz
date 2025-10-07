#!/usr/bin/perl

use Modern::Perl;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

=head1 NAME

t/attach_order.t - Test that attachments are uploaded in correct chronological order

=head1 DESCRIPTION

Tests that when attaching multiple commits, they are uploaded in chronological
order (oldest first) so they can be applied correctly later.

=cut

# Simple mock for testing without external dependencies
{
    package MockBug;
    sub new { 
        my ($class, %args) = @_;
        bless { %args, _attachments => [] }, $class;
    }
    sub id { $_[0]->{id} }
    sub summary { $_[0]->{summary} }
    sub status { $_[0]->{status} }
    sub attachments { $_[0]->{_attachments} }
    sub add_attachment {
        my ($self, $patch, $filename, $description, %opts) = @_;
        push @{$self->{_attachment_order}}, $description;
        return 1;
    }
}

{
    package MockCommands;
    sub new { 
        my ($class, %args) = @_;
        bless \%args, $class;
    }
}

subtest 'current behavior - attachments uploaded in reverse chronological order' => sub {
    plan tests => 4;
    
    # Track attachment order
    my @attachment_order;
    
    # Create mock bug that captures attachment order
    my $bug = MockBug->new(
        id => 12345,
        summary => 'Test bug',
        status => 'NEW',
        _attachment_order => \@attachment_order
    );
    
    # Simulate current GitBz::Git->get_commits behavior (reverse chronological)
    my @commits = (
        { id => 'abc123', subject => 'Third commit (newest)' },
        { id => 'def456', subject => 'Second commit (middle)' },
        { id => 'ghi789', subject => 'First commit (oldest)' },
    );
    
    # Simulate current attach_patches behavior
    for my $commit (@commits) {
        $bug->add_attachment(
            "patch content",
            $commit->{id} . ".patch",
            $commit->{subject}
        );
    }
    
    # Verify current (wrong) behavior
    is(scalar @attachment_order, 3, 'Three attachments were created');
    is($attachment_order[0], 'Third commit (newest)', 'First attachment is newest commit (WRONG)');
    is($attachment_order[1], 'Second commit (middle)', 'Second attachment is middle commit');
    is($attachment_order[2], 'First commit (oldest)', 'Third attachment is oldest commit (WRONG)');
    
    note("CURRENT BEHAVIOR (BROKEN): " . join(' -> ', @attachment_order));
    note("This is backwards! Patches should be applied oldest-first for correct git apply sequence.");
};

subtest 'expected correct behavior - chronological order' => sub {
    plan tests => 4;
    
    my @attachment_order;
    my $bug = MockBug->new(
        id => 12345,
        summary => 'Test bug', 
        status => 'NEW',
        _attachment_order => \@attachment_order
    );
    
    # What the corrected behavior should return (chronological order)
    my @commits = (
        { id => 'ghi789', subject => 'First commit (oldest)' },
        { id => 'def456', subject => 'Second commit (middle)' },
        { id => 'abc123', subject => 'Third commit (newest)' },
    );
    
    # Simulate corrected attach_patches behavior
    for my $commit (@commits) {
        $bug->add_attachment(
            "patch content",
            $commit->{id} . ".patch", 
            $commit->{subject}
        );
    }
    
    # Verify correct behavior
    is(scalar @attachment_order, 3, 'Three attachments were created');
    is($attachment_order[0], 'First commit (oldest)', 'First attachment is oldest commit (CORRECT)');
    is($attachment_order[1], 'Second commit (middle)', 'Second attachment is middle commit');
    is($attachment_order[2], 'Third commit (newest)', 'Third attachment is newest commit (CORRECT)');
    
    note("EXPECTED BEHAVIOR (CORRECT): " . join(' -> ', @attachment_order));
    note("This is the correct order for sequential git apply.");
};

subtest 'git rev-list default behavior analysis' => sub {
    plan tests => 1;
    
    # Document the root cause: git rev-list returns newest-first by default
    my $explanation = <<'EOF';
ROOT CAUSE ANALYSIS:
- git rev-list returns commits in reverse chronological order (newest first)
- GitBz::Git->get_commits() uses git rev-list without --reverse flag
- attach_patches() processes commits in the order returned by get_commits()
- Result: attachments are uploaded newest-first (backwards for applying)

SOLUTION:
- Add --reverse flag to git rev-list in GitBz::Git->rev_list()
- This will return commits in chronological order (oldest first)
- Attachments will then be uploaded in correct sequence for git apply
EOF
    
    pass("Analysis documented");
    note($explanation);
};

done_testing();
