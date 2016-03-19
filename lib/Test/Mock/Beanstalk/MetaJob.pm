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
    return 'BURIED' if $self->job->buried;
    return 'RESERVED' if $self->job->reserved;
    return 'READY'; # FIXME: Handle delayed
}

sub stats {
    my $self = shift;
    my $ret = {};
    $ret->{$_} = $self->$_() for qw(age buries delay kicks releases reserves timeouts state ttr tube);
    $ret->{file} = '???';
    $ret->{id} = $self->job->id;
    return Beanstalk::Stats->new($ret);
}

1;
