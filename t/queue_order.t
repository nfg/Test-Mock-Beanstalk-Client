# vim: set ft=perl

use strict;
use warnings;

use Test::More tests => 3;
use Test::Deep;
use Test::Mock::Beanstalk::Client;
use Test::Warnings;

my $client = Test::Mock::Beanstalk::Client->new();

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

    my $job = $client->reserve();
    cmp_deeply($job->data, "LOW PRIORITY", "Returned job with least delay first");
    #ok($job->delete(), "Deleted job");

    $job = $client->reserve();
    cmp_deeply($job->data, "DELAY:3", "Returned oldest job with matching priority");
    #ok($job->delete(), "Deleted job");

    $job = $client->reserve();
    cmp_deeply($job->data, "DELAY:3 #2", "Returned remaining job");
    #ok($job->delete(), "Deleted job");

    is($client->reserve(0), undef, "No jobs remaining in tube");
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
