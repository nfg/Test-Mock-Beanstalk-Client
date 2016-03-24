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
has reserved => is => 'rw';
has start => is => 'rw', lazy => 1, default => sub { my $self = shift; return $self->created + $self->delay };
has deleted => is => 'rw';

sub BUILDARGS {
    my ($class, $client, $opt, $job) = @_;

    my $ret = {};
    foreach my $field (qw(priority ttr delay)) {
        $ret->{$field} = exists $opt->{$field} ? $opt->{$field} : $client->$field;
    }
    $ret->{job} = $job;
    $ret->{tube} = $client->_using();
    return $ret;
}

sub state {
    my $self = shift;
    return 'buried' if $self->job->buried;
    return 'reserved' if $self->job->reserved;
    return 'delayed' if $self->start > time();
    return 'ready';
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

sub bury {
    my ($self, $priority) = @_;
    $self->priority($priority);
    $self->job->buried(1);
    $self->job->reserved(0);
    $self->buries( $self->buries + 1 );
    return 1;
}

sub kick {
    my $self = shift;
    $self->job->buried(0);
    $self->start( time() );
    $self->kicks( $self->kicks + 1 );

    return 1;
}

sub release {
    my ($self, $opt) = @_;
    $self->releases( $self->releases + 1 );
    $self->reserved(0);
    if (exists $opt->{delay}) {
        $self->delay($opt->{delay});
    }
    $self->start( time() + $self->delay() );
    $self->priority($opt->{pri}) if exists $opt->{pri};
    return 1;
}

sub reserve {
    my $self = shift;
    $self->start(time() + $self->ttr);
    $self->job->reserved(1);
    $self->reserves( $self->reserves + 1 );
    return $self->job;
}

1;
