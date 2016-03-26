# See bottom of file for license and copyright information

=begin TML

---+!! package Foswiki::Request

Class to encapsulate request data.

Fields:
   * =action= action requested (view, edit, save, ...)
   * =cookies= hashref whose keys are cookie names and values
               are CGI::Cookie objects
   * =headers= hashref whose keys are header name
   * =method= request method (GET, HEAD, POST)
   * =param= hashref of parameters, both query and body ones
   * =param_list= arrayref with parameter names in received order
   * =path_info= path_info of request (eg. /WebName/TopciName)
   * =remote_address= Client's IP address
   * =remote_user= Remote HTTP authenticated user
   * =secure= Boolean value about use of encryption
   * =server_port= Port that the webserver listens on
   * =uploads= hashref whose keys are parameter name of uploaded
               files
   * =uri= the request uri

The following fields are parsed from the path_info
   * =web= the requested web.  Access using web method
   * =topic= the requested topic. Access using topic

=cut

package Foswiki::Request;
use strict;
use warnings;

use CGI ();
our @ISA = ('CGI');

use Assert;
use Error    ();
use IO::File ();
use CGI::Util qw(rearrange);
use Time::HiRes ();

use constant TRACE => 0;

BEGIN {
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

sub getTime {
    my $this     = shift;
    my $endTime  = [Time::HiRes::gettimeofday];
    my $timeDiff = Time::HiRes::tv_interval( $this->{start_time}, $endTime );
    return $timeDiff;
}

=begin TML

---++ ClassMethod new([$initializer])

Constructs a Foswiki::Request object.
   * =$initializer= - may be a filehandle or hashref.
      * If it's a filehandle, it'll be used to reload the Foswiki::Request
        object. See =save= method. Note: Restore only parameters
      * It can be a hashref whose keys are parameter names. Values may be 
        arrayref's to multivalued parameters. Same note as above.

=cut

sub new {
    my ( $proto, $initializer ) = @_;

    my $this;

    my $class = ref($proto) || $proto;

    $this = {
        action         => '',
        cookies        => {},
        headers        => {},
        method         => undef,
        param          => {},
        param_list     => [],
        path_info      => '',
        remote_address => '',
        remote_user    => undef,
        secure         => 0,
        server_port    => undef,
        start_time     => [Time::HiRes::gettimeofday],
        uploads        => {},
        uri            => '',
        _pathParsed    => undef,
        web            => undef,
        topic          => undef,
    };

    bless $this, $class;

    if ( ref($initializer) eq 'HASH' ) {
        while ( my ( $key, $value ) = each %$initializer ) {
            $this->multi_param(
                -name  => $key,
                -value => ref($value) eq 'ARRAY' ? [@$value] : [$value]
            );
        }
    }
    elsif ( ref($initializer) && UNIVERSAL::isa( $initializer, 'GLOB' ) ) {
        $this->load($initializer);
    }
    return $this;
}

=begin TML

---++ ObjectMethod action([$action]) -> $action


Gets/Sets action requested (view, edit, save, ...)

=cut

sub action {
    my ( $this, $action ) = @_;
    if ( defined $action ) {

        # Record the very first action set in this request. It will be required
        # later if a redirect cache overlays this request.
        $this->{base_action} = $action unless defined $this->{base_action};
        $ENV{FOSWIKI_ACTION} = $this->{action} = $action;
        return $action;
    }
    else {
        return $this->{action};
    }

}

=begin TML

---++ ObjectMethod base_action() -> $action

Get the first action ever set in this request object. This remains
unchanged even if a request cache is unwrapped on to of this request.
The idea is that callers can always find out the action that initiated
the HTTP request. This is required for (for example) checking access
controls.

=cut

sub base_action {
    my $this = shift;
    return defined $this->{base_action}
      ? $this->{base_action}
      : $this->action();
}

=begin TML

---++ ObjectMethod method( [ $method ] ) -> $method

Sets/Gets request method (GET, HEAD, POST).

=cut

sub method {
    return @_ == 1 ? $_[0]->{method} : ( $_[0]->{method} = $_[1] );
}

=begin TML

---++ ObjectMethod pathInfo( [ $path ] ) -> $path

Sets/Gets request path info.

Called without parameters returns current pathInfo.

There is a =path_info()= alias for compatibility with CGI.

Note that the string returned is a *URL encoded byte string*
i.e. it will only contain characters -A-Za-z0-9_.~!*\'();:@&=+$,/?%#[]
If you intend to analyse it, you will probably have to
Foswiki::urlDecode it first.

=cut

*path_info = \&pathInfo;

sub pathInfo {
    return @_ == 1 ? $_[0]->{path_info} : ( $_[0]->{path_info} = $_[1] );
}

=begin TML

---++ ObjectMethod protocol() -> $protocol

Returns 'https' if secure connection. 'http' otherwise.

=cut

# SMELL : review this
sub protocol {
    return $_[0]->secure ? 'https' : 'http';
}

=begin TML

---++ ObjectMethod uri( [$uri] ) -> $uri

Gets/Sets request uri.

=cut

sub uri {
    return @_ == 1 ? $_[0]->{uri} : ( $_[0]->{uri} = $_[1] );
}

=begin TML

---++ ObjectMethod queryString() -> $query_string

Returns query_string part of request uri, if any.

=query_string()= alias provided for compatibility with CGI.

Note that the string returned is a *URL encoded byte string*
i.e. it will only contain characters -A-Za-z0-9_.~!*\'();:@&=+$,/?%#[]
If you intend to analyse it, you will probably have to
Foswiki::urlDecode it first.

=cut

*query_string = \&queryString;

sub queryString {
    my $this = shift;
    my @params;
    foreach my $name ( $this->param ) {
        my $key = Foswiki::urlEncode($name);
        push @params,
          map { $key . "=" . Foswiki::urlEncode( defined $_ ? $_ : '' ) }
          $this->param($name);
    }
    return join( ';', @params );
}

=begin TML

---++ ObjectMethod url( [-full     => 1,
                         -base     => 1,
                         -absolute => 1,
                         -relative => 1, 
                         -path     => 1, 
                         -query    => 1] ) -> $url

Returns many url info. 
   * If called without parameters or with -full => 1 returns full url, e.g. 
     http://mysite.net/view
   * If called with -base => 1 returns base url, e.g. http://foswiki.org
   * -absolute => 1 returns absolute action path, e.g. /cgi-bin/view
   * -relative => 1 returns relative action path, e.g. view
   * -path => 1, -query => 1 also includes path info and query string
     respectively

Note that the path and query components are returned as a *URL encoded byte string*
You will most likely need to Foswiki::urlDecode it for use.

Reasonably compatible with CGI corresponding method. Doesn't support
-rewrite. See Item5914.

=cut

sub url {
    my ( $this, @p ) = @_;

    my ( $relative, $absolute, $full, $base, $path_info, $query ) = rearrange(
        [
            qw(RELATIVE ABSOLUTE FULL BASE), [qw(PATH PATH_INFO)],
            [qw(QUERY_STRING QUERY)],
        ],
        @p
    );
    my $url;
    $full++ if $base || !( $relative || $absolute );
    my $path = $this->pathInfo;
    my $name;

    ## See Foswiki.spec for the difference between ScriptUrlPath and ScriptUrlPaths
    if ( defined $Foswiki::cfg{ScriptUrlPaths}{ $this->{action} } ) {

     # When this is set, it is the complete script path including prefix/suffix.
        $name = $Foswiki::cfg{ScriptUrlPaths}{ $this->{action} };
    }
    else {
        $name = $Foswiki::cfg{ScriptUrlPath} . '/' . $this->{action};

        # Don't add suffix if no script is used.
        $name .= $Foswiki::cfg{ScriptSuffix} if $name;
    }
    $name =~ s(//+)(/)g;
    if ($full) {
        my $vh = $this->header('X-Forwarded-Host') || $this->header('Host');
        $url =
          $vh ? $this->protocol . '://' . $vh : $Foswiki::cfg{DefaultUrlHost};
        return $url if $base;
        $url .= $name;
    }
    elsif ($relative) {
        ($url) = $name =~ m{([^/]+)$};
    }
    elsif ($absolute) {
        $url = $name;
    }
    $url .= $path if $path_info && defined $path;
    my $queryString = $this->queryString();
    $url .= '?' . $queryString if $query && $queryString;
    $url = '' unless defined $url;

    return $url;
}

=begin TML

---++ ObjectMethod secure( [$secure] ) -> $secure

Gets/Sets connection's secure flag.

=cut

sub secure {
    return @_ == 1 ? $_[0]->{secure} : ( $_[0]->{secure} = $_[1] );
}

=begin TML

---++ ObjectMethod remoteAddress( [$ip] ) -> $ip

Gets/Sets client IP address.

=remote_addr()= alias for compatibility with CGI.

=cut

*remote_addr = \&remoteAddress;

sub remoteAddress {
    return @_ == 1
      ? $_[0]->{remote_address}
      : ( $_[0]->{remote_address} = $_[1] );
}

=begin TML

---++ ObjectMethod remoteUser( [$userName] ) -> $userName

Gets/Sets remote user's name.

=remote_user()= alias for compatibility with CGI.

=cut

*remote_user = \&remoteUser;

sub remoteUser {
    return @_ == 1 ? $_[0]->{remote_user} : ( $_[0]->{remote_user} = $_[1] );
}

=begin TML

---++ ObjectMethod serverPort( [$userName] ) -> $userName

Gets/Sets server user's name.

=server_port()= alias for compatibility with CGI.

=cut

*server_port = \&serverPort;

sub serverPort {
    return @_ == 1 ? $_[0]->{server_port} : ( $_[0]->{server_port} = $_[1] );
}

=begin TML

---++ ObjectMethod queryParam( [-name => $name, -value => $value             |
                                -name => $name, -values => [ $v1, $v2, ... ] |
                                $name, $v1, $v2, ...                         |
                                name, [ $v1, $v2, ... ]                     
                               ] ) -> @paramNames | @values | $firstValue

This method is used by engines, during its prepare phase. Should not be used
anywhere else. Since bodyParam must exist and it has different semantics from
param method, this one exists for symmetry, and could be modified in the 
future, so it could be possible to get query and body parameters independently.

=cut

sub queryParam {
    my $this = shift;
    return if $this->method && $this->method eq 'POST';
    return $this->param(@_);
}

=begin TML

---++ ObjectMethod bodyParam( [-name => $name, -value => $value             |
                               -name => $name, -values => [ $v1, $v2, ... ] |
                               $name, $v1, $v2, ...                         |
                               name, [ $v1, $v2, ... ]                     
                              ] ) -> @paramNames | @values | $firstValue

Adds parameters passed within request body to the object.  Should be called
only by engines. Otherwise use param() method.

=cut

sub bodyParam {
    my $this = shift;
    return $this->param(@_);
}

=begin TML

---++ ObjectMethod param( [-name => $name, -value => $value             |
                           -name => $name, -values => [ $v1, $v2, ... ] |
                           $name, $v1, $v2, ...                         |
                           name, [ $v1, $v2, ... ]                     
                           ] ) -> @paramNames | @values | $firstValue

   * Called without parameters returns all parameter names
   * Called only with parameter name or with -name => 'name'
      * In list context returns all associated values (maybe empty list)
      * In scalar context returns first value (maybe undef)
   * Called with name and list of values or with 
     -name => 'name', -value => 'value' or -name => 'name', -values => [ ... ]
     sets parameter value
   * Returns parameter values as UTF-8 encoded binary strings

Resonably compatible with CGI.

*NOTE* this method will assert if it is called in a list context. A list
context might be:
   * in a list of parameters e.g. =my_function( $query->param( ...=
   * assigning to a list e.g. =my @l = $query->param(...=
   * in a loop condition e.g. =foreach ($query->param(...=

The following are *scalar* contexts:
   * =defined($query->param( ...= is OK
   * =lc($query->param( ...= is OK
   * =... if ( $query->param( ...= is OK

In a list context, you should call =multi_param= (fully compatible) to
retrieve list parameters.

=cut

sub multi_param {

    my @list_of_params = param(@_);
    return @list_of_params;
}

sub param {
    my ( $this, @p ) = @_;

    my ( $key, @value ) = rearrange( [ 'NAME', [qw(VALUE VALUES)] ], @p );

    # param() - just return the list of param names
    return @{ $this->{param_list} } unless defined $key;

# list context can be dangerous so warn:
# http://blog.gerv.net/2014.10/new-class-of-vulnerability-in-perl-web-applications
    if ( DEBUG && wantarray ) {
        my ( $package, $filename, $line ) = caller;
        if ( $package ne 'Foswiki::Request' ) {
            ASSERT( 0,
"Foswiki::Request::param called in list context from package $package, $filename line $line, declare as scalar, or call multi_param. "
            );
        }
    }

    if ( defined $value[0] ) {
        push @{ $this->{param_list} }, $key
          unless exists $this->{param}{$key};
        $this->{param}{$key} = ref $value[0] eq 'ARRAY' ? $value[0] : [@value];
    }
    if ( defined $this->{param}{$key} ) {
        return wantarray
          ? @{ $this->{param}{$key} }
          : $this->{param}{$key}->[0];
    }
    else {
        return wantarray ? () : undef;
    }
}

=begin TML

---++ ObjectMethod cookie($name [, $value, $path, $secure, $expires]) -> $value

   * If called  without parameters returns a list of cookie names.
   * If called only with =$name= parameter returns value of cookie 
     with that name or undef if it doesn't exist.
   * If called with defined $value and other  parameters returns a 
     CGI::Cookie  object  created  with those  parameters. Doesn't 
     store this new created cookie within request object. This way 
     for compatibility with CGI.

=cut

sub cookie {
    eval { require CGI::Cookie; 1 } or throw Error::Simple($@);
    my ( $this, @p ) = @_;
    my ( $name, $value, $path, $secure, $expires ) =
      rearrange( [ 'NAME', [qw(VALUE VALUES)], 'PATH', 'SECURE', 'EXPIRES' ],
        @p );
    unless ( defined $value ) {
        return keys %{ $this->{cookies} } unless $name;
        return () unless $this->{cookies}{$name};
        return $this->{cookies}{$name}->value if defined $name && $name ne '';
    }
    return unless defined $name && $name ne '';
    return new CGI::Cookie(
        -name  => $name,
        -value => $value,
        -path  => $path || '/',
        -secure  => $secure  || $this->secure,
        -expires => $expires || abs( $Foswiki::cfg{Sessions}{ExpireAfter} )
    );
}

=begin TML

ObjectMethod cookies( \%cookies ) -> $hashref

Gets/Sets cookies hashref. Keys are cookie names
and values CGI::Cookie objects.

=cut

sub cookies {
    return @_ == 1 ? $_[0]->{cookies} : ( $_[0]->{cookies} = $_[1] );
}

=begin TML

---++ ObjectMethod delete( @paramNames )

Deletes parameters from request.

=Delete()= alias provided for compatibility with CGI

=cut

*Delete = \&delete;

sub delete {
    my $this = shift;
    foreach my $p (@_) {
        next unless exists $this->{param}{$p};
        if ( my $upload = $this->{uploads}{ $this->param($p) } ) {
            $upload->finish;
            CORE::delete $this->{uploads}{ $this->param($p) };
        }
        CORE::delete $this->{param}{$p};
        @{ $this->{param_list} } = grep { $_ ne $p } @{ $this->{param_list} };
    }
}

=begin TML

---++ ObjectMethod deleteAll()

Deletes all parameter name and value(s).

=delete_all()= alias provided for compatibility with CGI.

=cut

*delete_all = \&deleteAll;

sub deleteAll {
    my $this = shift;
    $this->delete( $this->param() );
}

=begin TML

---++ ObjectMethod header([-name => $name, -value  => $value            |
                           -name => $name, -values => [ $v1, $v2, ... ] |
                           $name, $v1, $v2, ...                         |
                           name, [ $v1, $v2, ... ]                     
                           ] ) -> @paramNames | @values | $firstValue

Gets/Sets a header field:
   * Called without parameters returns all header field names
   * Called only with header field name or with -name => 'name'
      * In list context returns all associated values (maybe empty list)
      * In scalar context returns the first value (maybe undef)
   * Called with name and list of values or with 
     -name => 'name', -value => 'value' or -name => 'name', -values => [ ... ]
     sets header field value

*Not compatible with CGI*, since CGI correspondent is a 
response write method. CGI scripts obtain headers from %ENV
or =http= method. %ENV is not available and must be replaced
by calls to this and other methods of this class. =http= is
provided for compatibility, but is deprecated. Use this one
instead.

Calls to CGI =header= method must be replaced by calls to
Foswiki::Response =header= method.

=cut

sub header {
    my ( $this, @p ) = @_;
    my ( $key, @value ) = rearrange( [ 'NAME', [qw(VALUE VALUES)] ], @p );

    return keys %{ $this->{headers} } unless $key;
    $key =~ tr/_/-/;
    $key = lc($key);

    if ( defined $value[0] ) {
        $this->{headers}{$key} =
          ref $value[0] eq 'ARRAY' ? $value[0] : [@value];
    }
    if ( defined $this->{headers}{$key} ) {
        return wantarray
          ? @{ $this->{headers}{$key} }
          : $this->{headers}{$key}->[0];
    }
    else {
        return wantarray ? () : undef;
    }
}

=begin TML

---++ ObjectMethod save( $fh )

Saves object state to filehandle. Object may be loaded later
passing $fh to new constructor or by calling load().

=cut

sub save {
    my ( $this, $fh ) = @_;
    local ( $\, $, ) = ( '', '' );
    foreach my $name ( $this->param ) {
        foreach my $value ( $this->param($name) ) {
            $value = '' unless defined $value;
            next if $name eq '' && $value eq '';    # Item12371
            print $fh Foswiki::urlEncode($name), '=',
              Foswiki::urlEncode($value), "\n";
        }
    }
    print $fh "=\n";
}

=begin TML

---++ ObjectMethod load( $fh )

Loads object state from filehandle, probably created with
a previous save().

=cut

sub load {
    my ( $this, $file ) = @_;
    my %param = ();
    my @plist = ();
    local $/ = "\n";
    while (<$file>) {
        chomp;
        last if /^=$/;
        my ( $key, $value ) =
          map { defined $_ ? Foswiki::urlDecode($_) : $_ } split /=/;

        # Item12956: Split returns only a single entry in array for null values.
        # save sets null values to '',  so load needs to restore '', not undef
        $value = '' unless defined $value;
        if ( exists $param{$key} ) {
            push @{ $param{$key} }, $value;
        }
        else {
            push @plist, $key;
            $param{$key} = [$value];
        }
    }
    foreach my $key (@plist) {
        $this->multi_param( -name => $key, -value => $param{$key} );
    }
}

=begin TML

---++ ObjectMethod upload( $name ) -> $handle

Called with file name parameter returns an open filehandle
to uploaded file.

=cut

sub upload {
    my ( $this, $name ) = @_;
    my $upload = $this->{uploads}{ $this->param($name) };
    return defined $upload ? $upload->handle : undef;
}

=begin TML

---++ ObjectMethod uploadInfo( $fname ) -> $headers

Returns a hashref to information about uploaded 
files as sent by browser.

=cut

sub uploadInfo {
    return $_[0]->{uploads}{ $_[1] }->uploadInfo;
}

=begin TML

---++ ObjectMethod tmpFileName( $fname ) -> $tmpFileName

Returns the name of temporarly created file to store uploaded $fname.

$fname may be obtained by calling =param()= with form field name.

=cut

sub tmpFileName {
    my ( $this, $fname ) = @_;
    return $this->{uploads}{$fname}
      ? $this->{uploads}{$fname}->tmpFileName
      : undef;
}

=begin TML

---++ ObjectMethod uploads( [ \%uploads ] ) -> $hashref

Gets/Sets request uploads field. Keys are uploaded file names,
as sent by browser, and values are Foswiki::Request::Upload objects.

=cut

sub uploads {
    return @_ == 1 ? $_[0]->{uploads} : ( $_[0]->{uploads} = $_[1] );
}

# ======== possible accessors =======
# auth_type
# content_length
# content_type

=begin TML

---++ ObjectMethod http( [$header] ) -> $value DEPRECATED

Called without parameters returns a list of all available header filed names.

Given a field name returns value associated.

http('HTTP_USER_AGENT'); http('User-Agent') and http('User_Agent') 
are equivalent.

Please, use =header()= instead. Present only for compatibility with CGI.

=cut

sub http {
    my ( $this, $p ) = @_;
    if ( defined $p ) {
        $p =~ s/^https?[_-]//i;
        return $this->header($p);
    }
    return $this->header();
}

=begin TML

---++ ObjectMethod https( [$name] ) -> $value || $secure DEPRECATED

Similar to =http()= method above. Called with no parameters returns
secure flag.

Please, use =header()= and =secure()= instead. 
Present only for compatibility with CGI.

=cut

sub https {
    my ( $this, $p ) = @_;
    return !defined $p || $p =~ m/^https$/i ? $this->secure : $this->http($p);
}

=begin TML

---++ ObjectMethod userAgent() -> $userAgent;

Convenience method to get User-Agent string.

=user_agent()= alias provided for compatibility with CGI.

=cut

*user_agent = \&userAgent;

sub userAgent { shift->header('User-Agent') }

=begin TML

---++ ObjectMethod referer()

Convenience method to get Referer uri.

=cut

sub referer { shift->header('Referer') }

=begin TML

---++ ObjectMethod web() -> $baseweb

Gets the complete Web path parsed from the query path, or the topic=
query param.  This either returns a valid parsed web path, or undef.

   * It does not filter out any illegal characters.
   * It does not set a default web.

This is read only.

=cut

sub web {
    my $this = shift;

    unless ( $this->{_pathParsed} ) {
        $this->_establishWebTopic();
    }

    print STDERR "Request->web() returns " . ( $this->{web} || 'undef' ) . "\n"
      if TRACE;
    return $this->{web};

}

=begin TML

---++ ObjectMethod topic() -> $basetopic

Gets the complete topic name parsed from the query path, or the topic=
queryparam.  This either returns a valid parsed topic name, or undef.

   * It does not filter out any illegal characters.
   * It does not set a default topic.

This is read only.

=cut

sub topic {
    my $this = shift;

    unless ( $this->{_pathParsed} ) {
        $this->_establishWebTopic();
    }

    print STDERR "Request->topic() returns "
      . ( $this->{topic} || 'undef' ) . "\n"
      if TRACE;
    return $this->{topic};

}

sub _establishWebTopic {
    my $this = shift;

    # Allow topic= query param to override the path
    my $topicParam = $this->param('topic');

    my $parse = $this->parse($topicParam);

    # Item3270 - here's the appropriate place to enforce spec
    # http://develop.twiki.org/~twiki4/cgi-bin/view/Bugs/Item3270
    $this->{topic} = ucfirst( $parse->{topic} )
      if ( defined $parse->{topic} );

    if ( $topicParam && !$parse->{web} ) {
        $parse = $this->parse();    # Didn't get a web, so try the path
    }
    $this->{web}        = $parse->{web};
    $this->{errors}     = $parse->{errors};
    $this->{pathParsed} = 1;
}

=begin TML

---++ ObjectMethod parse([query path]) -> { web => $web, topic => $topic, errors => (parse error list) }

Parses the rquests query_path and returns a hash of web and topic names.
If passed a query string, it will parse it and return the extracted
web / topic.

*This method cannot set the web and topic parsed from the query path.*

Slash (/) can separate webs, subwebs and topics.
Dot (.) can *only* separate a web path from a topic.
Trailing slash disambiguates a topic from a subweb when both exist with same name.

If any illegal characters are present (matched by NameFilter),
then no results except for parse errors are returned.

webExists and topicExists may be called to disambiguate between subwebs and topics
however the returned web and topic names do not necessarily exist.

Ths following paths are supported:
   * Main            Extracts webname, topic is undef
   * Main/Somename   Extracts webname and topic.
   * Main.Somename   Extracts webname and topic.
   * Main/Somename/  Forces Somename to be a web, if it also exists as a topic

=cut

sub parse {
    my ( $this, $path ) = @_;

    require Foswiki::Sandbox;

    my $query_path = $path || Foswiki::urlDecode( $this->path_info() );
    my $web_path;
    my @errors;

    print STDERR "Processing path ($query_path)\n" if TRACE;

    return {} unless defined $query_path && length $query_path > 1;
    $query_path =~ s{/+}{/}g;    # Remove duplicate slashes
    $query_path =~ s{^/}{}g;     # Remove leading slash

    # trailingSlash Flag - hint that you want the web even if the topic exists
    my $trailingSlash = ( $query_path =~ s/\/$// );

    # Try the simple,  split on dot, maybe it will work.
    my ( $tweb, $ttopic ) = split( /\./, $query_path );
    if ( defined $ttopic ) {

        my $web = Foswiki::Sandbox::untaint( $tweb,
            \&Foswiki::Sandbox::validateWebName );

        my $topic = Foswiki::Sandbox::untaint( $ttopic,
            \&Foswiki::Sandbox::validateTopicName );

        push @errors, 'Web failed validation'   unless defined $web;
        push @errors, 'Topic failed validation' unless defined $topic;

        my $resp = { web => $web, topic => $topic, errors => \@errors };

        #print STDERR Data::Dumper::Dumper( \$resp ) if TRACE;
        return $resp;
    }

    my @parts = split( /\//, $query_path );    # split the path
          #print STDERR Data::Dumper::Dumper( \@parts ) if TRACE;

    my $temptopic;
    my @webs;

    foreach (@parts) {
        print STDERR "Checking $_\n" if TRACE;

        # Lax check on name to eliminate evil characters.
        my $p = Foswiki::Sandbox::untaint( $_,
            \&Foswiki::Sandbox::validateTopicName );
        unless ($p) {
            push @errors, 'Path failed validation';
            my $resp = { web => undef, topic => undef, errors => \@errors };

            #print STDERR Data::Dumper::Dumper( \$resp ) if TRACE;
            return $resp;
        }

        if ( \$_ == \$parts[-1] ) {    # This is the last part of path
            print STDERR "Testing last part web "
              . join( '/', @webs )
              . "topic $p \n"
              if TRACE;

            if ( $trailingSlash
                && $Foswiki::Plugins::SESSION->webExists(
                    join( '/', @webs, $p ) ) )
            {
                print STDERR "Web Exists, Trailing slash, don't check topic: "
                  . join( '/', @webs, $p ) . "\n"
                  if TRACE;

                # It exists in Store as a web
                push @webs, $p;
            }
            elsif (
                $Foswiki::Plugins::SESSION->topicExists(
                    join( '/', @webs ), $p
                )
              )
            {

                print STDERR "Topic Exists"
                  . join( '/', @webs )
                  . "topic  $p \n"
                  if TRACE;

                $temptopic = $p || '';
            }
            elsif (
                $Foswiki::Plugins::SESSION->webExists( join( '/', @webs, $p ) )
              )
            {

                print STDERR "Web Exists " . join( '/', @webs, $p ) . "\n"
                  if TRACE;

                # It exists in Store as a web
                push @webs, $p;
            }
            elsif ($trailingSlash) {
                print STDERR "$p: Not a topic,  trailingSlash - treat as web\n"
                  if TRACE;
                push @webs, $p;
            }
            else {
                print STDERR " $p: Just a topic. " . scalar @webs . "\n"
                  if TRACE;
                $temptopic = $p;
            }
        }
        else {
            $p = Foswiki::Sandbox::untaint( $_,
                \&Foswiki::Sandbox::validateWebName );
            unless ($p) {
                push @errors, 'Path failed validation';
                my $resp = { web => undef, topic => undef, errors => \@errors };
                return $resp;
            }
            else {
                push @webs, $p;
            }
        }
    }
    my $resp =
      { web => join( '/', @webs ), topic => $temptopic, errors => \@errors };

    #print STDERR Data::Dumper::Dumper( \$resp ) if TRACE;
    return $resp;

}

1;
__END__

Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2016 Foswiki Contributors. All Rights Reserved.
Foswiki Contributors are listed in the AUTHORS file in the root of this
distribution. NOTE: Please extend that file, not this notice.

This module is based/inspired on Catalyst framework, and also CGI,
CGI::Simple and HTTP::Headers modules. Refer to
http://search.cpan.org/~mramberg/Catalyst-Runtime-5.7010/lib/Catalyst.pm,
http://search.cpan.org/~lds/CGI.pm-3.29/CGI.pm,
http://search.cpan.org/author/ANDYA/CGI-Simple-1.103/lib/CGI/Simple.pm, and
http://search.cpan.org/~gaas/libwww-perl-5.808/lib/HTTP/Headers.pm
for full credits and license details.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
