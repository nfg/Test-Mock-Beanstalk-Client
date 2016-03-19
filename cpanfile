requires 'perl', '5.008005';
requires 'Beanstalk::Client';
requires 'Moo';
requires 'List::Util';
requires 'List::MoreUtils';
requires 'YAML::Syck';

# requires 'Some::Module', 'VERSION';

on test => sub {
    requires 'Test::More', '0.96';
    requires 'Test::Warnings';
    requires 'Test::Deep';
};
