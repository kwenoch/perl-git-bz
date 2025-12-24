requires 'Modern::Perl';
requires 'Try::Tiny';
requires 'IPC::Run3';
requires 'Getopt::Long';
requires 'File::Temp';
requires 'MIME::Base64';
requires 'Exception::Class';
requires 'JSON';
requires 'LWP::UserAgent';
requires 'Text::UnicodeBox::Table';

on 'test' => sub {
    requires 'IO::String';
    requires 'Test::More';
    requires 'Test::Exception';
    requires 'Test::MockModule';
    requires 'Test::MockObject';
    requires 'Test::Warn';
    requires 'Test::Output';
    requires 'TAP::Harness::JUnit';
};
