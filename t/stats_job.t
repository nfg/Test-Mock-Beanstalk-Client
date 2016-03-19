# vim: set ft=perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Deep;
use Test::Mock::Beanstalk::Client;
use Test::Warnings;

use Data::Printer;
use Beanstalk::Client;

my $client = Test::Mock::Beanstalk::Client->new();
#Beanstalk::Client->new();

my $job = $client->put({}, { data => 1 });
my $stats = $job->stats;
p $stats;

cmp_deeply($stats,
    all(
        isa("Beanstalk::Stats"),
        methods(
            age => 0,
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

note 'ADD MORE TESTS!';
