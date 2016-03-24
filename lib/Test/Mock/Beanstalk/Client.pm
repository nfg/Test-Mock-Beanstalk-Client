package Test::Mock::Beanstalk::Client;

use 5.008_005;
our $VERSION = '0.01';

use Moo;
use Beanstalk::Job;
use List::MoreUtils 'first_index';
use List::Util 'min';
use YAML::Syck ();
use Test::Mock::Beanstalk::MetaJob;

# While developing
use Data::Printer return_value => 'dump';

# Public attributes, all from Beanstalk::Client docs
has server  => ( is => 'rw', default => 'localhost:11300' );
#has socket  => ( is => 'rw' );
has delay   => ( is => 'rw', default => 0 );
has ttr     => ( is => 'rw', default => 120 );
has priority    => ( is => 'rw', default => 10_000 );
has encoder => ( is => 'rw', default => sub { \&YAML::Syck::Dump } );
has decoder => ( is => 'rw', default => sub { \&YAML::Syck::Load } );
has error   => ( is => 'rw' );
has connect_timeout => ( is => 'rw' );
has default_tube => ( is => 'rw', default => 'default' );
has debug   => ( is => 'rw' );

has _watching => ( is => 'rw', lazy => 1, default => sub { [ shift->default_tube ] } );
has _using  => (is => 'rw', lazy => 1, default => sub { shift->default_tube }, writer => 'use' );
has _connected => ( is => 'rw', default => 1 );

my %tubes;

my %job_to_tube;


sub _fetch_job
{
    my $job_id = shift;
    return unless exists $job_to_tube{$job_id};
    foreach (@{ $tubes{ $job_to_tube{$job_id} } }) {
        return $_ if $_->{job}->id eq $job_id;
    }
    delete $job_to_tube{$job_id};
    return;
}
sub _queue_job
{
    my $self = shift;
    my $metadata = shift;
    my $tube = ($tubes{ $self->_using } ||= []);

    # Record in hash for easy lookup
    $job_to_tube{ $metadata->job->id } = $metadata->tube;

    my $index = first_index {
        # Keep going 'til we're the higher priority...
        $metadata->priority > $_->priority
        # Or priority is the same, but we should start sooner
        || ( $metadata->priority == $_->priority && $metadata->start > $_->start )
    } @$tube;

    if ($index == -1) { # Empty tube
        push @$tube, $metadata;
        return;
    }

#    print "INDEX: $index\n";
    splice @$tube, $index, 0, $metadata;
}

sub _next_job
{
    my ($self, $tube_name, $ignore_ttr) = @_;
    my $tube = $tubes{$tube_name};
    return unless $tube;

    # Cleanup
    @$tube = map {
        my @ret;
        if (! $_->deleted) {
            push @ret, $_;
            # Release any jobs past ttr
            if ($_->job->reserved() && $_->start < time()) {
                print STDERR "Releasing job!";
                $_->job->reserved(0);
            }
        }
        @ret;
    } @$tube;

#    foreach my $data (@$tube) {
#        print "RESERVED: " . ($data->{job}->reserved // 0) . " DATA: " . $data->{job}->data;
#        print "\n";
#    }
#
    my @list =
        sort { $a->priority <=> $b->priority }
        grep {
            ! $_->job->reserved && ! $_->job->buried
            && $_->start <= time();
        } @$tube;
    if (scalar @list) {
#        if (scalar @list > 1) {
#            print STDERR "DEBUG: Got multiple ready jobs: " . p(@list);
#        }
        return $list[0];
    }

    my $earliest = min map { $_->start } grep { ! $_->job->reserved() } @$tube;
    @list = grep { $_->start == $earliest } grep { ! $_->job->reserved() } @$tube;
#    if (scalar @list > 1) {
#        print STDERR "DEBUG: Got multiple jobs for same time: " . p(@list);
#    }
    return $list[0];
}

my $job_id = 0;
sub _new_job_id { ++$job_id }

################################################################################
# Mocked methods

sub put {
    my $self = shift;
    my $opt = shift || {};

    my $data = $opt->{data} || $self->encoder->(@_);
    my $job = Beanstalk::Job->new({
            id      => _new_job_id(),
            client  => $self,
            buried  => 0,
            data    => $data
        });
    my $metadata = Test::Mock::Beanstalk::MetaJob->new($self, $opt, $job);
    $self->_queue_job($metadata);
    return $job;
}

sub stats {
    my $self = shift;
    die "FIXME!";
    return Beanstalk::Stats->new({});
}

sub stats_tube {
    my $self = shift;
    my $tube = shift || 'default';
    die "FIXME!";
}

sub stats_job {
    my $self = shift;
    my $job_id = shift;

    my $metadata = _fetch_job($job_id);
    return unless $metadata;
    return $metadata->stats;
}

