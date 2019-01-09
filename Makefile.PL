use strict;
use warnings;
 
use ExtUtils::MakeMaker;
 
WriteMakefile(
        NAME          => 'Mojo::Recache',
        AUTHOR        => [q{Stefan Adams <stefan@adams.fm>}],
        VERSION_FROM  => 'lib/Mojo/Recache.pm',
        ABSTRACT_FROM => 'lib/Mojo/Recache.pm',
        PL_FILES      => {},
        PREREQ_PM     => {
                'Mojolicius' => 8.11,
                'Storable' => 0,
                'Minion' => 9.07,
                'B::Deparse' => 0,
                'Data::Structure::Util' => 0,
        },
        dist          => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
        clean         => { FILES => 'Mojo-Recache-*' },
);