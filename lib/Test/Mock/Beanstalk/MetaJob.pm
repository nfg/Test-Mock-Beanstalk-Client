package Test::Mock::Beanstalk::MetaJob;

# This package contains information about jobs.
# It's meant to provide the data for "stats-job", as well
# as internal data used by the client.

use Moo;
use Beanstalk::Stats;

# Job attributes manipulated by caller.
has [qw(priority ttr delay)] => ( is => 'rw', required => 1 );
has job => is => 'ro', required => 1; # weak_ref ?
has tube => is => 'ro', required => 1;
# Stats about job
has [qw(buries kicks releases reserves timeouts)] => is => 'rw', default => sub { 0 };

# My data
has created => is => 'ro', default => sub { time() };
has start => is => 'rw', lazy => 1, default => sub { my $self = shift; return $self->created + $self->delay };
has deleted => is => 'rw';

sub BUILDARGS {
    my ($class, $client, $opt, $job) = @_;

    my $ret = {};
    foreach my $field (qw(priority ttr delay)) {
        $ret->{$field} = exists $opt->{$field} ? $opt->{$field} : $client->$field;
    }
    $ret->{job} = $job;

#    $ret->{stats}{file} = '';
    $ret->{tube} = $client->_using();
    return $ret;
}

sub state {
    my $self = shift;
    return 'buried' if $self->job->buried;
    return 'reserved' if $self->job->reserved;
    return 'ready'; # FIXME: Handle delayed
}

sub stats {
    my $self = shift;
    my $ret = {};
    $ret->{$_} = $self->$_() for qw(age buries delay kicks pri releases reserves timeouts state ttr tube);
    $ret->{file} = 0; # FIXME: WHat's "file"?
    $ret->{id} = $self->job->id;
    $ret->{pri} = $self->priority;
    $ret->{"time-left"} = 0;
    if ($self->job->reserved) {
        $ret->{"time-left"} = time() - $self->start;
    }
    return Beanstalk::Stats->new($ret);
}

sub age {
    my $self = shift;
    return time() - $self->created;
}

sub pri { shift->priority }


1;
