# See bottom of file for license and copyright information
package Foswiki::Plugins::JQueryPlugin::FOSWIKI;
use v5.14;

use Foswiki::Func;
use Foswiki::Plugins;
use JSON();

use Moo;
use namespace::clean;
extends qw( Foswiki::Plugins::JQueryPlugin::Plugin );

=begin TML

---+ package Foswiki::Plugins::JQueryPlugin::FOSWIKI

This is the perl stub for the jquery.foswiki plugin.

=cut

=begin TML

---++ ClassMethod new( $class, ... )

Constructor

=cut

our %pluginParams = (
    name         => 'Foswiki',
    version      => '2.10',
    author       => 'Michael Daum',
    homepage     => 'http://foswiki.org/Extensions/JQueryPlugin',
    javascript   => ['jquery.foswiki.js'],
    dependencies => [ 'JQUERYPLUGIN', 'JQUERYPLUGIN::MIGRATE', 'livequery' ],
    tags         => 'JQTHEME, JQREQUIRE, JQICON, JQICONPATH, JQPLUGINS',
);

=begin TML

---++ ClassMethod init( $this )

Initialize this plugin by adding the required static files to the html header

=cut

around init => sub {
    my $orig = shift;
    my $this = shift;

    return unless $orig->($this);

    # get exported prefs
    my $prefs = Foswiki::Func::getPreferencesValue('EXPORTEDPREFERENCES') || '';

    # try a little harder for foswiki engines < 1.1
    if ( $Foswiki::Plugins::VERSION < 2.1 ) {

        # defaults since foswiki >= 1.1.0
        $prefs =
'PUBURL, PUBURLPATH, SCRIPTSUFFIX, SCRIPTURL, SCRIPTURLPATH, SERVERTIME, SKIN, SYSTEMWEB, TOPIC, USERNAME, USERSWEB, WEB, WIKINAME, WIKIUSERNAME, NAMEFILTER';
        $prefs .= ', TWISTYANIMATIONSPEED'
          if $Foswiki::cfg{Plugins}{TwistyPlugin}{Enabled};
    }

    # init NAMEFILTER
    unless ( Foswiki::Func::getPreferencesValue('NAMEFILTER') ) {
        Foswiki::Func::setPreferencesValue( 'NAMEFILTER',
            $Foswiki::cfg{NameFilter} );
    }

    # init ATTACHMENTNAMEFILTER
    unless ( Foswiki::Func::getPreferencesValue('ATTACHMENTNAMEFILTER') ) {
        Foswiki::Func::setPreferencesValue( 'ATTACHMENTNAMEFILTER',
            $Foswiki::cfg{AttachmentNameFilter} );
    }

    # add exported preferences to head
    my %prefs = ();
    foreach my $pref ( split( /\s*,\s*/, $prefs ) ) {
        $prefs{$pref} =
          Foswiki::Func::expandCommonVariables( '%' . $pref . '%' );
    }

    # add {ScriptUrlPaths}
    if ( defined $Foswiki::cfg{ScriptUrlPaths} ) {
        %{ $prefs{"SCRIPTURLPATHS"} } = %{ $Foswiki::cfg{ScriptUrlPaths} };
    }
    $prefs{"URLHOST"} = Foswiki::Func::getUrlHost();

    my $text =
        "<script class='\$zone \$id foswikiPreferences' type='text/json'>"
      . JSON::to_json( \%prefs, { pretty => 1, allow_nonref => 1 } )
      . "</script>";

    Foswiki::Func::addToZone( "script", "JQUERYPLUGIN::FOSWIKI::PREFERENCES",
        $text, "JQUERYPLUGIN::FOSWIKI" );
};

1;
__END__

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2010-2016 Foswiki Contributors. Foswiki Contributors
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