sub kick {
    my $self = shift;
    my $count = shift || 1;

    while ($count > 0) {
        my $metadata =  die "YARR";
    }
}

sub kick_job {
    my $self = shift;
    my $job = shift;
    my $metadata = _fetch_job($job->id);
    return unless $metadata;
    return $metadata->kick();
}

#sub use {
#    my $self = shift;
#    my $tube = shift;
#
#    return $self->_using($tube);
#}

sub reserve {
    my $self = shift;
    my $timeout = shift;

    my $next_job; # Find next available job, given tubes
    foreach my $tube ( @{ $self->_watching } ) {
        my $job = $self->_next_job($tube);
        next unless ! $next_job || $job->{start} < $next_job->{start};
        $next_job = $job;
    }

    if ($next_job && $next_job->{start} < time()) {
        # Available job; return it.
        return $next_job->reserve();
    }
    elsif ($next_job) {
        # Check our timeout vs. delays.
        my $delay = $next_job->{start} - time();
        if (defined $timeout && $delay <= $timeout) {
            sleep $delay;
            return $next_job->reserve();
        }
        elsif (defined $timeout) {
            sleep($timeout);
            return;
        }
        else {
            # Sleeping indefinitely, but we do have a job waiting.
            sleep($delay);
            return $next_job->reserve();
        }
    }
    elsif (defined $timeout) {
        sleep($timeout);
        return;
    }
    warn "Waiting on beanstalkd in a unit test! Make sure you have a test job waiting.";
    return;
}

sub delete
{
    my $self = shift;
    my $job_id = shift;

    my $metadata = _fetch_job($job_id);
    return unless $metadata;

    $metadata->deleted(1);
    return 1;
}

sub touch {
    my $self = shift;
    my $job_id = shift;

    my $metadata = _fetch_job($job_id);
    return unless $metadata;
    return $metadata->touch();
}

sub release {
    my $self = shift;
    my $job_id = shift;
    my $opt = shift || {};

    my $pri   = exists $opt->{priority} ? $opt->{priority} : $self->priority;
    my $delay = exists $opt->{delay}    ? $opt->{delay}    : $self->delay;

    my $metadata = _fetch_job($job_id);
    return undef unless $metadata;
    return $metadata->release();
}

sub bury {
    my $self = shift;
    my $job_id = shift;
    my $opt = shift || {};

    my $pri = exists $opt->{priority} ? $opt->{priority} : $self->priority;

    my $metadata = _fetch_job($job_id);
    return unless $metadata;
    return $metadata->bury($pri);
}

sub watch {
    my $self = shift;
    my $tube = shift;

    my %tubes = map { $_ => 1 } @{ $self->_watching }, $tube;
    $self->_watching([ keys %tubes ]);
    return 1;
}

sub ignore {
    my $self = shift;
    my $tube = shift;

    my @tubes = grep { $_ ne $tube } @{ $self->_watching };
    $self->_watching(\@tubes);
    return 1;
}

sub watch_only  {
    my $self = shift;
    die "Missing tube!" unless @_;
    $self->_watching(\@_);
    return 1;
}

sub peek { die "peek" }
sub peek_ready {}
sub peek_delayed {}
sub peek_buried {}

sub list_tubes {
}

sub list_tube_used {
    my $self = shift;
    return $self->_using;
}

sub list_tubes_watched
{
}

sub pause_tube {
    my $self = shift;
    my $tube = shift;
    my $delay = shift || 0;
    return 1;
}

# Mocking methods
sub connect     { shift->_connected(1) }
sub disconnect  { shift->_connected(0) }



# Test methods

sub clear_tubes {
    my $self = shift;
    if (@_) {
        delete $tubes{$_} for @_;
    }
    else {
        %tubes = ();
        %job_to_tube = ();
    }
}


1;
__END__

=encoding utf-8

=head1 NAME

Test::Mock::Beanstalk::Client - Replacement for Beanstalk::Client

=head1 SYNOPSIS

  use Test::Mock::Beanstalk::Client;

  my $client = Test::Mock::Beanstalk::Client->new();

  my $job = $client->put({ ttr => 20 }, "data");
  $job->bury();

  $client->kick_job($job->id);

  # And so one

=head1 DESCRIPTION

Test::Mock::Beanstalk::Client is a drop-in replacement for unit tests. Its goal is to be a complete replacement for L<Beanstalk::Client>, albeit for a single process only. No worries about leaking test data, or other processes grabbing your test data from beanstalkd.

=head1 METHODS

In addition to the methods from L<Beanstalk::Client>, it supports the following testing methods:

=over

=item B<clear_tubes ([tubeA, tubeB, ...])>

Call with a list of tubes and data will be purged, or call with no arguments to purge all data.

=back

=head1 AUTHOR

Nigel Gregoire E<lt>nigelgregoire@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2016- Nigel Gregoire

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Beanstalk::Client>

=cut
