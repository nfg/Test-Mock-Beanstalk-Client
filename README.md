# NAME

Test::Mock::Beanstalk::Client - Replacement for Beanstalk::Client

# SYNOPSIS

    use Test::Mock::Beanstalk::Client;

    my $client = Test::Mock::Beanstalk::Client->new();

    my $job = $client->put({ ttr => 20 }, "data");
    $job->bury();

    $client->kick_job($job->id);

    # And so one

# DESCRIPTION

Test::Mock::Beanstalk::Client is a drop-in replacement for unit tests. Its goal is to be a complete replacement for [Beanstalk::Client](https://metacpan.org/pod/Beanstalk::Client), albeit for a single process only. No worries about leaking test data, or other processes grabbing your test data from beanstalkd.

# METHODS

In addition to the methods from [Beanstalk::Client](https://metacpan.org/pod/Beanstalk::Client), it supports the following testing methods:

- **clear\_tubes (\[tubeA, tubeB, ...\])**

    Call with a list of tubes and data will be purged, or call with no arguments to purge all data.

# AUTHOR

Nigel Gregoire &lt;nigelgregoire@gmail.com>

# COPYRIGHT

Copyright 2016- Nigel Gregoire

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[Beanstalk::Client](https://metacpan.org/pod/Beanstalk::Client)
