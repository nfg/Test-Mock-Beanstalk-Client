# vim: set ft=perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Deep;
use Test::Mock::Beanstalk::Client;
use Test::Warnings;

if ($ENV{BEANSTALKD_TESTS}) { require Beanstalk::Client }

my $client = $ENV{BEANSTALKD_TESTS} ? Beanstalk::Client->new() : Test::Mock::Beanstalk::Client->new();

subtest 'Checking delay vs. priority' => sub {
    $client->use('tube1');
    $client->watch_only('tube1');

    $client->put({
            delay => 3,
            priority => 1000,
            data => "DELAY:3",
        });
    $client->put({
            delay => 3,
            priority => 1000,
            data => "DELAY:3 #2",
        });
    sleep 1;
    $client->put({
            delay => 0,
            priority => 10_000,
            data => "LOW PRIORITY",
        });

    my $job1 = $client->reserve();
    cmp_deeply($job1->data, "LOW PRIORITY", "Returned job with least delay first");

    my $job2 = $client->reserve();
    cmp_deeply($job2->data, "DELAY:3", "Returned oldest job with matching priority");

    my $job3 = $client->reserve();
    cmp_deeply($job3->data, "DELAY:3 #2", "Returned remaining job");

    is($client->reserve(0), undef, "No jobs remaining in tube");

    $_->delete() for ($job1, $job2, $job3);
};

subtest 'Checking priorities' => sub {
    $client->use('tube2');
    $client->watch_only('tube2');

    $client->put({
            priority => 1000,
            data => "ENTRY 1",
        });
    $client->put({
            priority => 999,
            data => "ENTRY 2",
        });
    $client->put({
            priority => 1001,
            data => "ENTRY 3",
        });
    $client->put({
            priority => 999,
            data => "ENTRY 4",
        });

    my @result;
    while (my $job = $client->reserve(0)) {
        push @result, $job->data;
        $job->delete();
    }
    cmp_deeply(\@result, ['ENTRY 2', 'ENTRY 4', 'ENTRY 1', 'ENTRY 3'], "Jobs returned in expected order given priorities")
        or note "RESULT: " . join(',', @result) . "\nEXPECTED: 'ENTRY 2', 'ENTRY 4', 'ENTRY 1', 'ENTRY 3'";
};

note 'DONE!';
