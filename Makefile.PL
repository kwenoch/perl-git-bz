use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'GitBz',
    VERSION      => '0.1.0',
    EXE_FILES    => ['bin/git-bz'],
    PREREQ_PM    => {
        'Modern::Perl'     => 0,
        'Try::Tiny'        => 0,
        'Config::Tiny'     => 0,
        'IPC::Run3'        => 0,
        'Getopt::Long'     => 0,
        'File::HomeDir'    => 0,
        'File::Temp'       => 0,
        'MIME::Base64'     => 0,
        'Exception::Class' => 0,
        'JSON'             => 0,
        'LWP::UserAgent'   => 0,
    },
    TEST_REQUIRES => {
        'Test::More'      => 0,
        'Test::Exception' => 0,
    },
    META_MERGE => {
        resources => {
            repository => 'https://github.com/example/git-bz-perl',
        },
    },
);
