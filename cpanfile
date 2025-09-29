requires 'Modern::Perl';
requires 'Try::Tiny';
requires 'Config::Tiny';
requires 'IPC::Run3';
requires 'Getopt::Long';
requires 'File::HomeDir';
requires 'File::Temp';
requires 'MIME::Base64';
requires 'Exception::Class';
requires 'JSON';
requires 'LWP::UserAgent';

on 'test' => sub {
    requires 'Test::More';
    requires 'Test::Exception';
    requires 'Test::MockModule';
    requires 'TAP::Harness::JUnit';
};
