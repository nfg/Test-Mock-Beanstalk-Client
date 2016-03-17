package Test::Mock::Beanstalk::Client;

use 5.008_005;
our $VERSION = '0.01';

use Moo;
use Beanstalk::Job;
use List::MoreUtils 'first_index';
use List::Util 'min';
use YAML::Syck ();

# Public attributes, all from Beanstalk::Client docs
has server  => ( is => 'rw', default => 'localhost:11300' );
#has socket  => ( is => 'rw' );
has delay   => ( is => 'rw', default => 0 );
has ttr     => ( is => 'rw', default => 120 );
has priority    => ( is => 'rw', default => 10_000 );
has encoder => ( is => 'rw', default => \&YAML::Syck::Dump );
has decoder => ( is => 'rw', default => \&YAML::Syck::Load );
has error   => ( is => 'rw' );
has connect_timeout => ( is => 'rw' );
has default_tube => ( is => 'rw', default => 'default' );
has debug   => ( is => 'rw' );

has _watching => ( is => 'rw', default => sub { [] } );
has _using  => (is => 'rw', lazy => 1, default => sub { shift->default_tube }, writer => 'use' );
has _connected => ( is => 'rw', default => 1 );

my %tubes;

my %job_to_tube;

sub _queue_job
{
    my $self = shift;
    my $metadata = shift;
    my $tube = ($tubes{ $self->_using } ||= []);
    $metadata->{start} = time() + $metadata->{delay};

    # Record in hash for easy lookup
    $job_to_tube{ $metadata->{job}->id } = $self->_using;

    my $index = first_index {
        # Keep going 'til we're the higher priority...
        $metadata->{priority} > $_->{priority}
        # Or priority is the same, but we should start sooner
        || ( $metadata->{priority} == $_->{priority} && $metadata->{start} > $_->{start} )
    } @$tube;

    if ($index == -1) { # Empty tube
        push @$tube, $metadata;
        return;
    }

    print "INDEX: $index\n";
    splice @$tube, $index, 0, $metadata;
}

use Data::Printer return_value => 'dump';
sub _next_job
{
    my ($self, $tube_name) = @_;
    my $tube = $tubes{$tube_name};
    return unless $tube;

    my @list =
        sort { $a->{priority} <=> $b->{priority} }
        grep {
            ! $_->{job}->reserved && ! $_->{job}->buried
            && $_->{start} <= time() }
        map {
            # Release any jobs past ttr
            if ($_->{job}->reserved() && $_->{next_try} < time()) {
                $_->{job}->reserved(0);
            }
            $_;
        } @$tube;
    if (scalar @list) {
#        print STDERR "DEBUG: Got multiple ready jobs: " . p(@list);
        return $list[0];
    }
    my $earliest = min map { $_->{start} } @$tube;
    @list = grep { $_->{start} == $earliest } @$tube;
#    if (scalar @list > 1) {
#        print STDERR "DEBUG: Got multiple jobs for same time: " . p(@list);
#    }
    return $list[0];
}

my $job_id = 0;
sub _new_job_id { ++$job_id }

sub put {
    my $self = shift;
    my $opt = shift || {};

    my $metadata = {};
    foreach my $field (qw(priority ttr delay)) {
        $metadata->{$field} = exists $opt->{$field} ? $opt->{$field} : $self->$field;
    }
    my $data = $opt->{data} || $self->encoder->(@_);

    my $job = Beanstalk::Job->new({
            id      => _new_job_id(),
            client  => $self,
            buried  => 0,
            data    => $data
        });
    $metadata->{job} = $job;
    $self->_queue_job($metadata);
    return $job;
}

sub _reserve
{
    my $metadata = shift;
    $metadata->{next_try} = time() + $metadata->{job}->ttr;
    $metadata->{job}->reserved(1);
    return $metadata->{job};
}

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
        return _reserve($next_job);
    }
    elsif ($next_job) {
        # Check our timeout vs. delays.
        my $delay = $next_job->{start} - time();
        if (defined $timeout && $delay <= $timeout) {
            sleep $delay;
            return _reserve($next_job);
        }
        elsif (defined $timeout) {
            sleep($timeout);
            return;
        }
        else {
            # Sleeping indefinitely, but we do have a job waiting.
            sleep($delay);
            return _reserve($next_job);
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

    if (! exists $job_to_tube{$job_id}) {
        return;
    }
    my $tube = $tubes{ $job_to_tube{$job_id} };
    my $job;
    @$tube = grep {
        my $ret = 1;
        if ($_->{job}->id eq $job_id) {
            $ret = 0;
            $job = $_;
        };
        $ret;
    } @$tube;

    return unless $job;

    delete $job_to_tube{$job_id};
    return 1;
}


# Mocking methods
sub connect     { shift->_connected(1) }
sub disconnect  { shift->_connected(0) }
sub watch_only  {
    my $self = shift;
    die "Missing tube!" unless @_;
    $self->_watching(\@_);
}

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
