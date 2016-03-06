# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::PageCache::DBI::PostgreSQL

Implements a Foswiki::PageCache::DBI using postgresql

=cut

package Foswiki::PageCache::DBI::PostgreSQL;
use v5.14;

use Moo;
extends qw(Foswiki::PageCache::DBI);

=begin TML

---++ ClassMethod new( ) -> $object

Construct a new page cache and makes sure the database is ready

=cut

has database => (
    is      => 'rw',
    lazy    => 1,
    default => $Foswiki::cfg{Cache}{DBI}{PostgreSQL}{Database} || 'foswiki',
);
has host => (
    is      => 'rw',
    lazy    => 1,
    default => $Foswiki::cfg{Cache}{DBI}{PostgreSQL}{Host} || 'localhost',
);
has port => (
    is      => 'rw',
    lazy    => 1,
    default => $Foswiki::cfg{Cache}{DBI}{PostgreSQL}{Port} || '',
);

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    return $orig->(
        $class,
        username => $Foswiki::cfg{Cache}{DBI}{PostgreSQL}{Username},
        password => $Foswiki::cfg{Cache}{DBI}{PostgreSQL}{Password},
        @_,
    );
};

sub BUILD {
    my $this = shift;

    my $dsn = 'dbi:Pg:dbname=' . $this->database;
    $dsn .= ';host=' . $this->host;
    $dsn .= ';port=' . $this->port if $this->port;

    $this->dsn($dsn);

    return $this->init;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2012 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
