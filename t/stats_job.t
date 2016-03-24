# vim: set ft=perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Deep;
use Test::Mock::Beanstalk::Client;
use Test::Warnings;

use Data::Printer;
use Beanstalk::Client;

my $client = Test::Mock::Beanstalk::Client->new();
#Beanstalk::Client->new();

my $job = $client->put({}, { data => 1 });

cmp_deeply($job->stats,
    all(
        isa("Beanstalk::Stats"),
        methods(
            age => num(0, 1),
            buries => 0,
            delay => 0,
            file => 0,
            id => $job->id,
            kicks => 0,
            pri => 10000,
            releases => 0,
            reserves => 0,
            state   => "ready",
            "time-left" => 0,
            timeouts    => 0,
            ttr => 120,
            tube => "default"
        )
    ),
    "Got expected stats object for new job"
);

$job->release();
$job->bury();
$client->kick_job($job);

cmp_deeply($job->stats,
    all(
        isa('Beanstalk::Stats'),
        methods(
            buries => 1,
            kicks => 1,
            releases => 1,
            reserves => 0,
            state => 'ready',
            ttr => 120,
            tube => 'default'
        )
    ),
    'Got updated stats after playing with job.'
);

my $also_job = $client->reserve(0);
cmp_deeply($also_job,
    all(
        isa('Beanstalk::Job'),
        methods( id => $job->id ),
    ),
    'Successfully reserved job...'
);

cmp_deeply($job->stats,
    methods(
        releases => 1,
        state => 'reserved',
    ),
    '... and is reflected in stats'
);

note 'ADD MORE TESTS!';
