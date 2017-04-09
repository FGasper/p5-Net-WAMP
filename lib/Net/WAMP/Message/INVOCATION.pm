package Net::WAMP::Message::INVOCATION;

use strict;
use warnings;

use parent qw(
    Net::WAMP::Base::SessionMessage
    Net::WAMP::Base::TowardCallee
);

use Types::Serialiser ();

use constant PARTS => qw( Request  Registration  Metadata  Arguments  ArgumentsKw );

use constant NUMERIC => qw( Request Registration );

1;
